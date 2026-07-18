import { FormEvent, useEffect, useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { ArrowLeft, Send } from "lucide-react";
import {
  api,
  ApiError,
  Conversation,
  Me,
  Message,
  openSocket,
} from "../api";

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
  });
}

export default function Chat() {
  const navigate = useNavigate();
  const { id } = useParams<{ id: string }>();
  const convID = id ?? "";

  const [me, setMe] = useState<Me | null>(null);
  const [conv, setConv] = useState<Conversation | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);

  const bottomRef = useRef<HTMLDivElement | null>(null);
  const wsRef = useRef<WebSocket | null>(null);

  useEffect(() => {
    if (!convID) {
      setError("invalid conversation");
      setLoading(false);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const [meResp, convResp, msgsResp] = await Promise.all([
          api.me(),
          api.conversation(convID),
          api.messages(convID),
        ]);
        if (cancelled) return;
        setMe(meResp);
        setConv(convResp);
        setMessages(msgsResp.messages);
      } catch (err) {
        if (cancelled) return;
        if (err instanceof ApiError && err.status === 401) {
          navigate("/login");
          return;
        }
        setError(err instanceof ApiError ? err.message : "load failed");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [convID, navigate]);

  useEffect(() => {
    if (!me) return;
    const ws = openSocket((e) => {
      if (e.type === "message" && e.message.conversation_id === convID) {
        setMessages((prev) =>
          prev.some((m) => m.id === e.message.id) ? prev : [...prev, e.message],
        );
      }
    });
    wsRef.current = ws;
    return () => {
      ws.close();
      wsRef.current = null;
    };
  }, [me, convID]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages.length]);

  async function send(e: FormEvent) {
    e.preventDefault();
    const body = draft.trim();
    if (!body || sending) return;
    setSending(true);
    try {
      const m = await api.sendMessage(convID, body);
      setMessages((prev) =>
        prev.some((x) => x.id === m.id) ? prev : [...prev, m],
      );
      setDraft("");
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "send failed");
    } finally {
      setSending(false);
    }
  }

  if (loading) return <p className="text-ink-400 text-sm">Loading...</p>;
  if (error) {
    return (
      <p className="rounded-xl bg-rose-50 px-4 py-3 text-rose-700 dark:bg-rose-950/40 dark:text-rose-300">
        {error}
      </p>
    );
  }
  if (!conv || !me) {
    return (
      <p className="rounded-xl bg-rose-50 px-4 py-3 text-rose-700 dark:bg-rose-950/40 dark:text-rose-300">
        not found
      </p>
    );
  }

  const primary = conv.other_user.photos[0];

  return (
    <div className="mx-auto max-w-2xl">
      <div className="flex h-[calc(100vh-9rem)] flex-col overflow-hidden rounded-3xl border border-ink-200 bg-white shadow-sm dark:border-ink-800 dark:bg-ink-800">
        {/* Header */}
        <header className="flex items-center gap-3 border-b border-ink-200 px-5 py-3 dark:border-ink-700">
          <Link
            to="/chats"
            className="grid h-8 w-8 place-items-center rounded-full text-ink-500 hover:bg-ink-100 dark:text-ink-300 dark:hover:bg-ink-700"
            aria-label="Back to chats"
          >
            <ArrowLeft size={18} />
          </Link>
          <Link
            to={`/users/${conv.other_user.handle}`}
            className="flex flex-1 items-center gap-3 group"
          >
            <div className="h-10 w-10 shrink-0 overflow-hidden rounded-full bg-ink-200 dark:bg-ink-700">
              {primary ? (
                <img
                  src={primary.url}
                  alt={conv.other_user.display_name}
                  className="h-full w-full object-cover"
                />
              ) : null}
            </div>
            <div className="min-w-0">
              <p className="truncate font-semibold text-ink-900 group-hover:text-brand-600 dark:text-ink-50 dark:group-hover:text-brand-400">
                {conv.other_user.display_name}
              </p>
              <p className="truncate text-xs text-ink-500 dark:text-ink-300">
                @{conv.other_user.handle}
              </p>
            </div>
          </Link>
        </header>

        {/* Messages */}
        <div className="flex-1 overflow-y-auto bg-ink-50 px-4 py-4 dark:bg-ink-900/40">
          {messages.length === 0 ? (
            <div className="flex h-full items-center justify-center">
              <p className="text-sm text-ink-400">
                No messages yet — say hi 👋
              </p>
            </div>
          ) : (
            <div className="flex flex-col gap-1.5">
              {messages.map((m, i) => {
                const mine = m.sender_id === me.id;
                const prev = messages[i - 1];
                const grouped =
                  prev && prev.sender_id === m.sender_id &&
                  new Date(m.created_at).getTime() -
                    new Date(prev.created_at).getTime() <
                    60_000;
                return (
                  <div
                    key={m.id}
                    className={`flex flex-col ${mine ? "items-end" : "items-start"}`}
                  >
                    <div
                      className={`max-w-[75%] rounded-3xl px-4 py-2 text-sm leading-snug whitespace-pre-wrap break-words shadow-sm ${
                        mine
                          ? "brand-gradient text-white rounded-br-md"
                          : "border border-ink-200 bg-white text-ink-900 rounded-bl-md dark:border-ink-600 dark:bg-ink-700 dark:text-ink-50"
                      }`}
                    >
                      {m.body}
                    </div>
                    {!grouped && (
                      <span className="mt-0.5 px-2 text-[10px] text-ink-400">
                        {formatTime(m.created_at)}
                      </span>
                    )}
                  </div>
                );
              })}
              <div ref={bottomRef} />
            </div>
          )}
        </div>

        {/* Composer */}
        <form
          onSubmit={send}
          className="flex items-center gap-2 border-t border-ink-200 bg-white px-3 py-3 dark:border-ink-700 dark:bg-ink-800"
        >
          <input
            type="text"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="Write a message..."
            maxLength={2000}
            disabled={sending}
            className="flex-1 rounded-full border border-ink-200 bg-ink-50 px-4 py-2.5 text-sm outline-none transition-colors focus:border-brand-400 focus:bg-white focus:ring-2 focus:ring-brand-200 dark:border-ink-700 dark:bg-ink-900 dark:text-ink-50 dark:focus:bg-ink-900 dark:focus:ring-brand-900"
          />
          <button
            type="submit"
            disabled={sending || draft.trim() === ""}
            aria-label="Send message"
            className="grid h-10 w-10 shrink-0 place-items-center rounded-full brand-gradient text-white shadow-sm transition-all hover:brightness-105 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <Send size={16} strokeWidth={2.4} />
          </button>
        </form>
      </div>
    </div>
  );
}
