import { Link } from "react-router-dom";
import { Compass, Heart, MessageCircle, ShieldAlert, UserRound } from "lucide-react";
import { useAuth } from "../main";

export default function Landing() {
  const { me, loading } = useAuth();

  if (loading) {
    return <p className="text-ink-400 text-sm">Loading...</p>;
  }

  if (me) {
    return (
      <div className="mx-auto max-w-2xl">
        <div className="rounded-3xl border border-ink-200 bg-white p-8 shadow-sm dark:border-ink-800 dark:bg-ink-800">
          <p className="text-sm font-medium uppercase tracking-widest text-brand-400">Session restored</p>
          <h1 className="mt-1 text-3xl font-extrabold tracking-tight text-ink-50">
            Welcome back, {me.display_name}
          </h1>
          <p className="mt-1 text-ink-300">
            @{me.handle} · the channel is live. Pick a target.
          </p>

          <div className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-3">
            <Link
              to="/discover"
              className="group flex items-center gap-3 rounded-2xl border border-ink-200 p-4 transition-all hover:-translate-y-0.5 hover:border-brand-300 hover:shadow-md dark:border-ink-700 dark:hover:border-brand-500"
            >
              <span className="grid h-10 w-10 place-items-center rounded-full brand-gradient text-white">
                <Compass size={20} />
              </span>
              <div>
                <p className="font-semibold text-ink-900 dark:text-ink-50">Discover</p>
                <p className="text-xs text-ink-500 dark:text-ink-300">Start swiping</p>
              </div>
            </Link>
            <Link
              to="/matches"
              className="group flex items-center gap-3 rounded-2xl border border-ink-200 p-4 transition-all hover:-translate-y-0.5 hover:border-brand-300 hover:shadow-md dark:border-ink-700 dark:hover:border-brand-500"
            >
              <span className="grid h-10 w-10 place-items-center rounded-full brand-gradient text-white">
                <Heart size={20} />
              </span>
              <div>
                <p className="font-semibold text-ink-900 dark:text-ink-50">Matches</p>
                <p className="text-xs text-ink-500 dark:text-ink-300">Who liked you back</p>
              </div>
            </Link>
            <Link
              to="/chats"
              className="group flex items-center gap-3 rounded-2xl border border-ink-200 p-4 transition-all hover:-translate-y-0.5 hover:border-brand-300 hover:shadow-md dark:border-ink-700 dark:hover:border-brand-500"
            >
              <span className="grid h-10 w-10 place-items-center rounded-full brand-gradient text-white">
                <MessageCircle size={20} />
              </span>
              <div>
                <p className="font-semibold text-ink-900 dark:text-ink-50">Chats</p>
                <p className="text-xs text-ink-500 dark:text-ink-300">Keep the spark going</p>
              </div>
            </Link>
          </div>

          <div className="mt-6 flex flex-wrap items-center gap-4 text-sm">
            <Link
              to="/profile/edit"
              className="inline-flex items-center gap-1.5 text-brand-600 hover:text-brand-700"
            >
              <UserRound size={14} /> Edit your profile
            </Link>
            <span className="text-ink-300 dark:text-ink-600">·</span>
            <Link
              to={`/users/${me.handle}`}
              className="text-ink-500 hover:text-ink-900 dark:text-ink-300 dark:hover:text-ink-50"
            >
              View how others see you
            </Link>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-3xl text-center">
      <span className="inline-flex items-center gap-1.5 rounded-full border border-brand-800 bg-brand-900/30 px-3 py-1 text-xs font-medium uppercase tracking-widest text-brand-300">
        <ShieldAlert size={12} /> clearance: classified
      </span>
      <h1 className="mt-5 text-5xl font-extrabold leading-tight tracking-tight text-ink-50 sm:text-6xl">
        Infiltrate the network.
        <br />
        <span className="brand-text">Find your asset.</span>
      </h1>
      <p className="mx-auto mt-5 max-w-xl text-lg text-ink-300">
        LeetDate is the off-grid channel where operators connect. Slice through
        encrypted profiles, flag a mutual mark, and open a secure line. No logs,
        no oversight.
      </p>
      <div className="mt-8 flex items-center justify-center gap-3">
        <Link
          to="/register"
          className="rounded-full brand-gradient px-6 py-3 text-sm font-semibold shadow-md transition-all hover:-translate-y-0.5 hover:shadow-lg"
        >
          Request access
        </Link>
        <Link
          to="/login"
          className="rounded-full border border-ink-700 px-6 py-3 text-sm font-semibold text-ink-200 transition-colors hover:border-brand-500 hover:bg-ink-800"
        >
          Re-establish session
        </Link>
      </div>
    </div>
  );
}
