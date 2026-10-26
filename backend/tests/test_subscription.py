import base64
import json
from datetime import datetime, timedelta, timezone

import pytest
from conftest import TestingSessionLocal, auth_headers
from cryptography.hazmat.primitives.asymmetric import ec
from fake_app_store import DAY_MS, YEARLY, FakeAppStore, der, now_ms
from helpers import new_id
from sqlalchemy import select
from test_coach_api import BODY

import appstore
from models import Subscription, User

EMAIL = "subscriber@example.com"


@pytest.fixture
def store(monkeypatch):
    fake = FakeAppStore()
    monkeypatch.setattr(appstore, "trusted_roots", lambda: (fake.root,))
    monkeypatch.delenv("APP_STORE_ACCEPT_XCODE", raising=False)
    return fake


def put(client, signed, email=EMAIL):
    return client.put(
        "/v1/subscription", json={"signed_transaction": signed}, headers=auth_headers(email)
    )


def get(client, email=EMAIL):
    return client.get("/v1/subscription", headers=auth_headers(email)).json()


def notify(client, signed_payload):
    return client.post("/v1/app-store/notifications", json={"signedPayload": signed_payload})


def ask_coach(client, email=EMAIL):
    return client.put(f"/v1/recommendations/{new_id()}", json=BODY, headers=auth_headers(email))


def stored(email=EMAIL) -> Subscription | None:
    with TestingSessionLocal() as db:
        user = db.scalar(select(User).where(User.email == email))
        return user and db.get(Subscription, user.id)


# Apple's root


def test_apples_root_certificate_ships_with_the_code():
    (root,) = appstore.trusted_roots()
    assert root.subject.rfc4514_string() == (
        "C=US,O=Apple Inc.,OU=Apple Certification Authority,CN=Apple Root CA - G3"
    )
    assert root.fingerprint(appstore.hashes.SHA256()).hex().upper().startswith("63343ABF")


def test_a_transaction_signed_by_a_test_chain_fails_against_apples_root():
    signed = FakeAppStore().transaction()
    with pytest.raises(appstore.VerificationError, match="Not signed by Apple"):
        appstore.verify_transaction(signed)


# PUT /v1/subscription


def test_a_trial_purchase_gives_access_to_the_coach(client, store, started):
    assert ask_coach(client).status_code == 402

    response = put(client, store.transaction())

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "active"
    assert body["product_id"] == "app.ironsage.coach.monthly"
    assert body["environment"] == "Sandbox"
    assert body["coach_access"] is True
    assert get(client) == body
    assert ask_coach(client).status_code == 200


def test_no_subscription(client, store):
    assert get(client) == {
        "status": "none",
        "product_id": None,
        "expires_at": None,
        "environment": None,
        "coach_access": False,
    }


def test_the_manual_override_still_gives_access(client, store, started):
    client.get("/v1/me", headers=auth_headers(EMAIL))
    with TestingSessionLocal() as db:
        db.scalar(select(User).where(User.email == EMAIL)).coach_enabled = True
        db.commit()
    assert get(client)["coach_access"] is True
    assert get(client)["status"] == "none"
    assert ask_coach(client).status_code == 200


def test_an_expired_transaction_is_stored_but_gives_no_access(client, store, started):
    response = put(client, store.transaction(expiresDate=now_ms() - DAY_MS))

    assert response.status_code == 200
    assert response.json()["status"] == "expired"
    assert response.json()["coach_access"] is False
    assert ask_coach(client).status_code == 402


def test_access_ends_when_the_period_runs_out(client, store, started):
    put(client, store.transaction())
    with TestingSessionLocal() as db:
        subscription = db.scalar(select(Subscription))
        subscription.expires_at = subscription.expires_at.replace(year=2020)
        db.commit()
    assert get(client)["status"] == "expired"
    assert ask_coach(client).status_code == 402


def test_a_forged_transaction_is_refused(client, store):
    forger = FakeAppStore()

    response = put(client, forger.transaction())

    assert response.status_code == 400
    assert "Not signed by Apple" in response.json()["detail"]
    assert stored() is None


def test_an_altered_transaction_is_refused(client, store):
    header, _, signature = store.transaction().split(".")
    payload = store.transaction_payload(expiresDate=now_ms() + 3650 * DAY_MS)
    altered = f"{header}.{base64.urlsafe_b64encode(json.dumps(payload).encode()).decode()}"

    response = put(client, f"{altered}.{signature}")

    assert response.status_code == 400
    assert "Bad signature" in response.json()["detail"]


def test_a_transaction_for_another_app_is_refused(client, store):
    response = put(client, store.transaction(bundleId="com.example.other"))
    assert response.status_code == 400
    assert "another app" in response.json()["detail"]


@pytest.mark.parametrize(
    ("overrides", "message"),
    [
        ({"productId": "app.ironsage.something.else"}, "Not a coach subscription"),
        ({"type": "Non-Consumable"}, "Not an auto-renewable"),
        ({"expiresDate": None}, "without expiresDate"),
        ({"expiresDate": "soon"}, "Malformed date"),
    ],
)
def test_other_products_and_incomplete_transactions_are_refused(client, store, overrides, message):
    response = put(client, store.transaction(**overrides))
    assert response.status_code == 400
    assert message in response.json()["detail"]


def test_a_subscription_belongs_to_one_account(client, store):
    assert put(client, store.transaction()).status_code == 200

    response = put(client, store.transaction(), email="someone.else@example.com")

    assert response.status_code == 409
    assert stored("someone.else@example.com") is None


def test_an_older_transaction_does_not_shorten_the_subscription(client, store):
    renewal = store.transaction(expiresDate=now_ms() + 30 * DAY_MS)
    put(client, renewal)

    response = put(client, store.transaction())

    assert response.json()["expires_at"] == get(client)["expires_at"]
    assert stored().transaction_id == json.loads(
        base64.urlsafe_b64decode(renewal.split(".")[1] + "==")
    )["transactionId"]


def test_a_renewal_to_yearly_updates_the_product(client, store):
    put(client, store.transaction())
    response = put(client, store.transaction(productId=YEARLY, expiresDate=now_ms() + 365 * DAY_MS))
    assert response.json()["product_id"] == YEARLY


def test_another_apple_ids_subscription_replaces_an_expired_one(client, store):
    put(client, store.transaction(expiresDate=now_ms() - DAY_MS))

    response = put(client, store.transaction(originalTransactionId="2000000000000999"))

    assert response.json()["status"] == "active"
    assert stored().original_transaction_id == "2000000000000999"


def test_an_expired_one_from_another_apple_id_keeps_the_active_one(client, store):
    put(client, store.transaction())

    response = put(
        client,
        store.transaction(originalTransactionId="2000000000000999", expiresDate=now_ms() - 1),
    )

    assert response.json()["status"] == "active"
    assert stored().original_transaction_id == "2000000000000001"


def test_a_refunded_transaction_revokes_access(client, store, started):
    response = put(client, store.transaction(revocationDate=now_ms()))
    assert response.json()["status"] == "revoked"
    assert ask_coach(client).status_code == 402


def test_deleting_the_account_removes_the_subscription(client, store):
    put(client, store.transaction())
    assert client.delete("/v1/me", headers=auth_headers(EMAIL)).status_code == 204
    with TestingSessionLocal() as db:
        assert db.scalar(select(Subscription)) is None


# Xcode's StoreKit testing


def xcode_transaction() -> str:
    xcode = FakeAppStore()
    return xcode.sign(xcode.transaction_payload(environment="Xcode"), chain=[der(xcode.leaf)])


def test_xcode_transactions_are_refused_by_default(client, store):
    response = put(client, xcode_transaction())
    assert response.status_code == 400
    assert "only accepted locally" in response.json()["detail"]


def test_xcode_transactions_are_accepted_locally_when_enabled(client, store, monkeypatch):
    monkeypatch.setenv("APP_STORE_ACCEPT_XCODE", "1")
    response = put(client, xcode_transaction())
    assert response.json()["environment"] == "Xcode"
    assert response.json()["status"] == "active"


def test_xcode_transactions_are_never_accepted_on_lambda(client, store, monkeypatch):
    monkeypatch.setenv("APP_STORE_ACCEPT_XCODE", "1")
    monkeypatch.setenv("AWS_LAMBDA_FUNCTION_NAME", "trainwise-api-prod")
    assert put(client, xcode_transaction()).status_code == 400


# Malformed or untrustworthy JWS


def test_malformed_jws_is_refused(store):
    good = store.transaction()
    header, payload, signature = good.split(".")
    other_curve = FakeAppStore(leaf_curve=ec.SECP384R1())

    def signed(chain):
        return store.sign(store.transaction_payload(), chain=chain)

    cases = {
        "not.a.jws.at.all": "Malformed JWS",
        f"{header}.{payload}": "Malformed JWS",
        "!!!.???.***": "Malformed JWS",
        f"{base64.urlsafe_b64encode(b'[1]').decode()}.{payload}.{signature}": "Malformed JWS",
        f"{header}.{payload}.{signature[:-8]}": None,
        signed(chain=[]): "Missing certificate chain",
        signed(chain=store.chain[:2]): "Unexpected certificate chain",
        signed(chain=["%%%", *store.chain[1:]]): "Malformed certificate",
        signed(chain=[42, *store.chain[1:]]): "Malformed certificate",
        signed(chain=[store.chain[1], *store.chain[1:]]): "Broken certificate chain",
        signed(chain=[der(other_curve.leaf), *store.chain[1:]]): "Broken certificate chain",
        other_curve.sign(other_curve.transaction_payload()): "Not signed by Apple",
    }
    for jws, message in cases.items():
        with pytest.raises(appstore.VerificationError, match=message):
            appstore.decode(jws)


def test_only_es256_is_accepted(store):
    header = base64.urlsafe_b64encode(
        json.dumps({"alg": "HS256", "x5c": store.chain}).encode()
    ).decode().rstrip("=")
    _, payload, signature = store.transaction().split(".")
    with pytest.raises(appstore.VerificationError, match="Unexpected algorithm"):
        appstore.decode(f"{header}.{payload}.{signature}")


def test_the_leaf_must_be_an_app_store_certificate(monkeypatch):
    unmarked = FakeAppStore(leaf_marker=None)
    monkeypatch.setattr(appstore, "trusted_roots", lambda: (unmarked.root,))
    with pytest.raises(appstore.VerificationError, match="Not an App Store certificate"):
        appstore.decode(unmarked.transaction())


def test_the_leaf_must_be_valid_when_the_data_was_signed(monkeypatch):
    month_ago = datetime.now(timezone.utc) - timedelta(days=30)
    lapsed = FakeAppStore(not_before=month_ago, not_after=month_ago + timedelta(days=7))
    monkeypatch.setattr(appstore, "trusted_roots", lambda: (lapsed.root,))
    with pytest.raises(appstore.VerificationError, match="not valid when signed"):
        appstore.decode(lapsed.transaction())
    # Signed while it was valid: still good after it lapsed.
    signed_then = (month_ago + timedelta(days=1)).timestamp() * 1000
    assert appstore.decode(lapsed.transaction(signedDate=int(signed_then)))


def test_a_signature_of_the_wrong_length_is_refused(store):
    header, payload, _ = store.transaction().split(".")
    short = base64.urlsafe_b64encode(b"\x01" * 63).decode().rstrip("=")
    with pytest.raises(appstore.VerificationError, match="Malformed signature"):
        appstore.decode(f"{header}.{payload}.{short}")


# App Store Server Notifications


def test_a_renewal_extends_the_subscription(client, store, started):
    put(client, store.transaction())
    renewed = now_ms() + 30 * DAY_MS

    response = notify(client, store.notification("DID_RENEW", transaction=store.transaction(
        expiresDate=renewed, offerType=None
    )))

    assert response.status_code == 200
    assert stored().expires_at.timestamp() == pytest.approx(renewed / 1000)
    assert ask_coach(client).status_code == 200


def test_an_expiry_ends_access(client, store, started):
    put(client, store.transaction())
    lapsed = store.transaction(expiresDate=now_ms() - 1, transactionId=stored().transaction_id)

    response = notify(client, store.notification("EXPIRED", "VOLUNTARY", transaction=lapsed))

    assert response.status_code == 200
    assert get(client)["status"] == "expired"
    assert ask_coach(client).status_code == 402


def test_a_refund_revokes_access(client, store, started):
    put(client, store.transaction())
    refunded = store.transaction(revocationDate=now_ms(), transactionId=stored().transaction_id)

    assert notify(client, store.notification("REFUND", transaction=refunded)).status_code == 200

    assert get(client)["status"] == "revoked"
    assert ask_coach(client).status_code == 402


def test_the_billing_grace_period_keeps_access(client, store, started):
    put(client, store.transaction())
    failed = store.transaction(expiresDate=now_ms() - 1, transactionId=stored().transaction_id)
    grace = now_ms() + 6 * DAY_MS

    notify(client, store.notification(
        "DID_FAIL_TO_RENEW",
        "GRACE_PERIOD",
        transaction=failed,
        renewal={"gracePeriodExpiresDate": grace, "originalTransactionId": "2000000000000001"},
    ))

    assert get(client)["status"] == "active"
    assert stored().expires_at.timestamp() == pytest.approx(grace / 1000)


def test_a_notification_for_an_unclaimed_subscription_is_accepted_and_ignored(client, store):
    response = notify(client, store.notification("SUBSCRIBED", transaction=store.transaction()))
    assert response.status_code == 200
    with TestingSessionLocal() as db:
        assert db.scalar(select(Subscription)) is None


def test_a_test_notification_is_accepted(client, store):
    assert notify(client, store.notification("TEST")).status_code == 200
    summary = store.notification("RENEWAL_EXTENDED", container="summary")
    assert notify(client, summary).status_code == 200


def test_a_forged_notification_is_refused(client, store):
    put(client, store.transaction())
    forger = FakeAppStore()
    forged = forger.notification("REFUND", transaction=store.transaction(revocationDate=now_ms()))

    assert notify(client, forged).status_code == 400
    assert get(client)["status"] == "active"


def test_a_notification_for_another_app_is_refused(client, store):
    response = notify(client, store.notification("TEST", bundle_id="com.example.other"))
    assert response.status_code == 400
