import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { MapPin } from "lucide-react";
import { api, ApiError, PublicProfile } from "../api";

export default function ProfileView() {
  const { handle } = useParams();
  const [profile, setProfile] = useState<PublicProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [photoIdx, setPhotoIdx] = useState(0);

  useEffect(() => {
    if (!handle) return;
    setLoading(true);
    api
      .getUser(handle)
      .then((p) => setProfile(p))
      .catch((err) => {
        if (err instanceof ApiError && err.status === 404) {
          setNotFound(true);
        } else {
          setError(err instanceof ApiError ? err.message : "load failed");
        }
      })
      .finally(() => setLoading(false));
  }, [handle]);

  if (loading) return <p className="text-ink-400 text-sm">Loading...</p>;
  if (notFound) {
    return (
      <p className="rounded-xl bg-rose-50 px-4 py-3 text-rose-700 dark:bg-rose-950/40 dark:text-rose-300">
        No user with handle “{handle}”.
      </p>
    );
  }
  if (error) {
    return (
      <p className="rounded-xl bg-rose-50 px-4 py-3 text-rose-700 dark:bg-rose-950/40 dark:text-rose-300">
        {error}
      </p>
    );
  }
  if (!profile) return null;

  return (
    <div className="mx-auto max-w-md">
      <div className="overflow-hidden rounded-3xl border border-ink-200 bg-white shadow-lg dark:border-ink-800 dark:bg-ink-800">
        <div className="relative h-[min(56vh,560px)] w-full bg-ink-100 dark:bg-ink-900">
          {profile.photos.length > 0 ? (
            <img
              src={profile.photos[photoIdx]?.url ?? profile.photos[0].url}
              alt={profile.display_name}
              className="h-full w-full object-cover"
            />
          ) : (
            <div className="grid h-full w-full place-items-center text-ink-400">
              No photo yet
            </div>
          )}

          {profile.photos.length > 1 && (
            <div className="absolute inset-x-3 top-3 flex gap-1.5">
              {profile.photos.map((p, i) => (
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

          <div className="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/80 via-black/30 to-transparent p-5 pt-20">
            <h1 className="text-3xl font-extrabold tracking-tight text-white drop-shadow-sm">
              {profile.display_name}
              {profile.age != null && (
                <span className="ml-2 font-semibold opacity-90">
                  {profile.age}
                </span>
              )}
            </h1>
            <p className="mt-1 text-sm text-white/80">@{profile.handle}</p>
            {profile.city && (
              <p className="mt-1 flex items-center gap-1 text-sm text-white/80">
                <MapPin size={14} /> {profile.city}
              </p>
            )}
          </div>
        </div>

        <div className="space-y-4 p-6">
          {profile.bio && (
            <p className="text-sm leading-relaxed text-ink-700 dark:text-ink-200">
              {profile.bio}
            </p>
          )}
          {profile.interests && profile.interests.length > 0 && (
            <div className="flex flex-wrap gap-1.5">
              {profile.interests.map((tag) => (
                <span
                  key={tag}
                  className="rounded-full bg-brand-50 px-2.5 py-1 text-xs font-medium text-brand-700 dark:bg-brand-900/30 dark:text-brand-300"
                >
                  #{tag}
                </span>
              ))}
            </div>
          )}
          {(profile.gender ||
            (profile.looking_for && profile.looking_for.length > 0)) && (
            <p className="text-xs text-ink-500 dark:text-ink-300">
              {profile.gender && <span>{profile.gender}</span>}
              {profile.gender &&
                profile.looking_for &&
                profile.looking_for.length > 0 &&
                " · "}
              {profile.looking_for && profile.looking_for.length > 0 && (
                <span>looking for {profile.looking_for.join(", ")}</span>
              )}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
