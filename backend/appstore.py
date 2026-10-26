"""Checks what the App Store signs: transactions from the phone and server notifications.

Both arrive as JWS (ES256) whose `x5c` header carries the signing chain: a leaf, Apple's
intermediate, and Apple Root CA - G3. A JWS is trusted when the intermediate was issued
by the root below (which ships with the code, so no App Store Connect keys are needed),
the leaf by the intermediate, both carry Apple's marker extensions, both were valid when
the data was signed, and the leaf's key verifies the signature. This is what Apple's
App Store Server Library does offline (it adds an OCSP revocation check online).

Transactions bought with the StoreKit configuration file in Xcode are signed by a local
certificate instead. They are refused unless APP_STORE_ACCEPT_XCODE=1, which is ignored
on Lambda, so a local backend can be tested with the simulator.
"""

import base64
import binascii
import json
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import cache

from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature

BUNDLE_ID = "app.ironsage.IronSage"
# The "IronSage Coach" subscription group.
PRODUCT_IDS = frozenset({"app.ironsage.coach.monthly", "app.ironsage.coach.yearly"})

# https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
# SHA-256 fingerprint:
# 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79
APPLE_ROOT_CA_G3 = b"""-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----
"""

# Apple marks the certificates that sign App Store data with these extensions.
LEAF_MARKER = x509.ObjectIdentifier("1.2.840.113635.100.6.11.1")
INTERMEDIATE_MARKER = x509.ObjectIdentifier("1.2.840.113635.100.6.2.1")


class VerificationError(Exception):
    """The data was not signed by the App Store, or is not for this app."""


@cache
def trusted_roots() -> tuple[x509.Certificate, ...]:
    return (x509.load_pem_x509_certificate(APPLE_ROOT_CA_G3),)


def accepts_xcode() -> bool:
    return os.getenv("APP_STORE_ACCEPT_XCODE") == "1" and not os.getenv("AWS_LAMBDA_FUNCTION_NAME")


def _b64url(part: str) -> bytes:
    return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))


def _certificate(encoded: object) -> x509.Certificate:
    if not isinstance(encoded, str):
        raise VerificationError("Malformed certificate chain")
    try:
        return x509.load_der_x509_certificate(base64.b64decode(encoded, validate=True))
    except (binascii.Error, ValueError) as error:
        raise VerificationError("Malformed certificate chain") from error


def _has_extension(certificate: x509.Certificate, oid: x509.ObjectIdentifier) -> bool:
    try:
        certificate.extensions.get_extension_for_oid(oid)
    except x509.ExtensionNotFound:
        return False
    return True


def _check_chain(chain: list, signed_at: datetime) -> x509.Certificate:
    """Returns the leaf certificate once the chain leads to a trusted root."""
    if len(chain) != 3:
        raise VerificationError("Unexpected certificate chain")
    leaf, intermediate = _certificate(chain[0]), _certificate(chain[1])
    # The root in the header is ignored: the intermediate must chain to ours.
    if not any(_issued_by(intermediate, root) for root in trusted_roots()):
        raise VerificationError("Not signed by Apple")
    if not _issued_by(leaf, intermediate):
        raise VerificationError("Broken certificate chain")
    if not _has_extension(intermediate, INTERMEDIATE_MARKER) or not _has_extension(
        leaf, LEAF_MARKER
    ):
        raise VerificationError("Not an App Store certificate")
    for certificate in (leaf, intermediate):
        if not certificate.not_valid_before_utc <= signed_at <= certificate.not_valid_after_utc:
            raise VerificationError("Certificate not valid when signed")
    return leaf


def _issued_by(certificate: x509.Certificate, issuer: x509.Certificate) -> bool:
    try:
        certificate.verify_directly_issued_by(issuer)
    except (ValueError, TypeError, InvalidSignature):
        return False
    return True


def _verify_signature(leaf: x509.Certificate, signing_input: bytes, signature: bytes) -> None:
    key = leaf.public_key()
    if not isinstance(key, ec.EllipticCurvePublicKey) or key.curve.name != "secp256r1":
        raise VerificationError("Unexpected signing key")
    if len(signature) != 64:
        raise VerificationError("Malformed signature")
    der = encode_dss_signature(
        int.from_bytes(signature[:32], "big"), int.from_bytes(signature[32:], "big")
    )
    try:
        key.verify(der, signing_input, ec.ECDSA(hashes.SHA256()))
    except InvalidSignature as error:
        raise VerificationError("Bad signature") from error


def decode(jws: str, *, allow_xcode: bool = False) -> dict:
    """The payload of a JWS the App Store signed; raises VerificationError otherwise."""
    try:
        header_part, payload_part, signature_part = jws.split(".")
        header = json.loads(_b64url(header_part))
        payload = json.loads(_b64url(payload_part))
        signature = _b64url(signature_part)
    except (ValueError, binascii.Error) as error:
        raise VerificationError("Malformed JWS") from error
    if not isinstance(header, dict) or not isinstance(payload, dict):
        raise VerificationError("Malformed JWS")
    if header.get("alg") != "ES256":
        raise VerificationError("Unexpected algorithm")
    chain = header.get("x5c")
    if not isinstance(chain, list) or not chain:
        raise VerificationError("Missing certificate chain")
    signing_input = f"{header_part}.{payload_part}".encode()

    if payload.get("environment") == "Xcode":
        if not allow_xcode:
            raise VerificationError("Transactions from Xcode are only accepted locally")
        leaf = _certificate(chain[0])
    else:
        signed_at = _timestamp(payload.get("signedDate")) or datetime.now(timezone.utc)
        leaf = _check_chain(chain, signed_at)
    _verify_signature(leaf, signing_input, signature)
    return payload


def _timestamp(milliseconds: object) -> datetime | None:
    """App Store dates are milliseconds since 1970."""
    if milliseconds is None:
        return None
    if not isinstance(milliseconds, int | float) or isinstance(milliseconds, bool):
        raise VerificationError("Malformed date")
    return datetime.fromtimestamp(milliseconds / 1000, timezone.utc)


@dataclass(frozen=True)
class Transaction:
    transaction_id: str
    original_transaction_id: str
    product_id: str
    environment: str
    purchased_at: datetime
    expires_at: datetime
    # Set when Apple refunded the purchase or Family Sharing access ended.
    revoked_at: datetime | None


def verify_transaction(jws: str) -> Transaction:
    """A signed transaction of one of this app's coach subscriptions."""
    payload = decode(jws, allow_xcode=accepts_xcode())
    if payload.get("bundleId") != BUNDLE_ID:
        raise VerificationError("Transaction is for another app")
    if payload.get("productId") not in PRODUCT_IDS:
        raise VerificationError("Not a coach subscription")
    if payload.get("type") != "Auto-Renewable Subscription":
        raise VerificationError("Not an auto-renewable subscription")
    try:
        transaction_id = str(payload["transactionId"])
        original_transaction_id = str(payload["originalTransactionId"])
        purchased_at = _timestamp(payload["purchaseDate"])
        expires_at = _timestamp(payload["expiresDate"])
    except KeyError as error:
        raise VerificationError(f"Transaction without {error.args[0]}") from error
    if purchased_at is None or expires_at is None:
        raise VerificationError("Transaction without dates")
    return Transaction(
        transaction_id=transaction_id,
        original_transaction_id=original_transaction_id,
        product_id=payload["productId"],
        environment=str(payload.get("environment", "Production")),
        purchased_at=purchased_at,
        expires_at=expires_at,
        revoked_at=_timestamp(payload.get("revocationDate")),
    )


@dataclass(frozen=True)
class Notification:
    """An App Store Server Notification V2 (only what the entitlement needs)."""

    notification_type: str
    subtype: str | None
    transaction: Transaction | None
    # While Apple retries a failed renewal the subscriber keeps access until then.
    grace_period_expires_at: datetime | None


def verify_notification(signed_payload: str) -> Notification:
    payload = decode(signed_payload)
    data = payload.get("data") or payload.get("summary") or {}
    if not isinstance(data, dict) or data.get("bundleId") != BUNDLE_ID:
        raise VerificationError("Notification is for another app")
    transaction = None
    if isinstance(data.get("signedTransactionInfo"), str):
        transaction = verify_transaction(data["signedTransactionInfo"])
    grace_period_expires_at = None
    if isinstance(data.get("signedRenewalInfo"), str):
        renewal = decode(data["signedRenewalInfo"], allow_xcode=accepts_xcode())
        grace_period_expires_at = _timestamp(renewal.get("gracePeriodExpiresDate"))
    return Notification(
        notification_type=str(payload.get("notificationType", "")),
        subtype=payload.get("subtype"),
        transaction=transaction,
        grace_period_expires_at=grace_period_expires_at,
    )
