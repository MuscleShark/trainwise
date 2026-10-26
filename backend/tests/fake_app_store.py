"""A stand-in for the App Store's signing chain, for tests.

Builds a root, an intermediate and a leaf shaped like Apple's (with its marker
extensions) and signs JWS the way the App Store does; tests trust this root instead of
Apple's.
"""

import base64
import json
import time
import uuid
from datetime import datetime, timedelta, timezone

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.x509.oid import NameOID

import appstore

MONTHLY = "app.ironsage.coach.monthly"
YEARLY = "app.ironsage.coach.yearly"
DAY_MS = 24 * 60 * 60 * 1000


def now_ms() -> int:
    return int(time.time() * 1000)


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def name(common_name: str) -> x509.Name:
    return x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])


def certificate(
    subject: str,
    key,
    issuer: x509.Certificate | None,
    issuer_key,
    *,
    ca: bool,
    marker: x509.ObjectIdentifier | None = None,
    not_before: datetime | None = None,
    not_after: datetime | None = None,
) -> x509.Certificate:
    now = datetime.now(timezone.utc)
    builder = (
        x509.CertificateBuilder()
        .subject_name(name(subject))
        .issuer_name(issuer.subject if issuer else name(subject))
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(not_before or now - timedelta(days=365))
        .not_valid_after(not_after or now + timedelta(days=365))
        .add_extension(x509.BasicConstraints(ca=ca, path_length=None), critical=True)
    )
    if marker is not None:
        builder = builder.add_extension(x509.UnrecognizedExtension(marker, b"\x05\x00"), False)
    return builder.sign(issuer_key, hashes.SHA384() if ca else hashes.SHA256())


def der(cert: x509.Certificate) -> str:
    return base64.b64encode(cert.public_bytes(serialization.Encoding.DER)).decode()


class FakeAppStore:
    def __init__(self, *, leaf_marker=appstore.LEAF_MARKER, leaf_curve=None, **leaf_dates):
        self.root_key = ec.generate_private_key(ec.SECP384R1())
        self.root = certificate("Test Root", self.root_key, None, self.root_key, ca=True)
        self.intermediate_key = ec.generate_private_key(ec.SECP384R1())
        self.intermediate = certificate(
            "Test WWDR",
            self.intermediate_key,
            self.root,
            self.root_key,
            ca=True,
            marker=appstore.INTERMEDIATE_MARKER,
        )
        self.leaf_key = ec.generate_private_key(leaf_curve or ec.SECP256R1())
        self.leaf = certificate(
            "Test App Store",
            self.leaf_key,
            self.intermediate,
            self.intermediate_key,
            ca=False,
            marker=leaf_marker,
            **leaf_dates,
        )

    @property
    def chain(self) -> list[str]:
        return [der(self.leaf), der(self.intermediate), der(self.root)]

    def sign(self, payload: dict, *, chain: list[str] | None = None, key=None) -> str:
        header = {"alg": "ES256", "x5c": self.chain if chain is None else chain}
        encoded = (b64url(json.dumps(part).encode()) for part in (header, payload))
        signing_input = ".".join(encoded)
        signature = (key or self.leaf_key).sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
        r, s = decode_dss_signature(signature)
        size = 32 if (key or self.leaf_key).curve.key_size == 256 else 48
        raw = r.to_bytes(size, "big") + s.to_bytes(size, "big")
        return f"{signing_input}.{b64url(raw)}"

    def transaction_payload(self, **overrides) -> dict:
        purchased = now_ms() - DAY_MS
        payload = {
            "transactionId": str(uuid.uuid4().int)[:16],
            "originalTransactionId": "2000000000000001",
            "bundleId": appstore.BUNDLE_ID,
            "productId": MONTHLY,
            "type": "Auto-Renewable Subscription",
            "purchaseDate": purchased,
            "originalPurchaseDate": purchased,
            # In the 7-day free trial.
            "expiresDate": purchased + 7 * DAY_MS,
            "offerType": 1,
            "environment": "Sandbox",
            "signedDate": now_ms(),
        }
        payload.update(overrides)
        return {key: value for key, value in payload.items() if value is not None}

    def transaction(self, **overrides) -> str:
        return self.sign(self.transaction_payload(**overrides))

    def notification(
        self,
        notification_type: str,
        subtype: str | None = None,
        *,
        transaction: str | None = None,
        renewal: dict | None = None,
        bundle_id: str = appstore.BUNDLE_ID,
        container: str = "data",
    ) -> str:
        data = {"bundleId": bundle_id, "environment": "Sandbox"}
        if transaction is not None:
            data["signedTransactionInfo"] = transaction
        if renewal is not None:
            data["signedRenewalInfo"] = self.sign({"signedDate": now_ms(), **renewal})
        payload = {
            "notificationType": notification_type,
            "notificationUUID": str(uuid.uuid4()),
            "version": "2.0",
            "signedDate": now_ms(),
            container: data,
        }
        if subtype:
            payload["subtype"] = subtype
        return self.sign(payload)
