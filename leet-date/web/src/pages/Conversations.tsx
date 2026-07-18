import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { MessageCircle } from "lucide-react";
import { api, ApiError, Conversation } from "../api";

function formatStamp(iso: string): string {
  const d = new Date(iso);
  const now = new Date();
  const sameDay =
    d.getFullYear() === now.getFullYear() &&
    d.getMonth() === now.getMonth() &&
    d.getDate() === now.getDate();
  if (sameDay) {
    return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  }
  return d.toLocaleDateString();
}

export default function Conversations() {
  const navigate = useNavigate();
  const [items, setItems] = useState<Conversation[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api
      .conversations()
      .then((r) => setItems(r.conversations))
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

  if (items.length === 0) {
    return (
      <div className="mx-auto max-w-md text-center">
        <h1 className="text-3xl font-extrabold tracking-tight text-ink-900 dark:text-ink-50">
          Chats
        </h1>
        <div className="mt-6 rounded-3xl border border-dashed border-ink-300 bg-white px-8 py-12 dark:border-ink-700 dark:bg-ink-800">
          <span className="grid mx-auto h-12 w-12 place-items-center rounded-full brand-gradient text-white">
            <MessageCircle size={20} />
          </span>
          <p className="mt-4 text-sm text-ink-500 dark:text-ink-300">
            No chats yet. Find a match first.
          </p>
          <Link
            to="/discover"
            className="mt-4 inline-flex items-center rounded-full brand-gradient px-4 py-2 text-sm font-semibold text-white"
          >
            Discover
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-xl">
      <h1 className="text-3xl font-extrabold tracking-tight text-ink-900 dark:text-ink-50">
        Chats
      </h1>
      <p className="mt-1 text-sm text-ink-500 dark:text-ink-300">
        {items.length} {items.length === 1 ? "conversation" : "conversations"}
      </p>

      <ul className="mt-6 overflow-hidden rounded-3xl border border-ink-200 bg-white shadow-sm dark:border-ink-800 dark:bg-ink-800">
        {items.map((c, idx) => {
          const primary = c.other_user.photos[0];
          const ts = c.last_message_at ?? c.created_at;
          return (
            <li
              key={c.id}
              className={
                idx > 0
                  ? "border-t border-ink-100 dark:border-ink-700/60"
                  : undefined
              }
            >
              <Link
                to={`/chats/${c.id}`}
                className="flex items-center gap-4 px-4 py-3 transition-colors hover:bg-ink-50 dark:hover:bg-ink-900/40"
              >
                <div className="relative h-14 w-14 shrink-0 overflow-hidden rounded-full bg-ink-200 dark:bg-ink-700">
                  {primary ? (
                    <img
                      src={primary.url}
                      alt={c.other_user.display_name}
                      className="h-full w-full object-cover"
                    />
                  ) : (
                    <div className="grid h-full w-full place-items-center text-xs text-ink-500">
                      ?
                    </div>
                  )}
                </div>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-base font-semibold text-ink-900 dark:text-ink-50">
                    {c.other_user.display_name}
                  </p>
                  <p className="truncate text-sm text-ink-500 dark:text-ink-300">
                    {c.last_message_at ? "Tap to read messages" : "Say hi to start"}
                  </p>
                </div>
                <span className="shrink-0 text-xs text-ink-400 dark:text-ink-500">
                  {formatStamp(ts)}
                </span>
              </Link>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
