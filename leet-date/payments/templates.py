import html
import json
import os
from urllib.parse import quote

BASE_PATH = os.environ.get("PAY_BASE_PATH", "/pay")


def _esc(s: str) -> str:
    return html.escape(s, quote=True)


def _format_cents(c: int) -> str:
    sign = "-" if c < 0 else ""
    a = abs(c)
    return f"{sign}${a // 100}.{a % 100:02d}"


CSS = r"""
* { box-sizing: border-box; }
body {
    margin: 0;
    font: 12px Verdana, Geneva, Tahoma, sans-serif;
    color: #333;
    background: #d6dde6;
    background-image:
        linear-gradient(to bottom, #e8edf2 0%, #c2cbd6 100%);
    background-attachment: fixed;
    min-height: 100vh;
    padding: 30px 16px;
}
.container {
    width: 100%;
    max-width: 460px;
    margin: 0 auto;
    background: #ffffff;
    border: 1px solid #8c98a8;
    border-radius: 6px;
    box-shadow: 0 4px 14px rgba(0,0,0,0.25), 0 1px 0 #fff inset;
    overflow: hidden;
}
.header {
    background: #2b5599;
    background-image: linear-gradient(to bottom, #5a85c2 0%, #2b5599 50%, #1f4380 100%);
    border-bottom: 1px solid #15315f;
    padding: 12px 18px;
    color: #fff;
    text-shadow: 0 -1px 0 rgba(0,0,0,0.35);
    position: relative;
}
.header h1 {
    font: bold 22px Helvetica, Arial, sans-serif;
    margin: 0;
    letter-spacing: -0.5px;
}
.header h1 .pay { color: #ffd700; }
.header h1 .tm { font-size: 10px; vertical-align: super; font-weight: normal; opacity: 0.85; }
.header .tag {
    position: absolute;
    top: 14px; right: 18px;
    font: bold 10px Verdana, sans-serif;
    color: #fff;
    background: #060;
    background-image: linear-gradient(to bottom, #4a9c4a 0%, #060 100%);
    padding: 3px 8px;
    border-radius: 10px;
    border: 1px solid #003300;
    text-shadow: 0 -1px 0 rgba(0,0,0,0.4);
    box-shadow: inset 0 1px 0 rgba(255,255,255,0.3);
}
.body { padding: 22px 20px 18px; }
h2 {
    font: bold 16px Verdana, sans-serif;
    color: #2b5599;
    margin: 0 0 10px 0;
}
p { line-height: 1.5; margin: 6px 0; }
label {
    display: block;
    margin: 12px 0 4px;
    font-weight: bold;
    color: #555;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}
input[type=text], input[type=password] {
    width: 100%;
    padding: 6px 8px;
    border: 1px solid #aaa;
    border-top-color: #999;
    border-radius: 3px;
    background: #fafafa;
    font: 13px Verdana, sans-serif;
    box-shadow: inset 0 1px 2px rgba(0,0,0,0.1);
}
input[type=text]:focus, input[type=password]:focus {
    outline: 0;
    border-color: #4a7fbf;
    background: #fff;
    box-shadow: inset 0 1px 2px rgba(0,0,0,0.05), 0 0 4px rgba(74,127,191,0.6);
}
.btn {
    display: inline-block;
    padding: 7px 18px;
    background: #ff7b00;
    background-image: linear-gradient(to bottom, #ffb84d 0%, #ff8c1a 50%, #ff7b00 100%);
    border: 1px solid #b85700;
    border-radius: 4px;
    color: #fff;
    text-shadow: 0 -1px 0 rgba(0,0,0,0.35);
    box-shadow: inset 0 1px 0 rgba(255,255,255,0.45), 0 1px 2px rgba(0,0,0,0.2);
    font: bold 13px Verdana, sans-serif;
    cursor: pointer;
    text-decoration: none;
}
.btn:hover { background-image: linear-gradient(to bottom, #ffc266 0%, #ff9933 50%, #ff8514 100%); }
.btn:disabled { opacity: 0.55; cursor: not-allowed; }
.btn-secondary {
    background: #ddd;
    background-image: linear-gradient(to bottom, #f8f8f8 0%, #ddd 100%);
    border-color: #888;
    color: #333;
    text-shadow: 0 1px 0 #fff;
}
.btn-secondary:hover { background-image: linear-gradient(to bottom, #fff 0%, #e4e4e4 100%); }
.btnrow { margin-top: 16px; display: flex; gap: 8px; }
.muted { color: #888; font-size: 11px; }
.notice {
    background: #fffbe5;
    border: 1px solid #e5dba0;
    color: #6a5a00;
    padding: 8px 10px;
    border-radius: 3px;
    margin: 12px 0;
    font-size: 11px;
}
.err, .success {
    padding: 7px 10px;
    border-radius: 3px;
    margin: 10px 0;
    font-size: 12px;
}
.err { background: #fee; border: 1px solid #fbb; color: #900; }
.success { background: #efe; border: 1px solid #cfc; color: #060; }
.amount {
    font: bold 30px Helvetica, Arial, sans-serif;
    color: #060;
    text-align: center;
    margin: 14px 0;
    text-shadow: 0 1px 0 #fff;
}
.receipt {
    background: #f6f6f6;
    border: 1px solid #ddd;
    border-radius: 3px;
    padding: 10px 12px;
    margin: 10px 0;
}
.receipt dl { margin: 0; }
.receipt dt { float: left; clear: left; width: 130px; color: #777; font-size: 11px; padding: 3px 0; }
.receipt dd { margin: 0 0 0 130px; padding: 3px 0; font-size: 12px; font-weight: bold; }
hr { border: 0; border-top: 1px solid #ddd; margin: 14px 0; }
.footer {
    background: #f3f5f8;
    border-top: 1px solid #ccd2db;
    padding: 10px 18px;
    font-size: 10px;
    color: #777;
    text-align: center;
}
.footer a { color: #2b5599; text-decoration: none; }
.footer a:hover { text-decoration: underline; }
.trustrow {
    display: flex;
    gap: 6px;
    justify-content: center;
    margin-top: 6px;
}
.trust {
    display: inline-block;
    font: bold 9px Verdana, sans-serif;
    color: #fff;
    padding: 2px 5px;
    border-radius: 2px;
    text-shadow: 0 -1px 0 rgba(0,0,0,0.3);
}
.trust.ssl    { background: linear-gradient(to bottom, #4a9c4a 0%, #060 100%); border: 1px solid #003300; }
.trust.verify { background: linear-gradient(to bottom, #6a90c0 0%, #2b5599 100%); border: 1px solid #15315f; }
.trust.pcidss { background: linear-gradient(to bottom, #b04040 0%, #800020 100%); border: 1px solid #500010; }
a { color: #2b5599; }
"""


def _header_block() -> str:
    return f"""
    <div class="header">
      <h1>NextGen<span class="pay">Pay</span> <span class="tm">TM</span></h1>
      <span class="tag">SECURE</span>
    </div>
"""


def _footer_block() -> str:
    return """
    <div class="footer">
      <div>&copy; 2010 NextGenPay Inc. &middot; <a href="#">Privacy Policy</a> &middot; <a href="#">User Agreement</a></div>
      <div class="trustrow">
        <span class="trust ssl">256-BIT SSL</span>
        <span class="trust verify">VERIFIED MERCHANT</span>
        <span class="trust pcidss">PCI-DSS</span>
      </div>
    </div>
"""


def _document(title: str, body_inner: str, scripts: str = "") -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{_esc(title)}</title>
<style>{CSS}</style>
</head>
<body>
<div class="container">
  {_header_block()}
  <div class="body">
{body_inner}
  </div>
  {_footer_block()}
</div>
<script>{scripts}</script>
</body>
</html>"""


def register_page(next_url: str | None) -> str:
    next_esc = quote(next_url) if next_url else ""
    next_field = f'<input type="hidden" name="next" value="{_esc(next_url)}">' if next_url else ""
    body = f"""
    <h2>Open a NextGenPay account</h2>
    <p class="muted">Sign up for a free NextGenPay wallet. Funds are loaded by your sponsoring merchant once your account is verified.</p>
    <form id="f">
      {next_field}
      <label for="handle">NextGenPay handle</label>
      <input type="text" id="handle" name="handle" autocomplete="username" required>
      <label for="password">Password</label>
      <input type="password" id="password" name="password" autocomplete="new-password" required minlength="8">
      <div class="btnrow">
        <button type="submit" class="btn">Create my wallet &raquo;</button>
        <a href="{BASE_PATH}/login?next={next_esc}" class="btn btn-secondary">Log in instead</a>
      </div>
      <div id="err" class="err" style="display:none"></div>
    </form>
"""
    script = r"""
document.getElementById('f').addEventListener('submit', async (e) => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const next = fd.get('next');
  const body = {handle: fd.get('handle'), password: fd.get('password')};
  const r = await fetch('""" + BASE_PATH + r"""/register', {method:'POST', headers:{'Content-Type':'application/json'}, credentials:'include', body: JSON.stringify(body)});
  if (r.ok) {
    if (next) location.assign(next); else location.assign('""" + BASE_PATH + r"""/me');
  } else {
    const j = await r.json().catch(() => ({error:'unknown'}));
    const err = document.getElementById('err');
    err.textContent = j.error || 'error';
    err.style.display = '';
  }
});
"""
    return _document("NextGenPay — Open an Account", body, script)


def login_page(next_url: str | None) -> str:
    next_esc = quote(next_url) if next_url else ""
    next_field = f'<input type="hidden" name="next" value="{_esc(next_url)}">' if next_url else ""
    body = f"""
    <h2>Log in to your wallet</h2>
    <form id="f">
      {next_field}
      <label for="handle">NextGenPay handle</label>
      <input type="text" id="handle" name="handle" autocomplete="username" required>
      <label for="password">Password</label>
      <input type="password" id="password" name="password" autocomplete="current-password" required>
      <div class="btnrow">
        <button type="submit" class="btn">Log in &raquo;</button>
        <a href="{BASE_PATH}/register?next={next_esc}" class="btn btn-secondary">Open an account</a>
      </div>
      <div id="err" class="err" style="display:none"></div>
    </form>
"""
    script = r"""
document.getElementById('f').addEventListener('submit', async (e) => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const next = fd.get('next');
  const body = {handle: fd.get('handle'), password: fd.get('password')};
  const r = await fetch('""" + BASE_PATH + r"""/login', {method:'POST', headers:{'Content-Type':'application/json'}, credentials:'include', body: JSON.stringify(body)});
  if (r.ok) {
    if (next) location.assign(next); else location.assign('""" + BASE_PATH + r"""/me');
  } else {
    const j = await r.json().catch(() => ({error:'unknown'}));
    const err = document.getElementById('err');
    err.textContent = j.error || 'error';
    err.style.display = '';
  }
});
"""
    return _document("NextGenPay — Log In", body, script)


def checkout_page(pay_handle: str, balance_cents: int, ld_handle: str, amount_cents: int) -> str:
    insufficient = balance_cents < amount_cents
    body = f"""
    <p class="muted">Signed in as <strong>{_esc(pay_handle)}</strong> &middot; Wallet balance <strong>{_format_cents(balance_cents)}</strong></p>
    <h2>Confirm your payment</h2>
    <p>You are about to send funds from your NextGenPay wallet to upgrade the following Leet Date account:</p>
    <div class="receipt">
      <dl>
        <dt>Merchant</dt><dd>Leet Date Premium</dd>
        <dt>Recipient handle</dt><dd>{_esc(ld_handle)}</dd>
        <dt>Description</dt><dd>Premium tier (30&nbsp;days)</dd>
      </dl>
    </div>
    <div class="amount">{_format_cents(amount_cents)}</div>
    {'<div class="err">Your wallet balance is insufficient. Please add funds to continue.</div>' if insufficient else ''}
    <div class="notice">By clicking <strong>Pay Now</strong>, you authorize NextGenPay&trade; to debit your wallet for the amount shown above. All transactions are final.</div>
    <div class="btnrow">
      <button id="confirm" class="btn"{'disabled' if insufficient else ''}>Pay Now &raquo;</button>
      <a href="{BASE_PATH}/topup?return=checkout&handle={_esc(ld_handle)}&amount={amount_cents}" class="btn btn-secondary">Add Funds</a>
      <button id="cancel" type="button" class="btn btn-secondary">Cancel</button>
    </div>
    <div id="status" class="success" style="display:none"></div>
    <div id="err" class="err" style="display:none"></div>
"""
    script = (
        "const handle = " + json.dumps(ld_handle) + ";\n"
        "const amount = " + str(amount_cents) + ";\n"
        "document.getElementById('cancel').addEventListener('click', () => window.close());\n"
        "document.getElementById('confirm').addEventListener('click', async () => {\n"
        "  const btn = document.getElementById('confirm');\n"
        "  btn.disabled = true;\n"
        "  const r = await fetch('" + BASE_PATH + "/charge', {method:'POST', headers:{'Content-Type':'application/json'}, credentials:'include', body: JSON.stringify({handle: handle, amount_cents: amount})});\n"
        "  const j = await r.json().catch(() => ({error:'unknown'}));\n"
        "  if (j.ok && j.token) {\n"
        "    if (window.opener) {\n"
        "      window.opener.postMessage({type:'leetdate-pay', token: j.token, handle: handle}, location.origin);\n"
        "    }\n"
        "    const s = document.getElementById('status');\n"
        "    s.textContent = 'Payment approved. Closing this window...';\n"
        "    s.style.display = '';\n"
        "    setTimeout(() => window.close(), 700);\n"
        "  } else {\n"
        "    const e = document.getElementById('err');\n"
        "    e.textContent = j.error || 'payment failed';\n"
        "    e.style.display = '';\n"
        "    btn.disabled = false;\n"
        "  }\n"
        "});\n"
    )
    return _document("NextGenPay — Confirm Payment", body, script)


def topup_page(pay_handle: str, balance_cents: int, return_to: str | None) -> str:
    return_link = ""
    if return_to:
        return_link = f'<a href="{_esc(return_to)}" style="text-decoration:none"><button type="button" class="btn btn-secondary">&laquo; Back</button></a>'
    body = f"""
    <p class="muted">Signed in as <strong>{_esc(pay_handle)}</strong> &middot; Wallet balance <strong>{_format_cents(balance_cents)}</strong></p>
    <h2>Add funds to your wallet</h2>
    <p class="muted">Top up using any major credit or debit card. Funds are usually available immediately.</p>
    <form id="f">
      <label for="amount">Amount</label>
      <select id="amount" name="amount" required style="width:100%; padding:6px 8px; border:1px solid #aaa; border-radius:3px; background:#fafafa; font:13px Verdana,sans-serif;">
        <option value="500">$5.00</option>
        <option value="1000" selected>$10.00</option>
        <option value="2500">$25.00</option>
        <option value="10000">$100.00</option>
      </select>
      <label for="card_number">Card number</label>
      <input type="text" id="card_number" name="card_number" autocomplete="cc-number" placeholder="4242 4242 4242 4242" required>
      <div style="display:flex; gap:8px;">
        <div style="flex:1">
          <label for="card_expiry">Expiration (MM/YY)</label>
          <input type="text" id="card_expiry" name="card_expiry" autocomplete="cc-exp" placeholder="12/26" required>
        </div>
        <div style="width: 110px">
          <label for="card_cvv">CVV</label>
          <input type="text" id="card_cvv" name="card_cvv" autocomplete="cc-csc" placeholder="123" required>
        </div>
      </div>
      <label for="card_name">Cardholder name</label>
      <input type="text" id="card_name" name="card_name" autocomplete="cc-name" placeholder="As shown on card" required>
      <div class="btnrow">
        <button type="submit" id="submit" class="btn">Charge my card &raquo;</button>
        {return_link}
      </div>
      <div id="status" class="notice" style="display:none"></div>
      <div id="err" class="err" style="display:none"></div>
    </form>
"""
    script = r"""
const messages = [
  'Contacting payment gateway...',
  'Verifying card details with your issuing bank...',
  'Performing 3-D Secure check...',
  'Awaiting authorization...',
  'This is taking longer than usual, please wait...',
];
let msgIdx = 0;
let msgTimer = null;

document.getElementById('f').addEventListener('submit', async (e) => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const body = {
    amount_cents: parseInt(fd.get('amount'), 10),
    card_number: fd.get('card_number'),
    card_expiry: fd.get('card_expiry'),
    card_cvv: fd.get('card_cvv'),
    card_name: fd.get('card_name'),
  };
  const submit = document.getElementById('submit');
  const status = document.getElementById('status');
  const err = document.getElementById('err');
  submit.disabled = true;
  err.style.display = 'none';
  status.style.display = '';
  status.textContent = messages[0];
  msgTimer = setInterval(() => {
    msgIdx = Math.min(msgIdx + 1, messages.length - 1);
    status.textContent = messages[msgIdx];
  }, 3500);
  let j;
  try {
    const r = await fetch('""" + BASE_PATH + r"""/topup', {method:'POST', headers:{'Content-Type':'application/json'}, credentials:'include', body: JSON.stringify(body)});
    j = await r.json().catch(() => ({error: 'gateway returned malformed response'}));
  } catch (e) {
    j = {error: 'network error: ' + e.message};
  }
  clearInterval(msgTimer);
  status.style.display = 'none';
  err.textContent = j.error || 'unknown error';
  err.style.display = '';
  submit.disabled = false;
});
"""
    return _document("NextGenPay — Add Funds", body, script)
