import os
import re
import secrets
import time
from datetime import datetime, timedelta, timezone
from urllib.parse import quote

import bcrypt
from bottle import Bottle, HTTPResponse, redirect, request, response
from waitress import serve

import db
import jwt_util
import templates

app = Bottle()

BASE_PATH = os.environ.get("PAY_BASE_PATH", "/pay")
COOKIE_NAME = "pay_session"
COOKIE_SECURE = os.environ.get("PAY_COOKIE_SECURE") == "1"

HANDLE_RE = re.compile(r"^[a-z0-9_]{3,32}$")
LD_HANDLE_RE = re.compile(r"^[a-z0-9_]{3,32}$")




def _json(body, status=200):
    response.status = status
    response.content_type = "application/json"
    return body


def _err(msg: str, status: int):
    return _json({"error": msg}, status)


def _set_session_cookie(token: str, max_age_days: int = 7) -> None:
    response.set_cookie(
        COOKIE_NAME,
        token,
        path=BASE_PATH,
        httponly=True,
        secure=COOKIE_SECURE,
        max_age=max_age_days * 86400,
        samesite="lax",
    )


def _clear_session_cookie() -> None:
    response.delete_cookie(COOKIE_NAME, path=BASE_PATH)


def _current_session():
    token = request.get_cookie(COOKIE_NAME)
    if not token:
        return None
    row = db.lookup_session(token)
    if not row:
        return None
    user_id, handle = row
    return {"user_id": user_id, "handle": handle, "token": token}


def _create_session(user_id: int) -> str:
    token = secrets.token_hex(32)
    now = datetime.now(timezone.utc)
    db.create_session(token, user_id, (now + timedelta(days=7)).isoformat(), now.isoformat())
    return token


@app.get("/healthz")
def healthz():
    return _json({"ok": True})


@app.get("/.well-known/jwks.json")
def jwks():
    response.content_type = "application/json"
    return jwt_util.public_jwks_json()




@app.get("/register")
def get_register():
    response.content_type = "text/html; charset=utf-8"
    return templates.register_page(request.query.get("next") or None)

#TODO maybe 2FA?
@app.post("/register")
def post_register():
    body = request.json or {}
    handle = (body.get("handle") or "").strip().lower()
    password = body.get("password") or ""
    if not HANDLE_RE.match(handle):
        return _err("handle must match ^[a-z0-9_]{3,32}$", 400)
    if not (8 <= len(password) <= 100):
        return _err("password must be 8..100 chars", 400)
    pw_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(4)).decode("ascii")
    try:
        user_id = db.create_user(handle, pw_hash)
    except Exception:
        return _err("handle taken", 409)
    _set_session_cookie(_create_session(user_id))
    return _json({"ok": True, "handle": handle})


@app.get("/login")
def get_login():
    response.content_type = "text/html; charset=utf-8"
    return templates.login_page(request.query.get("next") or None)


@app.post("/login")
def post_login():
    body = request.json or {}
    handle = (body.get("handle") or "").strip().lower()
    password = body.get("password") or ""
    row = db.find_user_by_handle(handle)
    if not row:
        return _err("invalid credentials", 401)
    user_id, db_handle, pw_hash, _balance = row
    if not bcrypt.checkpw(password.encode("utf-8"), pw_hash.encode("ascii")):
        return _err("invalid credentials", 401)
    _set_session_cookie(_create_session(user_id))
    return _json({"ok": True, "handle": db_handle})


@app.post("/logout")
def post_logout():
    sess = _current_session()
    if sess:
        db.delete_session(sess["token"])
    _clear_session_cookie()
    return _json({"ok": True})


@app.get("/me")
def get_me():
    sess = _current_session()
    if not sess:
        return _err("not logged in", 401)
    row = db.find_user_by_id(sess["user_id"])
    if not row:
        return _err("session invalid", 401)
    _id, handle, _ph, balance = row
    return _json({"handle": handle, "balance_cents": balance})




@app.get("/checkout")
def get_checkout():
    ld_handle = (request.query.get("handle") or "").strip().lower()
    amount_str = request.query.get("amount") or "500"
    try:
        amount = max(1, min(int(amount_str), 100_000))
    except ValueError:
        amount = 500
    if not LD_HANDLE_RE.match(ld_handle):
        return _err("bad handle", 400)

    sess = _current_session()
    if not sess:
        next_url = f"{BASE_PATH}/checkout?handle={ld_handle}&amount={amount}"
        return redirect(f"{BASE_PATH}/login?next={quote(next_url)}")

    row = db.find_user_by_id(sess["user_id"])
    if not row:
        return redirect(f"{BASE_PATH}/login")
    _id, handle, _ph, balance = row
    response.content_type = "text/html; charset=utf-8"
    return templates.checkout_page(handle, balance, ld_handle, amount)


@app.post("/charge")
def post_charge():
    sess = _current_session()
    if not sess:
        return _err("not logged in", 401)
    body = request.json or {}
    ld_handle = (body.get("handle") or "").strip().lower()
    try:
        amount = int(body.get("amount_cents") or 0)
    except (TypeError, ValueError):
        return _err("bad amount", 400)
    if not LD_HANDLE_RE.match(ld_handle):
        return _err("bad handle", 400)
    if not (1 <= amount <= 100_000):
        return _err("amount out of range", 400)
    new_balance = db.debit_balance(sess["user_id"], amount)
    if new_balance is None:
        return _err("insufficient balance", 402)
    token = jwt_util.mint_receipt(ld_handle, amount)
    return _json({"ok": True, "token": token, "balance_cents": new_balance})



TOPUP_DELAY_SECONDS = float(os.environ.get("PAY_TOPUP_DELAY", "10"))


#TODO: Fix this asap, users will start noticing
@app.get("/topup")
def get_topup():
    sess = _current_session()
    if not sess:
        next_url = f"{BASE_PATH}/topup"
        return redirect(f"{BASE_PATH}/login?next={quote(next_url)}")
    row = db.find_user_by_id(sess["user_id"])
    if not row:
        return redirect(f"{BASE_PATH}/login")
    _id, handle, _ph, balance = row

    return_to = None
    if request.query.get("return") == "checkout":
        h = (request.query.get("handle") or "").strip().lower()
        a = request.query.get("amount") or "500"
        if LD_HANDLE_RE.match(h) and a.isdigit():
            return_to = f"{BASE_PATH}/checkout?handle={h}&amount={a}"

    response.content_type = "text/html; charset=utf-8"
    return templates.topup_page(handle, balance, return_to)


@app.post("/topup")
def post_topup():
    sess = _current_session()
    if not sess:
        return _err("not logged in", 401)
    body = request.json or {}
    card = (body.get("card_number") or "").replace(" ", "").strip()
    if not re.match(r"^\d{12,19}$", card):
        return _err("Invalid card number format", 400)
    time.sleep(TOPUP_DELAY_SECONDS)
    return _err(
        "Transaction timed out at upstream gateway (error 504 from acquirer). "
        "Your card was still charged. You can try again. Please do not contact us.",
        504,
    )




@app.post("/admin/fund")
def post_admin_fund():
    if not jwt_util.admin_enabled():
        return _err("admin disabled", 503)
    body = request.json or {}
    handle = (body.get("handle") or "").strip().lower()
    try:
        amount = int(body.get("amount_cents") or 0)
    except (TypeError, ValueError):
        return _err("bad amount", 400)
    if not HANDLE_RE.match(handle):
        return _err("bad handle", 400)
    if not (1 <= amount <= 10_000_000):
        return _err("amount out of range", 400)
    try:
        jwt_util.verify_admin_token(request.headers.get("X-Pay-Admin", ""), handle, amount)
    except Exception:
        return _err("unauthorized", 401)
    new_balance = db.credit_balance(handle, amount)
    if new_balance is None:
        return _err("unknown handle", 404)
    return _json({"ok": True, "handle": handle, "balance_cents": new_balance})


def main() -> None:
    db.init()
    jwt_util.load()
    if not jwt_util.admin_enabled():
        print("warning: PAY_ADMIN_PUBKEY is unset; /admin/fund is disabled", flush=True)
    port = int(os.environ.get("PORT", "7000"))
    serve(
        app,
        host="0.0.0.0",
        port=port,
        threads=16,
        connection_limit=100,
        channel_timeout=20,
        ident="NextGenPay",
    )


if __name__ == "__main__":
    main()

