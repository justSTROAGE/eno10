import React, {
  createContext,
  ReactNode,
  useCallback,
  useContext,
  useEffect,
  useState,
} from "react";
import ReactDOM from "react-dom/client";
import {
  BrowserRouter,
  Link,
  NavLink,
  Route,
  Routes,
  useNavigate,
} from "react-router-dom";
import { Compass, Crown, Heart, LogOut, MessageCircle, Terminal, UserRound } from "lucide-react";
import "./styles.css";

import Landing from "./pages/Landing";
import Register from "./pages/Register";
import Login from "./pages/Login";
import ProfileEdit from "./pages/ProfileEdit";
import ProfileView from "./pages/ProfileView";
import Discover from "./pages/Discover";
import Matches from "./pages/Matches";
import Conversations from "./pages/Conversations";
import Chat from "./pages/Chat";
import Premium from "./pages/Premium";
import ThemeToggle from "./components/ThemeToggle";
import { api, ApiError, Me } from "./api";

type AuthState = {
  me: Me | null;
  loading: boolean;
  refresh: () => Promise<void>;
  clear: () => void;
};

const AuthContext = createContext<AuthState>({
  me: null,
  loading: true,
  refresh: async () => {},
  clear: () => {},
});

export function useAuth() {
  return useContext(AuthContext);
}

function AuthProvider({ children }: { children: ReactNode }) {
  const [me, setMe] = useState<Me | null>(null);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    try {
      const m = await api.me();
      setMe(m);
    } catch (err) {
      if (!(err instanceof ApiError && err.status === 401)) {
        console.error(err);
      }
      setMe(null);
    } finally {
      setLoading(false);
    }
  }, []);

  const clear = useCallback(() => setMe(null), []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return (
    <AuthContext.Provider value={{ me, loading, refresh, clear }}>
      {children}
    </AuthContext.Provider>
  );
}

function NavBar() {
  const { me, clear } = useAuth();
  const navigate = useNavigate();

  async function onLogout() {
    try {
      await api.logout();
    } catch (err) {
      console.error(err);
    }
    clear();
    navigate("/");
  }

  const linkBase =
    "inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm font-medium transition-colors";
  const linkInactive =
    "text-ink-600 hover:text-ink-900 hover:bg-ink-100 dark:text-ink-300 dark:hover:text-ink-50 dark:hover:bg-ink-800";
  const linkActive =
    "text-white brand-gradient shadow-sm";

  return (
    <nav className="sticky top-0 z-40 w-full border-b border-ink-200/70 bg-white/85 backdrop-blur dark:border-ink-800/70 dark:bg-ink-900/80">
      <div className="mx-auto flex max-w-5xl items-center gap-2 px-6 py-3">
        <Link to="/" className="flex items-center gap-2">
          <span className="grid h-9 w-9 place-items-center rounded-md brand-gradient shadow-sm">
            <Terminal size={18} strokeWidth={2.4} />
          </span>
          <span className="caret text-xl font-extrabold tracking-tight brand-text glitch">
            root@leetdate
          </span>
        </Link>

        <div className="ml-6 flex flex-1 items-center gap-1">
          {me && (
            <>
              <NavLink
                to="/discover"
                className={({ isActive }) =>
                  `${linkBase} ${isActive ? linkActive : linkInactive}`
                }
              >
                <Compass size={16} /> Discover
              </NavLink>
              <NavLink
                to="/matches"
                className={({ isActive }) =>
                  `${linkBase} ${isActive ? linkActive : linkInactive}`
                }
              >
                <Heart size={16} /> Matches
              </NavLink>
              <NavLink
                to="/chats"
                className={({ isActive }) =>
                  `${linkBase} ${isActive ? linkActive : linkInactive}`
                }
              >
                <MessageCircle size={16} /> Chats
              </NavLink>
              <NavLink
                to="/premium"
                className={({ isActive }) =>
                  `${linkBase} ${isActive ? linkActive : linkInactive}`
                }
              >
                <Crown size={16} /> Premium
              </NavLink>
              <NavLink
                to="/profile/edit"
                className={({ isActive }) =>
                  `${linkBase} ${isActive ? linkActive : linkInactive}`
                }
              >
                <UserRound size={16} /> Profile
              </NavLink>
            </>
          )}
        </div>

        <div className="flex items-center gap-2">
          {!me ? (
            <>
              <Link
                to="/login"
                className="rounded-full px-4 py-1.5 text-sm font-medium text-ink-700 hover:bg-ink-100 dark:text-ink-200 dark:hover:bg-ink-800"
              >
                Log in
              </Link>
              <Link
                to="/register"
                className="rounded-full brand-gradient px-4 py-1.5 text-sm font-semibold text-white shadow-sm hover:brightness-105"
              >
                Sign up
              </Link>
            </>
          ) : (
            <button
              type="button"
              onClick={onLogout}
              className="inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-medium text-ink-600 hover:bg-ink-100 dark:text-ink-300 dark:hover:bg-ink-800"
              title="Log out"
            >
              <LogOut size={16} /> Log out
            </button>
          )}
          <ThemeToggle />
        </div>
      </div>
    </nav>
  );
}

function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <NavBar />
        <main className="mx-auto max-w-5xl px-6 py-8">
          <Routes>
            <Route path="/" element={<Landing />} />
            <Route path="/login" element={<Login />} />
            <Route path="/register" element={<Register />} />
            <Route path="/profile/edit" element={<ProfileEdit />} />
            <Route path="/users/:handle" element={<ProfileView />} />
            <Route path="/discover" element={<Discover />} />
            <Route path="/matches" element={<Matches />} />
            <Route path="/chats" element={<Conversations />} />
            <Route path="/chats/:id" element={<Chat />} />
            <Route path="/premium" element={<Premium />} />
          </Routes>
        </main>
      </AuthProvider>
    </BrowserRouter>
  );
}

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
