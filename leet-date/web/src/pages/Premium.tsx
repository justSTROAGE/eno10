import { FormEvent, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Crown, Search, Sparkles } from "lucide-react";
import { api, ApiError, Me, Perk } from "../api";
import { useAuth } from "../main";

type PayMessage = { type: "leetdate-pay"; token: string; handle: string };

export default function Premium() {
  const navigate = useNavigate();
  const { refresh } = useAuth();
  const [me, setMe] = useState<Me | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  const [perkText, setPerkText] = useState("");
  const [myPerk, setMyPerk] = useState<Perk | null>(null);
  const [savingPerk, setSavingPerk] = useState(false);

  const [lookupHandle, setLookupHandle] = useState("");
  const [lookupResult, setLookupResult] = useState<Perk | null>(null);
  const [lookupError, setLookupError] = useState<string | null>(null);

  useEffect(() => {
    api
      .me()
      .then((m) => {
        setMe(m);
        if (m.is_premium) loadMyPerk();
      })
      .catch((err) => {
        if (err instanceof ApiError && err.status === 401) navigate("/login");
        else setError("could not load profile");
      })
      .finally(() => setLoading(false));
  }, [navigate]);

  async function loadMyPerk() {
    try {
      const p = await api.getUserPerk((await api.me()).handle);
      setMyPerk(p);
      setPerkText(p.perk_text);
    } catch (err) {
      if (!(err instanceof ApiError && err.status === 404)) {
        console.error(err);
      }
    }
  }

  useEffect(() => {
    function onMessage(ev: MessageEvent) {
      if (ev.origin !== window.location.origin) return;
      const data = ev.data as PayMessage | undefined;
      if (!data || data.type !== "leetdate-pay" || !data.token) return;
      redeem(data.token);
    }
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, []);

  async function startUpgrade() {
    setError(null);
    setStatus(null);
    if (!me) return;
    const url = `/pay/checkout?handle=${encodeURIComponent(me.handle)}&amount=500`;
    const w = window.open(url, "nextgenpay", "popup,width=460,height=620");
    if (!w) setError("popup blocked — allow popups for this site");
  }

  async function redeem(token: string) {
    setStatus("Verifying receipt…");
    setError(null);
    try {
      const res = await api.redeemPremium(token);
      if (res.ok && res.is_premium) {
        setStatus("Premium activated 👑");
        await refresh();
        const m = await api.me();
        setMe(m);
        if (m.is_premium) loadMyPerk();
      } else {
        setError("redeem failed");
      }
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "redeem failed");
      setStatus(null);
    }
  }

  async function savePerk(e: FormEvent) {
    e.preventDefault();
    setSavingPerk(true);
    setError(null);
    try {
      const p = await api.setMyPerk(perkText);
      setMyPerk(p);
      setStatus("Perk saved");
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "save failed");
    } finally {
      setSavingPerk(false);
    }
  }

  async function lookupPerk(e: FormEvent) {
    e.preventDefault();
    setLookupResult(null);
    setLookupError(null);
    try {
      const p = await api.getUserPerk(lookupHandle.trim().toLowerCase());
      setLookupResult(p);
    } catch (err) {
      setLookupError(
        err instanceof ApiError
          ? err.status === 404
            ? "no perk visible (target may not be premium, or you aren't)"
            : err.message
          : "lookup failed",
      );
    }
  }

  if (loading) return <p className="text-ink-500">Loading…</p>;
  if (!me) return null;

  return (
    <div className="space-y-8">
      <header className="flex items-center gap-3">
        <span className="grid h-12 w-12 place-items-center rounded-full brand-gradient text-white shadow-sm">
          <Crown size={22} />
        </span>
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight">LeetDate Premium</h1>
          <p className="text-sm text-ink-500">
            {me.is_premium
              ? "You're a premium member."
              : "Upgrade to view other premium members' perks."}
          </p>
        </div>
      </header>

      {error && (
        <div className="rounded-lg border border-red-300 bg-red-50 px-4 py-2 text-sm text-red-700 dark:border-red-700 dark:bg-red-950/40 dark:text-red-300">
          {error}
        </div>
      )}
      {status && (
        <div className="rounded-lg border border-emerald-300 bg-emerald-50 px-4 py-2 text-sm text-emerald-700 dark:border-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300">
          {status}
        </div>
      )}

      {!me.is_premium ? (
        <section className="rounded-2xl border border-ink-200 bg-white p-6 shadow-sm dark:border-ink-800 dark:bg-ink-900">
          <h2 className="text-lg font-semibold">Upgrade to Premium · $5.00</h2>
          <ul className="mt-3 list-inside list-disc space-y-1 text-sm text-ink-600 dark:text-ink-300">
            <li>See premium members' exclusive perks</li>
            <li>Get a premium badge on your profile</li>
            <li>Publish your own perk for other premium members</li>
          </ul>
          <button
            type="button"
            onClick={startUpgrade}
            className="mt-5 inline-flex items-center gap-2 rounded-full brand-gradient px-5 py-2 text-sm font-semibold text-white shadow-sm hover:brightness-105"
          >
            <Sparkles size={16} /> Pay with NextGenPay
          </button>
          <p className="mt-3 text-xs text-ink-500">
            Opens a secure NextGenPay window. You can create a free NextGenPay wallet during checkout.
          </p>
        </section>
      ) : (
        <>
          <section className="rounded-2xl border border-ink-200 bg-white p-6 shadow-sm dark:border-ink-800 dark:bg-ink-900">
            <h2 className="text-lg font-semibold">Your premium perk</h2>
            <p className="mt-1 text-sm text-ink-500">
              Visible to other premium members on your profile.
            </p>
            <form onSubmit={savePerk} className="mt-4 space-y-3">
              <textarea
                value={perkText}
                onChange={(e) => setPerkText(e.target.value)}
                maxLength={500}
                rows={3}
                placeholder="e.g. concierge code, secret invite link, VIP message…"
                className="w-full rounded-lg border border-ink-300 bg-white px-3 py-2 text-sm dark:border-ink-700 dark:bg-ink-950"
              />
              <button
                type="submit"
                disabled={savingPerk || perkText.trim() === ""}
                className="rounded-full brand-gradient px-4 py-1.5 text-sm font-semibold text-white shadow-sm disabled:opacity-60"
              >
                {savingPerk ? "Saving…" : myPerk ? "Update perk" : "Publish perk"}
              </button>
            </form>
          </section>

          <section className="rounded-2xl border border-ink-200 bg-white p-6 shadow-sm dark:border-ink-800 dark:bg-ink-900">
            <h2 className="text-lg font-semibold">View a member's perk</h2>
            <form onSubmit={lookupPerk} className="mt-3 flex gap-2">
              <input
                value={lookupHandle}
                onChange={(e) => setLookupHandle(e.target.value)}
                placeholder="handle"
                className="flex-1 rounded-lg border border-ink-300 bg-white px-3 py-2 text-sm dark:border-ink-700 dark:bg-ink-950"
              />
              <button
                type="submit"
                className="inline-flex items-center gap-1.5 rounded-full bg-ink-900 px-4 py-1.5 text-sm font-semibold text-white dark:bg-ink-100 dark:text-ink-900"
              >
                <Search size={14} /> View
              </button>
            </form>
            {lookupResult && (
              <div className="mt-4 rounded-lg border border-ink-200 bg-ink-50 p-3 text-sm dark:border-ink-800 dark:bg-ink-950">
                <div className="font-semibold">@{lookupResult.handle}</div>
                <div className="mt-1 whitespace-pre-wrap text-ink-700 dark:text-ink-200">
                  {lookupResult.perk_text}
                </div>
              </div>
            )}
            {lookupError && (
              <p className="mt-3 text-sm text-ink-500">{lookupError}</p>
            )}
          </section>
        </>
      )}
    </div>
  );
}
