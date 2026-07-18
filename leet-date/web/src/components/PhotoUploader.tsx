import { ChangeEvent, DragEvent, useRef, useState } from "react";
import { Plus, Trash2 } from "lucide-react";
import { api, ApiError, MAX_PHOTO_BYTES, Photo } from "../api";

type Props = {
  photos: Photo[];
  onChange: (photos: Photo[]) => void;
  max: number;
};

export default function PhotoUploader({ photos, onChange, max }: Props) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [dragId, setDragId] = useState<number | null>(null);
  const [overId, setOverId] = useState<number | null>(null);
  const atMax = photos.length >= max;

  async function onPick(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setError(null);
    if (file.size > MAX_PHOTO_BYTES) {
      setError(
        `That image is ${(file.size / (1024 * 1024)).toFixed(
          1
        )} MB, please choose one under ${Math.floor(
          MAX_PHOTO_BYTES / (1024 * 1024)
        )} MB.`
      );
      if (inputRef.current) inputRef.current.value = "";
      return;
    }
    setBusy(true);
    try {
      const p = await api.uploadPhoto(file);
      onChange([...photos, p].sort((a, b) => a.sort_order - b.sort_order));
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "upload failed");
    } finally {
      setBusy(false);
      if (inputRef.current) inputRef.current.value = "";
    }
  }

  async function remove(id: number) {
    setError(null);
    try {
      await api.deletePhoto(id);
      onChange(photos.filter((p) => p.id !== id));
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "delete failed");
    }
  }

  async function reorderTo(sourceId: number, targetId: number) {
    if (sourceId === targetId) return;
    const from = photos.findIndex((p) => p.id === sourceId);
    const to = photos.findIndex((p) => p.id === targetId);
    if (from < 0 || to < 0) return;

    const next = photos.slice();
    const [moved] = next.splice(from, 1);
    next.splice(to, 0, moved);

    const renumbered = next.map((p, i) => ({ ...p, sort_order: i }));
    const prev = photos;
    onChange(renumbered);

    setError(null);
    try {
      const changed = renumbered.filter((p) => {
        const before = prev.find((q) => q.id === p.id);
        return before && before.sort_order !== p.sort_order;
      });
      for (const p of changed) {
        await api.reorderPhoto(p.id, p.sort_order);
      }
    } catch (err) {
      onChange(prev);
      setError(err instanceof ApiError ? err.message : "reorder failed");
    }
  }

  function onDragStart(e: DragEvent<HTMLDivElement>, id: number) {
    setDragId(id);
    e.dataTransfer.effectAllowed = "move";
    e.dataTransfer.setData("text/plain", String(id));
  }

  function onDragOver(e: DragEvent<HTMLDivElement>, id: number) {
    if (dragId === null) return;
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
    if (overId !== id) setOverId(id);
  }

  function onDragLeave(id: number) {
    if (overId === id) setOverId(null);
  }

  function onDrop(e: DragEvent<HTMLDivElement>, targetId: number) {
    e.preventDefault();
    const sourceId = dragId;
    setDragId(null);
    setOverId(null);
    if (sourceId !== null) reorderTo(sourceId, targetId);
  }

  function onDragEnd() {
    setDragId(null);
    setOverId(null);
  }

  return (
    <div>
      <div className="grid grid-cols-3 gap-3">
        {photos.map((p, idx) => {
          const isDragging = dragId === p.id;
          const isOver = overId === p.id && dragId !== null && dragId !== p.id;
          return (
            <div
              key={p.id}
              draggable
              onDragStart={(e) => onDragStart(e, p.id)}
              onDragOver={(e) => onDragOver(e, p.id)}
              onDragLeave={() => onDragLeave(p.id)}
              onDrop={(e) => onDrop(e, p.id)}
              onDragEnd={onDragEnd}
              className={[
                "group relative aspect-square cursor-grab overflow-hidden rounded-2xl border border-ink-200 bg-ink-100 transition-all dark:border-ink-700 dark:bg-ink-900",
                "active:cursor-grabbing",
                isDragging ? "photo-tile-dragging" : "",
                isOver ? "photo-tile-drag-over" : "",
              ]
                .filter(Boolean)
                .join(" ")}
            >
              <img
                src={p.url}
                alt={`photo ${p.id}`}
                draggable={false}
                className="h-full w-full select-none object-cover"
              />
              {idx === 0 && (
                <span className="absolute left-2 top-2 rounded-full brand-gradient px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-white shadow-sm">
                  Main
                </span>
              )}
              <button
                type="button"
                onClick={() => remove(p.id)}
                aria-label="Remove photo"
                className="absolute right-2 top-2 grid h-7 w-7 place-items-center rounded-full bg-black/55 text-white opacity-0 transition-opacity hover:bg-black/75 group-hover:opacity-100"
              >
                <Trash2 size={14} />
              </button>
            </div>
          );
        })}

        {!atMax && (
          <button
            type="button"
            onClick={() => inputRef.current?.click()}
            disabled={busy}
            className="grid aspect-square place-items-center rounded-2xl border-2 border-dashed border-ink-300 bg-white text-ink-400 transition-colors hover:border-brand-400 hover:bg-brand-50 hover:text-brand-500 disabled:opacity-50 dark:border-ink-700 dark:bg-ink-800 dark:hover:bg-brand-900/20"
          >
            <div className="flex flex-col items-center gap-1">
              <Plus size={22} />
              <span className="text-xs font-medium">
                {busy ? "Uploading..." : "Add photo"}
              </span>
            </div>
          </button>
        )}
      </div>

      <input
        ref={inputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        onChange={onPick}
        className="hidden"
      />

      <p className="mt-3 text-xs text-ink-500 dark:text-ink-300">
        {photos.length}/{max} photos
        {photos.length > 1 && " · drag to reorder"}
      </p>
      {error && (
        <p className="mt-2 rounded-lg bg-rose-50 px-3 py-2 text-sm text-rose-700 dark:bg-rose-950/40 dark:text-rose-300">
          {error}
        </p>
      )}
    </div>
  );
}
