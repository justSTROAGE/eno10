import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Heart, MapPin, PartyPopper, Sparkles, X } from "lucide-react";
import { api, ApiError, PublicProfile, SwipeDirection } from "../api";

export default function Discover() {
  const navigate = useNavigate();
  const [candidate, setCandidate] = useState<PublicProfile | null>(null);
  const [done, setDone] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [lastMatch, setLastMatch] = useState<string | null>(null);
  const [photoIdx, setPhotoIdx] = useState(0);

  function loadNext() {
    setLoading(true);
    setError(null);
    setPhotoIdx(0);
    api
      .discover()
      .then((r) => {
        if (r.user) {
          setCandidate(r.user);
          setDone(false);
        } else {
          setCandidate(null);
          setDone(true);
        }
      })
      .catch((err) => {
        if (err instanceof ApiError && err.status === 401) {
          navigate("/login");
          return;
        }
        setError(err instanceof ApiError ? err.message : "load failed");
      })
      .finally(() => setLoading(false));
  }

  useEffect(loadNext, [navigate]);

  async function decide(direction: SwipeDirection) {
    if (!candidate || busy) return;
    setBusy(true);
    setError(null);
    try {
      const res = await api.swipe(candidate.id, direction);
      setLastMatch(res.matched ? candidate.display_name : null);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "swipe failed");
      setBusy(false);
      return;
    }
    setBusy(false);
    loadNext();
  }

  if (loading) {
    return (
      <div className="mx-auto max-w-md py-12 text-center text-ink-400">
        Finding someone for you...
      </div>
    );
  }
  if (error) {
    return (
      <div className="mx-auto max-w-md py-12 text-center">
        <p className="rounded-xl bg-rose-50 px-4 py-3 text-rose-700 dark:bg-rose-950/40 dark:text-rose-300">
          {error}
        </p>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-md">
      {lastMatch && (
        <div className="mb-4 flex items-center gap-3 rounded-2xl border border-brand-200 bg-brand-50 px-4 py-3 text-brand-800 dark:border-brand-700 dark:bg-brand-900/30 dark:text-brand-200">
          <PartyPopper size={20} className="shrink-0" />
          <p className="flex-1 text-sm">
            It’s a match with <strong>{lastMatch}</strong>!
          </p>
          <Link
            to="/chats"
            className="rounded-full brand-gradient px-3 py-1 text-xs font-semibold text-white"
          >
            Say hi
          </Link>
        </div>
      )}

      {done || !candidate ? (
        <div className="rounded-3xl border border-dashed border-ink-300 bg-white px-8 py-14 text-center dark:border-ink-700 dark:bg-ink-800">
          <span className="grid mx-auto h-14 w-14 place-items-center rounded-full brand-gradient text-white">
            <Sparkles size={22} />
          </span>
          <h2 className="mt-4 text-xl font-bold text-ink-900 dark:text-ink-50">
            You’re all caught up
          </h2>
          <p className="mt-2 text-sm text-ink-500 dark:text-ink-300">
            No more candidates for now. Check back later.
          </p>
        </div>
      ) : (
        <>
          <div className="relative overflow-hidden rounded-3xl border border-ink-200 bg-white shadow-lg dark:border-ink-800 dark:bg-ink-800">
            <div className="relative h-[min(56vh,560px)] w-full bg-ink-100 dark:bg-ink-900">
              {candidate.photos.length > 0 ? (
                <img
                  src={candidate.photos[photoIdx]?.url ?? candidate.photos[0].url}
                  alt={candidate.display_name}
                  className="h-full w-full object-cover"
                />
              ) : (
                <div className="grid h-full w-full place-items-center text-ink-400">
                  No photo yet
                </div>
              )}

              {/* photo step dots */}
              {candidate.photos.length > 1 && (
                <div className="absolute inset-x-3 top-3 flex gap-1.5">
                  {candidate.photos.map((p, i) => (
                    <button
                      key={p.id}
                      type="button"
                      onClick={() => setPhotoIdx(i)}
                      className={`h-1 flex-1 rounded-full transition-colors ${
                        i === photoIdx ? "bg-white" : "bg-white/40"
                      }`}
                      aria-label={`Photo ${i + 1}`}
                    />
                  ))}
                </div>
              )}

              {/* gradient + overlay text */}
              <div className="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/80 via-black/30 to-transparent p-5 pt-20">
                <h2 className="text-3xl font-extrabold tracking-tight text-white drop-shadow-sm">
                  {candidate.display_name}
                  {candidate.age != null && (
                    <span className="ml-2 font-semibold opacity-90">
                      {candidate.age}
                    </span>
                  )}
                </h2>
                <p className="mt-1 text-sm text-white/80">@{candidate.handle}</p>
                {candidate.city && (
                  <p className="mt-1 flex items-center gap-1 text-sm text-white/80">
                    <MapPin size={14} /> {candidate.city}
                  </p>
                )}
              </div>
            </div>

            <div className="space-y-3 p-5">
              {candidate.bio && (
                <p className="text-sm leading-relaxed text-ink-700 dark:text-ink-200">
                  {candidate.bio}
                </p>
              )}
              {candidate.interests && candidate.interests.length > 0 && (
                <div className="flex flex-wrap gap-1.5">
                  {candidate.interests.map((tag) => (
                    <span
                      key={tag}
                      className="rounded-full bg-brand-50 px-2.5 py-1 text-xs font-medium text-brand-700 dark:bg-brand-900/30 dark:text-brand-300"
                    >
                      #{tag}
                    </span>
                  ))}
                </div>
              )}
              {(candidate.gender || (candidate.looking_for && candidate.looking_for.length > 0)) && (
                <p className="text-xs text-ink-500 dark:text-ink-300">
                  {candidate.gender && <span>{candidate.gender}</span>}
                  {candidate.gender && candidate.looking_for && candidate.looking_for.length > 0 && " · "}
                  {candidate.looking_for && candidate.looking_for.length > 0 && (
                    <span>looking for {candidate.looking_for.join(", ")}</span>
                  )}
                </p>
              )}
            </div>
          </div>

          <div className="mt-4 flex items-center justify-center gap-6">
            <button
              type="button"
              onClick={() => decide("pass")}
              disabled={busy}
              aria-label="Pass"
              className="grid h-16 w-16 place-items-center rounded-full border-2 border-ink-200 bg-white text-ink-500 shadow-md transition-all hover:-translate-y-1 hover:border-rose-400 hover:text-rose-500 active:scale-95 disabled:opacity-50 dark:border-ink-700 dark:bg-ink-800 dark:text-ink-300"
            >
              <X size={28} strokeWidth={2.6} />
            </button>
            <button
              type="button"
              onClick={() => decide("like")}
              disabled={busy}
              aria-label="Like"
              className="grid h-20 w-20 place-items-center rounded-full brand-gradient text-white shadow-lg transition-all hover:-translate-y-1 hover:shadow-xl active:scale-95 disabled:opacity-50"
            >
              <Heart size={32} fill="currentColor" strokeWidth={2.4} />
            </button>
          </div>
        </>
      )}
    </div>
  );
}
