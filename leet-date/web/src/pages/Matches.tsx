import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Compass, Heart } from "lucide-react";
import { api, ApiError, Match } from "../api";

export default function Matches() {
  const navigate = useNavigate();
  const [matches, setMatches] = useState<Match[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api
      .matches()
      .then((r) => setMatches(r.matches))
      .catch((err) => {
        if (err instanceof ApiError && err.status === 401) {
          navigate("/login");
          return;
        }
        setError(err instanceof ApiError ? err.message : "load failed");
      })
      .finally(() => setLoading(false));
  }, [navigate]);

  if (loading) return <p className="text-ink-400 text-sm">Loading...</p>;
  if (error) {
    return (
      <p className="rounded-xl bg-rose-50 px-4 py-3 text-rose-700 dark:bg-rose-950/40 dark:text-rose-300">
        {error}
      </p>
    );
  }

  if (matches.length === 0) {
    return (
      <div className="mx-auto max-w-md text-center">
        <h1 className="text-3xl font-extrabold tracking-tight text-ink-900 dark:text-ink-50">
          Matches
        </h1>
        <div className="mt-6 rounded-3xl border border-dashed border-ink-300 bg-white px-8 py-12 dark:border-ink-700 dark:bg-ink-800">
          <span className="grid mx-auto h-12 w-12 place-items-center rounded-full brand-gradient text-white">
            <Heart size={20} />
          </span>
          <p className="mt-4 text-sm text-ink-500 dark:text-ink-300">
            No matches yet — keep swiping.
          </p>
          <Link
            to="/discover"
            className="mt-4 inline-flex items-center gap-1.5 rounded-full brand-gradient px-4 py-2 text-sm font-semibold text-white"
          >
            <Compass size={14} /> Discover
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex items-end justify-between">
        <div>
          <h1 className="text-3xl font-extrabold tracking-tight text-ink-900 dark:text-ink-50">
            Your matches
          </h1>
          <p className="mt-1 text-sm text-ink-500 dark:text-ink-300">
            {matches.length} {matches.length === 1 ? "person likes" : "people like"} you back.
          </p>
        </div>
      </div>

      <ul className="grid grid-cols-2 gap-4 sm:grid-cols-3">
        {matches.map((m) => {
          const primary = m.user.photos[0];
          return (
            <li key={m.user.id}>
              <Link
                to={`/users/${m.user.handle}`}
                className="group block overflow-hidden rounded-2xl border border-ink-200 bg-white shadow-sm transition-all hover:-translate-y-0.5 hover:shadow-md dark:border-ink-800 dark:bg-ink-800"
              >
                <div className="relative aspect-square w-full overflow-hidden bg-ink-100 dark:bg-ink-900">
                  {primary ? (
                    <img
                      src={primary.url}
                      alt={m.user.display_name}
                      className="h-full w-full object-cover transition-transform duration-300 group-hover:scale-105"
                    />
                  ) : (
                    <div className="grid h-full w-full place-items-center text-ink-400">
                      No photo
                    </div>
                  )}
                  <div className="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/70 to-transparent p-3 pt-12">
                    <p className="text-base font-bold text-white drop-shadow-sm">
                      {m.user.display_name}
                      {m.user.age != null && (
                        <span className="ml-1 font-semibold opacity-90">
                          {m.user.age}
                        </span>
                      )}
                    </p>
                    <p className="text-xs text-white/80">@{m.user.handle}</p>
                  </div>
                </div>
                <p className="px-3 py-2 text-[11px] text-ink-500 dark:text-ink-400">
                  Matched {new Date(m.matched_at).toLocaleDateString()}
                </p>
              </Link>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
