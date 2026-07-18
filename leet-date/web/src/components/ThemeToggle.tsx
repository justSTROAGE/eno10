import { ShieldCheck } from "lucide-react";

export default function ThemeToggle() {
  return (
    <span
      title="End-to-end encrypted channel"
      className="hidden items-center gap-1.5 rounded-full border border-brand-500/40 bg-brand-900/40 px-2.5 py-1 text-[11px] font-semibold uppercase tracking-wider text-brand-300 sm:inline-flex"
    >
      <span className="relative grid h-2 w-2 place-items-center">
        <span className="absolute h-2 w-2 animate-ping rounded-full bg-brand-500/70" />
        <span className="h-1.5 w-1.5 rounded-full bg-brand-500" />
      </span>
      <ShieldCheck size={13} /> secure
    </span>
  );
}
