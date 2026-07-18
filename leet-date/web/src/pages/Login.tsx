import { FormEvent, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Flame } from "lucide-react";
import { api, ApiError } from "../api";
import { useAuth } from "../main";

export default function Login() {
  const [handle, setHandle] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const navigate = useNavigate();
  const { refresh } = useAuth();

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      await api.login(handle, password);
      await refresh();
      navigate("/");
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "login failed");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="mx-auto max-w-sm">
      <div className="rounded-3xl border border-ink-200 bg-white p-8 shadow-sm dark:border-ink-800 dark:bg-ink-800">
        <div className="mb-6 flex flex-col items-center text-center">
          <span className="grid h-12 w-12 place-items-center rounded-2xl brand-gradient text-white shadow-md">
            <Flame size={22} strokeWidth={2.4} />
          </span>
          <h1 className="mt-4 text-2xl font-extrabold tracking-tight text-ink-900 dark:text-ink-50">
            Welcome back
          </h1>
          <p className="mt-1 text-sm text-ink-500 dark:text-ink-300">
            Log in to keep the spark going.
          </p>
        </div>

        <form onSubmit={onSubmit} className="flex flex-col gap-4">
          <label className="flex flex-col gap-1.5">
            <span className="text-xs font-medium uppercase tracking-wide text-ink-500 dark:text-ink-300">
              Handle
            </span>
            <input
              value={handle}
              onChange={(e) => setHandle(e.target.value)}
              required
              autoComplete="username"
              className="w-full rounded-xl border border-ink-200 bg-white px-4 py-2.5 text-base text-ink-900 outline-none transition-colors focus:border-brand-500 focus:ring-2 focus:ring-brand-200 dark:border-ink-700 dark:bg-ink-900 dark:text-ink-50 dark:focus:ring-brand-900"
            />
          </label>
          <label className="flex flex-col gap-1.5">
            <span className="text-xs font-medium uppercase tracking-wide text-ink-500 dark:text-ink-300">
              Password
            </span>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              autoComplete="current-password"
              className="w-full rounded-xl border border-ink-200 bg-white px-4 py-2.5 text-base text-ink-900 outline-none transition-colors focus:border-brand-500 focus:ring-2 focus:ring-brand-200 dark:border-ink-700 dark:bg-ink-900 dark:text-ink-50 dark:focus:ring-brand-900"
            />
          </label>
          <button
            disabled={submitting}
            className="mt-2 rounded-xl brand-gradient py-2.5 text-sm font-semibold text-white shadow-sm transition-all hover:brightness-105 disabled:opacity-60"
          >
            {submitting ? "Signing in..." : "Sign in"}
          </button>
          {error && (
            <p className="rounded-lg bg-rose-50 px-3 py-2 text-sm text-rose-700 dark:bg-rose-950/40 dark:text-rose-300">
              {error}
            </p>
          )}
        </form>

        <p className="mt-6 text-center text-sm text-ink-500 dark:text-ink-300">
          New here?{" "}
          <Link to="/register" className="font-semibold text-brand-600 hover:text-brand-700">
            Create an account
          </Link>
        </p>
      </div>
    </div>
  );
}
