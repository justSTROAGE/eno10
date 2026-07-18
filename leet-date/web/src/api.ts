export const MAX_PHOTO_BYTES = 5 * 1024 * 1024;

export type Photo = {
  id: number;
  url: string;
  sort_order: number;
};

export type Me = {
  id: number;
  handle: string;
  display_name: string;
  age: number | null;
  gender: string | null;
  looking_for: string[] | null;
  city: string | null;
  bio: string | null;
  interests: string[] | null;
  private_contact: string | null;
  is_premium: boolean;
  photos: Photo[];
};

export type PublicProfile = {
  id: number;
  handle: string;
  display_name: string;
  age: number | null;
  gender: string | null;
  looking_for: string[] | null;
  city: string | null;
  bio: string | null;
  interests: string[] | null;
  is_premium: boolean;
  photos: Photo[];
};

export type Perk = { handle: string; perk_text: string };

export type SwipeDirection = "like" | "pass";

export type SwipeResult = { matched: boolean };

export type DiscoverResp = { user: PublicProfile | null };

export type Match = {
  user: PublicProfile;
  matched_at: string;
};

export type Conversation = {
  id: string;
  other_user: PublicProfile;
  created_at: string;
  last_message_at: string | null;
};

export type Message = {
  id: number;
  conversation_id: string;
  sender_id: number;
  body: string;
  created_at: string;
};

export type ProfilePatch = Partial<{
  age: number | null;
  gender: string | null;
  looking_for: string[];
  city: string | null;
  bio: string | null;
  interests: string[];
  private_contact: string | null;
}>;

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(path, {
    method,
    credentials: "include",
    headers: body ? { "Content-Type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : {};
  if (!res.ok) {
    throw new ApiError(res.status, data.error ?? `HTTP ${res.status}`);
  }
  return data as T;
}

function parseBody(text: string): any {
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
}

async function requestForm<T>(method: string, path: string, form: FormData): Promise<T> {
  const res = await fetch(path, {
    method,
    credentials: "include",
    body: form,
  });
  const text = await res.text();
  const data = parseBody(text);
  if (!res.ok) {
    const fallback =
      res.status === 413 ? "image is too large" : `HTTP ${res.status}`;
    throw new ApiError(res.status, data.error ?? fallback);
  }
  return data as T;
}

async function requestNoBody(method: string, path: string): Promise<void> {
  const res = await fetch(path, { method, credentials: "include" });
  if (!res.ok) {
    let msg = `HTTP ${res.status}`;
    try {
      const data = await res.json();
      if (data?.error) msg = data.error;
    } catch {}
    throw new ApiError(res.status, msg);
  }
}

type LoginResp = {
  id: number;
  handle: string;
  display_name: string;
};

export const api = {
  me: () => request<Me>("GET", "/api/me"),
  register: (handle: string, display_name: string, password: string) =>
    request<LoginResp>("POST", "/api/register", { handle, display_name, password }),
  login: (handle: string, password: string) =>
    request<LoginResp>("POST", "/api/login", { handle, password }),
  logout: () => request<{ ok: boolean }>("POST", "/api/logout"),

  getUser: (handle: string) =>
    request<PublicProfile>("GET", `/api/users/${encodeURIComponent(handle)}`),
  updateProfile: (patch: ProfilePatch) =>
    request<Me>("PATCH", "/api/me", patch),

  uploadPhoto: (file: File) => {
    const fd = new FormData();
    fd.append("file", file);
    return requestForm<Photo>("POST", "/api/me/photos", fd);
  },
  reorderPhoto: (id: number, sort_order: number) =>
    request<{ ok: boolean }>("PATCH", `/api/me/photos/${id}`, { sort_order }),
  deletePhoto: (id: number) => requestNoBody("DELETE", `/api/me/photos/${id}`),

  discover: () => request<DiscoverResp>("GET", "/api/discover"),
  swipe: (target_id: number, direction: SwipeDirection) =>
    request<SwipeResult>("POST", "/api/swipe", { target_id, direction }),
  matches: () =>
    request<{ matches: Match[] }>("GET", "/api/matches"),

  conversations: () =>
    request<{ conversations: Conversation[] }>("GET", "/api/conversations"),
  conversation: (id: string) =>
    request<Conversation>("GET", `/api/conversations/${encodeURIComponent(id)}`),
  messages: (id: string) =>
    request<{ messages: Message[] }>("GET", `/api/conversations/${encodeURIComponent(id)}/messages`),
  sendMessage: (id: string, body: string) =>
    request<Message>("POST", `/api/conversations/${encodeURIComponent(id)}/messages`, { body }),

  redeemPremium: (token: string) =>
    request<{ ok: boolean; is_premium: boolean; amount_cents: number }>(
      "POST",
      "/api/me/redeem-premium",
      { token },
    ),
  setMyPerk: (perk_text: string) =>
    request<Perk>("POST", "/api/me/perk", { perk_text }),
  getUserPerk: (handle: string) =>
    request<Perk>("GET", `/api/users/${encodeURIComponent(handle)}/perk`),
};

export type WSEvent =
  | { type: "hello"; user_id: number }
  | { type: "message"; message: Message };

export function openSocket(onEvent: (e: WSEvent) => void): WebSocket {
  const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
  const ws = new WebSocket(`${proto}//${window.location.host}/api/ws`);
  ws.onmessage = (ev) => {
    try {
      onEvent(JSON.parse(ev.data) as WSEvent);
    } catch {
      // ignore non-JSON frames
    }
  };
  return ws;
}
