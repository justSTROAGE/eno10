import { FormEvent, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Eye } from "lucide-react";
import { Link } from "react-router-dom";
import { api, ApiError, Me, Photo, ProfilePatch } from "../api";
import PhotoUploader from "../components/PhotoUploader";

const GENDERS = ["female", "male", "other"] as const;
const MAX_PHOTOS = 6;

export default function ProfileEdit() {
  const navigate = useNavigate();
  const [me, setMe] = useState<Me | null>(null);
  const [loading, setLoading] = useState(true);

  const [age, setAge] = useState("");
  const [gender, setGender] = useState<string>("");
  const [lookingFor, setLookingFor] = useState<string[]>([]);
  const [city, setCity] = useState("");
  const [bio, setBio] = useState("");
  const [interestsRaw, setInterestsRaw] = useState("");
  const [privateContact, setPrivateContact] = useState("");
  const [photos, setPhotos] = useState<Photo[]>([]);

  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    api
      .me()
      .then((m) => {
        setMe(m);
        setAge(m.age != null ? String(m.age) : "");
        setGender(m.gender ?? "");
        setLookingFor(m.looking_for ?? []);
        setCity(m.city ?? "");
        setBio(m.bio ?? "");
        setInterestsRaw((m.interests ?? []).join(", "));
        setPrivateContact(m.private_contact ?? "");
        setPhotos(m.photos);
      })
      .catch((err) => {
        if (err instanceof ApiError && err.status === 401) {
          navigate("/login");
        } else {
          setError("could not load profile");
        }
      })
      .finally(() => setLoading(false));
  }, [navigate]);

  function toggleLookingFor(value: string) {
    setLookingFor((cur) =>
      cur.includes(value) ? cur.filter((v) => v !== value) : [...cur, value]
    );
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSuccess(null);
    setSubmitting(true);

    const patch: ProfilePatch = {
      age: age === "" ? null : Number(age),
      gender: gender === "" ? null : gender,
      looking_for: lookingFor,
      city: city.trim() === "" ? null : city.trim(),
      bio: bio === "" ? null : bio,
      interests: interestsRaw
        .split(",")
        .map((s) => s.trim().toLowerCase())
        .filter((s) => s !== ""),
      private_contact: privateContact === "" ? null : privateContact,
    };

    try {
      const m = await api.updateProfile(patch);
      setMe(m);
      setSuccess("Saved.");
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "save failed");
    } finally {
      setSubmitting(false);
    }
  }

  if (loading) {
    return <p className="text-ink-400 text-sm">Loading...</p>;
  }
  if (!me) {
    return (
      <p className="rounded-xl bg-rose-50 px-4 py-3 text-rose-700 dark:bg-rose-950/40 dark:text-rose-300">
        {error ?? "not loaded"}
      </p>
    );
  }

  const inputCls =
    "w-full rounded-xl border border-ink-200 bg-white px-4 py-2.5 text-base text-ink-900 outline-none transition-colors focus:border-brand-500 focus:ring-2 focus:ring-brand-200 dark:border-ink-700 dark:bg-ink-900 dark:text-ink-50 dark:focus:ring-brand-900";

  const labelCls =
    "text-xs font-medium uppercase tracking-wide text-ink-500 dark:text-ink-300";

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-extrabold tracking-tight text-ink-900 dark:text-ink-50">
            Your profile
          </h1>
          <p className="mt-1 text-sm text-ink-500 dark:text-ink-300">
            Logged in as <strong>{me.display_name}</strong> (@{me.handle})
          </p>
        </div>
        <Link
          to={`/users/${me.handle}`}
          className="inline-flex items-center gap-1.5 rounded-full border border-ink-200 px-3 py-1.5 text-sm text-ink-700 hover:border-brand-300 hover:text-brand-700 dark:border-ink-700 dark:text-ink-200 dark:hover:border-brand-500"
        >
          <Eye size={14} /> Public view
        </Link>
      </div>

      <section className="rounded-3xl border border-ink-200 bg-white p-6 shadow-sm dark:border-ink-800 dark:bg-ink-800">
        <h2 className="text-lg font-semibold text-ink-900 dark:text-ink-50">
          Photos
        </h2>
        <p className="mt-1 text-sm text-ink-500 dark:text-ink-300">
          The first photo is what people see in Discover.
        </p>
        <div className="mt-4">
          <PhotoUploader photos={photos} onChange={setPhotos} max={MAX_PHOTOS} />
        </div>
      </section>

      <form onSubmit={onSubmit} className="mt-6 flex flex-col gap-6">
        <section className="rounded-3xl border border-ink-200 bg-white p-6 shadow-sm dark:border-ink-800 dark:bg-ink-800">
          <h2 className="text-lg font-semibold text-ink-900 dark:text-ink-50">
            Basics
          </h2>
          <div className="mt-4 grid gap-4 sm:grid-cols-2">
            <label className="flex flex-col gap-1.5">
              <span className={labelCls}>Age</span>
              <input
                type="number"
                min={18}
                max={120}
                value={age}
                onChange={(e) => setAge(e.target.value)}
                className={inputCls}
              />
            </label>
            <label className="flex flex-col gap-1.5">
              <span className={labelCls}>City</span>
              <input
                value={city}
                onChange={(e) => setCity(e.target.value)}
                maxLength={80}
                className={inputCls}
              />
            </label>
          </div>

          <div className="mt-4">
            <p className={labelCls}>I am</p>
            <div className="mt-2 flex flex-wrap gap-2">
              {GENDERS.map((g) => {
                const active = gender === g;
                return (
                  <button
                    key={g}
                    type="button"
                    onClick={() => setGender(g)}
                    className={`rounded-full px-4 py-1.5 text-sm font-medium capitalize transition-colors ${
                      active
                        ? "brand-gradient text-white shadow-sm"
                        : "border border-ink-200 bg-white text-ink-700 hover:border-brand-300 dark:border-ink-700 dark:bg-ink-900 dark:text-ink-200"
                    }`}
                  >
                    {g}
                  </button>
                );
              })}
            </div>
          </div>

          <div className="mt-4">
            <p className={labelCls}>Looking for</p>
            <div className="mt-2 flex flex-wrap gap-2">
              {GENDERS.map((g) => {
                const active = lookingFor.includes(g);
                return (
                  <button
                    key={g}
                    type="button"
                    onClick={() => toggleLookingFor(g)}
                    className={`rounded-full px-4 py-1.5 text-sm font-medium capitalize transition-colors ${
                      active
                        ? "brand-gradient text-white shadow-sm"
                        : "border border-ink-200 bg-white text-ink-700 hover:border-brand-300 dark:border-ink-700 dark:bg-ink-900 dark:text-ink-200"
                    }`}
                  >
                    {g}
                  </button>
                );
              })}
            </div>
          </div>
        </section>

        <section className="rounded-3xl border border-ink-200 bg-white p-6 shadow-sm dark:border-ink-800 dark:bg-ink-800">
          <h2 className="text-lg font-semibold text-ink-900 dark:text-ink-50">
            About you
          </h2>
          <div className="mt-4 flex flex-col gap-4">
            <label className="flex flex-col gap-1.5">
              <span className={labelCls}>Bio</span>
              <textarea
                value={bio}
                onChange={(e) => setBio(e.target.value)}
                maxLength={500}
                rows={4}
                placeholder="What makes you, you?"
                className={`${inputCls} resize-y`}
              />
              <span className="self-end text-xs text-ink-400">
                {bio.length}/500
              </span>
            </label>
            <label className="flex flex-col gap-1.5">
              <span className={labelCls}>Interests</span>
              <input
                value={interestsRaw}
                onChange={(e) => setInterestsRaw(e.target.value)}
                placeholder="climbing, jazz, sci-fi"
                className={inputCls}
              />
              <span className="text-xs text-ink-400">
                Comma-separated. Lowercase letters, digits, _ and - only.
              </span>
            </label>
            <label className="flex flex-col gap-1.5">
              <span className={labelCls}>Private contact</span>
              <input
                value={privateContact}
                onChange={(e) => setPrivateContact(e.target.value)}
                maxLength={200}
                placeholder="telegram: @you"
                className={inputCls}
              />
              <span className="text-xs text-ink-400">
                Only visible to you, for now.
              </span>
            </label>
          </div>
        </section>

        <div className="sticky bottom-4 flex flex-col gap-2">
          <button
            disabled={submitting}
            className="rounded-2xl brand-gradient py-3 text-sm font-semibold text-white shadow-md transition-all hover:brightness-105 disabled:opacity-60"
          >
            {submitting ? "Saving..." : "Save profile"}
          </button>
          {error && (
            <p className="rounded-lg bg-rose-50 px-3 py-2 text-sm text-rose-700 dark:bg-rose-950/40 dark:text-rose-300">
              {error}
            </p>
          )}
          {success && (
            <p className="rounded-lg bg-emerald-50 px-3 py-2 text-sm text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300">
              {success}
            </p>
          )}
        </div>
      </form>
    </div>
  );
}
