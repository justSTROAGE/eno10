import base64
import json
import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

import jwt as pyjwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

_key: Optional[rsa.RSAPrivateKey] = None
_kid: Optional[str] = None
_jwk_path = os.environ.get("PAY_JWK_PATH", "./payments-jwk.json")


def _b64u_uint(n: int) -> str:
    raw = n.to_bytes((n.bit_length() + 7) // 8, "big")
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def load() -> None:
    global _key, _kid
    if os.path.exists(_jwk_path):
        with open(_jwk_path, "r") as f:
            data = json.load(f)
        _kid = data["kid"]
        _key = serialization.load_pem_private_key(data["pem"].encode(), password=None)
        return

    _key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    _kid = "leetdate-pay-" + secrets.token_hex(4)
    pem = _key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode()
    parent = os.path.dirname(_jwk_path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(_jwk_path, "w") as f:
        json.dump({"kid": _kid, "pem": pem}, f)


def public_jwks_json() -> str:
    assert _key is not None and _kid is not None
    nums = _key.public_key().public_numbers()
    return json.dumps({
        "keys": [{
            "kty": "RSA",
            "kid": _kid,
            "use": "sig",
            "alg": "RS256",
            "n": _b64u_uint(nums.n),
            "e": _b64u_uint(nums.e),
        }]
    })


_admin_pubkey = None


def _admin_pubkey_pem() -> str:
    raw = os.environ.get("PAY_ADMIN_PUBKEY", "").strip()
    if "\\n" in raw:
        raw = raw.replace("\\n", "\n")
    return raw


def admin_enabled() -> bool:
    return bool(_admin_pubkey_pem())


def verify_admin_token(token: str, handle: str, amount_cents: int) -> None:
    global _admin_pubkey
    if _admin_pubkey is None:
        pem = _admin_pubkey_pem()
        if not pem:
            raise ValueError("admin pubkey not configured")
        _admin_pubkey = serialization.load_pem_public_key(pem.encode())
    claims = pyjwt.decode(
        token,
        _admin_pubkey,
        algorithms=["RS256"],
        audience="leetdate-payments",
        options={"require": ["exp", "iat", "aud", "iss"]},
    )
    if claims.get("iss") != "leetdate-checker":
        raise ValueError("bad issuer")
    if (claims.get("handle") or "").strip().lower() != handle:
        raise ValueError("handle mismatch")
    if int(claims.get("amount_cents", -1)) != amount_cents:
        raise ValueError("amount mismatch")


def mint_receipt(ld_handle: str, amount_cents: int) -> str:
    assert _key is not None and _kid is not None
    now = datetime.now(timezone.utc)
    claims = {
        "iss": "leetdate-payments",
        "aud": "leetdate",
        "sub": ld_handle,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=30)).timestamp()),
        "jti": secrets.token_hex(16),
        "amount_cents": amount_cents,
    }
    return pyjwt.encode(
        claims,
        _key,
        algorithm="RS256",
        headers={"kid": _kid, "typ": "JWT"},
    )
