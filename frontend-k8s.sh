#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================================
# Telecom Platform Frontend + Kubernetes Bootstrap — GKE-adjusted
#
# Run from the devops-portfolio repository root:
#   chmod +x bootstrap-frontend-k8s.sh
#   ./bootstrap-frontend-k8s.sh
#
# Useful overrides:
#   PROJECT_ID=my-project IMAGE_TAG=v1 ./bootstrap-frontend-k8s.sh
#   BUILD_PUSH=0 DEPLOY=0 ./bootstrap-frontend-k8s.sh
#   SERVICE_TYPE=ClusterIP ./bootstrap-frontend-k8s.sh
# ============================================================================

PROJECT_ID="${PROJECT_ID:-devops-project-503113}"
REGION="${REGION:-us-central1}"
AR_REPOSITORY="${AR_REPOSITORY:-dev-docker}"
NAMESPACE="${NAMESPACE:-telecom-platform}"
GKE_CLUSTER="${GKE_CLUSTER:-dev-gke}"
GKE_LOCATION="${GKE_LOCATION:-us-central1-a}"
GKE_LOCATION_TYPE="${GKE_LOCATION_TYPE:-zone}"
GET_CREDENTIALS="${GET_CREDENTIALS:-1}"
FRONTEND_NAME="${FRONTEND_NAME:-frontend}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d-%H%M%S)}"
BUILD_PUSH="${BUILD_PUSH:-1}"
DEPLOY="${DEPLOY:-1}"
SERVICE_TYPE="${SERVICE_TYPE:-ClusterIP}"
REPLICAS="${REPLICAS:-2}"

REGISTRY_HOST="${REGION}-docker.pkg.dev"
IMAGE="${REGISTRY_HOST}/${PROJECT_ID}/${AR_REPOSITORY}/${FRONTEND_NAME}:${IMAGE_TAG}"
STAMP="$(date +%Y%m%d-%H%M%S)"

log()  { printf '\033[1;34m[frontend]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

find_repo_root() {
  local current="$PWD"
  while [[ "$current" != "/" ]]; do
    if [[ -d "$current/services" ]] && \
       { [[ -f "$current/docker-compose.platform.yml" ]] || [[ -d "$current/k8s" ]] || [[ -d "$current/kubernetes" ]]; }; then
      printf '%s\n' "$current"
      return 0
    fi
    current="$(dirname "$current")"
  done
  return 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"
}

backup_path() {
  local source="$1"
  local relative="$2"
  [[ -e "$source" ]] || return 0
  local destination="$BACKUP_ROOT/$relative"
  mkdir -p "$(dirname "$destination")"
  cp -a "$source" "$destination"
  log "Backed up $relative"
}

write_file() {
  local target="$1"
  mkdir -p "$(dirname "$target")"
  cat > "$target"
  log "Wrote ${target#"$ROOT/"}"
}

ROOT="$(find_repo_root || true)"
[[ -n "${ROOT:-}" ]] || die "Run this script from the devops-portfolio repository or one of its subdirectories."
cd "$ROOT"

FRONTEND_DIR="$ROOT/services/$FRONTEND_NAME"
if [[ -d "$ROOT/k8s/apps" ]]; then
  K8S_DIR="$ROOT/k8s/apps/$FRONTEND_NAME"
elif [[ -d "$ROOT/kubernetes/base" ]]; then
  K8S_DIR="$ROOT/kubernetes/base/$FRONTEND_NAME"
else
  K8S_DIR="$ROOT/k8s/apps/$FRONTEND_NAME"
fi

BACKUP_ROOT="$ROOT/.frontend-backups/$STAMP"
backup_path "$FRONTEND_DIR" "services/$FRONTEND_NAME"
backup_path "$K8S_DIR" "${K8S_DIR#"$ROOT/"}"

mkdir -p "$FRONTEND_DIR/src" "$K8S_DIR"

# ----------------------------------------------------------------------------
# Frontend project
# ----------------------------------------------------------------------------

write_file "$FRONTEND_DIR/package.json" <<'EOF'
{
  "name": "telecom-operations-console",
  "private": true,
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite --host 0.0.0.0",
    "build": "tsc -b && vite build",
    "preview": "vite preview --host 0.0.0.0",
    "check": "tsc -b --pretty false"
  },
  "dependencies": {
    "react": "18.3.1",
    "react-dom": "18.3.1"
  },
  "devDependencies": {
    "@types/react": "18.3.12",
    "@types/react-dom": "18.3.1",
    "@vitejs/plugin-react": "4.3.4",
    "typescript": "5.7.2",
    "vite": "5.4.11"
  }
}
EOF

write_file "$FRONTEND_DIR/tsconfig.json" <<'EOF'
{
  "files": [],
  "references": [
    { "path": "./tsconfig.app.json" },
    { "path": "./tsconfig.node.json" }
  ]
}
EOF

write_file "$FRONTEND_DIR/tsconfig.app.json" <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "allowJs": false,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "strict": true,
    "forceConsistentCasingInFileNames": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx"
  },
  "include": ["src"]
}
EOF

write_file "$FRONTEND_DIR/tsconfig.node.json" <<'EOF'
{
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "allowImportingTsExtensions": true
  },
  "include": ["vite.config.ts"]
}
EOF

write_file "$FRONTEND_DIR/vite.config.ts" <<'EOF'
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/auth": "http://localhost:8080",
      "/api": "http://localhost:8080",
      "/health": "http://localhost:8080"
    }
  }
});
EOF

write_file "$FRONTEND_DIR/index.html" <<'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="theme-color" content="#08111f" />
    <meta
      name="description"
      content="Telecom operations console for devices, inventory, workflows, notifications, and audit events."
    />
    <title>Telecom Operations Console</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
EOF

write_file "$FRONTEND_DIR/src/main.tsx" <<'EOF'
import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import "./styles.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
EOF

write_file "$FRONTEND_DIR/src/App.tsx" <<'EOF'
import {
  FormEvent,
  ReactNode,
  useCallback,
  useEffect,
  useMemo,
  useState
} from "react";

type Json = Record<string, unknown>;
type Page =
  | "dashboard"
  | "devices"
  | "inventory"
  | "workflows"
  | "notifications"
  | "audit";

type Toast = { kind: "success" | "error"; message: string } | null;

type Device = {
  id: string;
  hostname: string;
  management_ip: string;
  vendor: string;
  model?: string | null;
  site?: string | null;
  software_version?: string | null;
  status: string;
  created_at?: string;
  updated_at?: string;
};

type InventoryItem = {
  id: string;
  name: string;
  category: string;
  quantity: number;
  low_stock_threshold: number;
  location: string;
  created_at: string;
  updated_at: string;
};

type Workflow = {
  id: string;
  name: string;
  device_id?: string | null;
  action: string;
  parameters: Json;
  state: string;
  result?: Json | null;
  error_message?: string | null;
  created_at: string;
  updated_at: string;
};

type Notification = {
  id: string;
  channel: string;
  recipient: string;
  subject: string;
  body: string;
  status: string;
  source_event_type?: string | null;
  source_event_id?: string | null;
  payload: Json;
  created_at: string;
};

type AuditEvent = {
  id: string;
  event_id: string;
  event_type: string;
  source: string;
  correlation_id?: string | null;
  occurred_at: string;
  payload: Json;
};

type Health = {
  status?: string;
  checks?: Record<string, string>;
  services?: Record<string, string>;
};

class ApiError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

const TOKEN_KEY = "telecom-platform-token";
const USER_KEY = "telecom-platform-user";

const navItems: { page: Page; label: string; icon: string }[] = [
  { page: "dashboard", label: "Overview", icon: "⌂" },
  { page: "devices", label: "Devices", icon: "◇" },
  { page: "inventory", label: "Inventory", icon: "▦" },
  { page: "workflows", label: "Workflows", icon: "▶" },
  { page: "notifications", label: "Notifications", icon: "●" },
  { page: "audit", label: "Audit trail", icon: "≡" }
];

function formatDate(value?: string | null): string {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? value
    : new Intl.DateTimeFormat(undefined, {
        dateStyle: "medium",
        timeStyle: "short"
      }).format(date);
}

function valueText(value: unknown): string {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

function statusTone(value: string): string {
  const normalized = value.toLowerCase();
  if (["ready", "alive", "active", "completed", "sent", "healthy"].includes(normalized))
    return "positive";
  if (["pending", "queued", "running", "maintenance", "unknown"].includes(normalized))
    return "warning";
  if (["failed", "unreachable", "inactive", "not_ready", "degraded"].includes(normalized))
    return "negative";
  return "neutral";
}

function Icon({ name }: { name: string }) {
  const paths: Record<string, ReactNode> = {
    refresh: (
      <>
        <path d="M20 11a8.1 8.1 0 0 0-14.9-4M4 4v5h5" />
        <path d="M4 13a8.1 8.1 0 0 0 14.9 4M20 20v-5h-5" />
      </>
    ),
    plus: <path d="M12 5v14M5 12h14" />,
    logout: (
      <>
        <path d="M10 17l5-5-5-5M15 12H3" />
        <path d="M14 3h5a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-5" />
      </>
    ),
    trash: (
      <>
        <path d="M3 6h18M8 6V4h8v2M19 6l-1 15H6L5 6M10 11v6M14 11v6" />
      </>
    ),
    play: <path d="M8 5v14l11-7z" />,
    edit: (
      <>
        <path d="M12 20h9" />
        <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L8 18l-4 1 1-4z" />
      </>
    ),
    search: (
      <>
        <circle cx="11" cy="11" r="7" />
        <path d="M20 20l-4-4" />
      </>
    ),
    close: <path d="M6 6l12 12M18 6L6 18" />
  };
  return (
    <svg
      viewBox="0 0 24 24"
      width="18"
      height="18"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {paths[name]}
    </svg>
  );
}

function Button({
  children,
  onClick,
  type = "button",
  variant = "primary",
  disabled = false,
  title
}: {
  children: ReactNode;
  onClick?: () => void;
  type?: "button" | "submit";
  variant?: "primary" | "secondary" | "danger" | "ghost";
  disabled?: boolean;
  title?: string;
}) {
  return (
    <button
      type={type}
      className={`button button-${variant}`}
      onClick={onClick}
      disabled={disabled}
      title={title}
    >
      {children}
    </button>
  );
}

function Badge({ value }: { value: string }) {
  return <span className={`badge badge-${statusTone(value)}`}>{value.replaceAll("_", " ")}</span>;
}

function EmptyState({ text }: { text: string }) {
  return (
    <div className="empty-state">
      <div className="empty-symbol">∿</div>
      <strong>No records yet</strong>
      <span>{text}</span>
    </div>
  );
}

function LoadingRows() {
  return (
    <div className="loading-list">
      {Array.from({ length: 5 }).map((_, index) => (
        <div className="skeleton-row" key={index} />
      ))}
    </div>
  );
}

function Modal({
  title,
  children,
  onClose
}: {
  title: string;
  children: ReactNode;
  onClose: () => void;
}) {
  useEffect(() => {
    const close = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", close);
    return () => window.removeEventListener("keydown", close);
  }, [onClose]);

  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <section className="modal" onMouseDown={(event) => event.stopPropagation()}>
        <header className="modal-header">
          <div>
            <span className="eyebrow">Telecom Platform</span>
            <h2>{title}</h2>
          </div>
          <button className="icon-button" onClick={onClose} aria-label="Close modal">
            <Icon name="close" />
          </button>
        </header>
        {children}
      </section>
    </div>
  );
}

function Field({
  label,
  children,
  hint
}: {
  label: string;
  children: ReactNode;
  hint?: string;
}) {
  return (
    <label className="field">
      <span>{label}</span>
      {children}
      {hint && <small>{hint}</small>}
    </label>
  );
}

function TableShell({
  children,
  loading,
  empty,
  emptyText
}: {
  children: ReactNode;
  loading: boolean;
  empty: boolean;
  emptyText: string;
}) {
  if (loading) return <LoadingRows />;
  if (empty) return <EmptyState text={emptyText} />;
  return <div className="table-scroll">{children}</div>;
}

function Login({
  onLogin
}: {
  onLogin: (username: string, password: string) => Promise<void>;
}) {
  const [username, setUsername] = useState("admin");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      await onLogin(username.trim(), password);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Login failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="login-page">
      <section className="login-visual">
        <div className="brand-mark brand-mark-large">
          <span />
          <span />
          <span />
        </div>
        <div className="login-copy">
          <span className="eyebrow light">Enterprise telecom operations</span>
          <h1>One console for your network operations.</h1>
          <p>
            Manage devices and stock, run safe asynchronous workflows, and review every
            notification and audit event from one place.
          </p>
        </div>
        <div className="network-art" aria-hidden="true">
          <span className="node n1" />
          <span className="node n2" />
          <span className="node n3" />
          <span className="node n4" />
          <span className="line l1" />
          <span className="line l2" />
          <span className="line l3" />
        </div>
      </section>

      <section className="login-panel">
        <form className="login-card" onSubmit={submit}>
          <div className="mobile-brand">
            <div className="brand-mark"><span /><span /><span /></div>
            <strong>Telecom Console</strong>
          </div>
          <span className="eyebrow">Protected operations workspace</span>
          <h2>Welcome back</h2>
          <p>Sign in with the API Gateway administrator credentials.</p>

          {error && <div className="form-error">{error}</div>}

          <Field label="Username">
            <input
              autoComplete="username"
              value={username}
              onChange={(event) => setUsername(event.target.value)}
              required
            />
          </Field>
          <Field label="Password">
            <input
              autoComplete="current-password"
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder="Enter your password"
              required
            />
          </Field>
          <Button type="submit" disabled={busy}>
            {busy ? "Signing in…" : "Sign in securely"}
          </Button>
          <small className="login-note">
            Your JWT remains in this browser session and is sent only to the same origin.
          </small>
        </form>
      </section>
    </main>
  );
}

export default function App() {
  const [token, setToken] = useState(() => sessionStorage.getItem(TOKEN_KEY) ?? "");
  const [username, setUsername] = useState(() => sessionStorage.getItem(USER_KEY) ?? "admin");
  const [page, setPage] = useState<Page>("dashboard");
  const [loading, setLoading] = useState(false);
  const [health, setHealth] = useState<Health>({});
  const [devices, setDevices] = useState<Device[]>([]);
  const [inventory, setInventory] = useState<InventoryItem[]>([]);
  const [workflows, setWorkflows] = useState<Workflow[]>([]);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [audit, setAudit] = useState<AuditEvent[]>([]);
  const [toast, setToast] = useState<Toast>(null);
  const [modal, setModal] = useState<null | "device" | "inventory" | "workflow" | "notification">(null);
  const [search, setSearch] = useState("");

  const logout = useCallback(() => {
    sessionStorage.removeItem(TOKEN_KEY);
    sessionStorage.removeItem(USER_KEY);
    setToken("");
    setUsername("admin");
  }, []);

  const request = useCallback(
    async <T,>(path: string, options: RequestInit = {}, authenticated = true): Promise<T> => {
      const headers = new Headers(options.headers);
      if (authenticated && token) headers.set("Authorization", `Bearer ${token}`);
      if (options.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");

      const response = await fetch(path, { ...options, headers });
      const text = await response.text();
      let payload: unknown = null;
      if (text) {
        try {
          payload = JSON.parse(text);
        } catch {
          payload = text;
        }
      }
      if (!response.ok) {
        if (response.status === 401 && authenticated) logout();
        const detail =
          typeof payload === "object" && payload && "detail" in payload
            ? String((payload as { detail: unknown }).detail)
            : `Request failed with HTTP ${response.status}`;
        throw new ApiError(detail, response.status);
      }
      return payload as T;
    },
    [logout, token]
  );

  const showToast = useCallback((kind: "success" | "error", message: string) => {
    setToast({ kind, message });
    window.setTimeout(() => setToast(null), 4000);
  }, []);

  const refresh = useCallback(async () => {
    if (!token) return;
    setLoading(true);
    const results = await Promise.allSettled([
      request<Health>("/health/ready", {}, false),
      request<Device[] | { items: Device[] }>("/api/v1/devices?limit=200"),
      request<InventoryItem[]>("/api/v1/inventory?limit=500"),
      request<Workflow[]>("/api/v1/workflows?limit=500"),
      request<Notification[]>("/api/v1/notifications?limit=500"),
      request<AuditEvent[]>("/api/v1/audit?limit=500")
    ]);

    const failures: string[] = [];
    results.forEach((result, index) => {
      if (result.status === "rejected") {
        failures.push(result.reason instanceof Error ? result.reason.message : `Request ${index + 1} failed`);
        return;
      }
      switch (index) {
        case 0:
          setHealth(result.value as Health);
          break;
        case 1: {
          const value = result.value as Device[] | { items: Device[] };
          setDevices(Array.isArray(value) ? value : value.items ?? []);
          break;
        }
        case 2:
          setInventory(result.value as InventoryItem[]);
          break;
        case 3:
          setWorkflows(result.value as Workflow[]);
          break;
        case 4:
          setNotifications(result.value as Notification[]);
          break;
        case 5:
          setAudit(result.value as AuditEvent[]);
          break;
      }
    });

    if (failures.length) showToast("error", failures[0]);
    setLoading(false);
  }, [request, showToast, token]);

  useEffect(() => {
    void refresh();
    if (!token) return;
    const timer = window.setInterval(() => void refresh(), 30000);
    return () => window.clearInterval(timer);
  }, [refresh, token]);

  async function login(loginUsername: string, password: string) {
    const response = await fetch("/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: loginUsername, password })
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(payload.detail ?? "Invalid username or password");
    }
    const accessToken = payload.access_token as string | undefined;
    if (!accessToken) throw new Error("The gateway did not return an access token");
    sessionStorage.setItem(TOKEN_KEY, accessToken);
    sessionStorage.setItem(USER_KEY, loginUsername);
    setUsername(loginUsername);
    setToken(accessToken);
  }

  async function remove(path: string, label: string) {
    if (!window.confirm(`Delete ${label}? This action cannot be undone.`)) return;
    try {
      await request(path, { method: "DELETE" });
      showToast("success", `${label} deleted`);
      await refresh();
    } catch (reason) {
      showToast("error", reason instanceof Error ? reason.message : "Delete failed");
    }
  }

  async function runWorkflow(id: string) {
    try {
      await request(`/api/v1/workflows/${id}/run`, { method: "POST" });
      showToast("success", "Workflow queued for asynchronous execution");
      await refresh();
    } catch (reason) {
      showToast("error", reason instanceof Error ? reason.message : "Workflow could not be queued");
    }
  }

  const query = search.trim().toLowerCase();
  const filteredDevices = useMemo(
    () => devices.filter((item) => JSON.stringify(item).toLowerCase().includes(query)),
    [devices, query]
  );
  const filteredInventory = useMemo(
    () => inventory.filter((item) => JSON.stringify(item).toLowerCase().includes(query)),
    [inventory, query]
  );
  const filteredWorkflows = useMemo(
    () => workflows.filter((item) => JSON.stringify(item).toLowerCase().includes(query)),
    [workflows, query]
  );
  const filteredNotifications = useMemo(
    () => notifications.filter((item) => JSON.stringify(item).toLowerCase().includes(query)),
    [notifications, query]
  );
  const filteredAudit = useMemo(
    () => audit.filter((item) => JSON.stringify(item).toLowerCase().includes(query)),
    [audit, query]
  );

  const lowStock = inventory.filter((item) => item.quantity <= item.low_stock_threshold).length;
  const activeWorkflows = workflows.filter((item) =>
    ["pending", "queued", "running"].includes(item.state)
  ).length;
  const failedWorkflows = workflows.filter((item) => item.state === "failed").length;
  const healthChecks = health.checks ?? health.services ?? {};
  const healthyServices = Object.values(healthChecks).filter((value) =>
    ["ready", "healthy", "alive"].includes(value)
  ).length;

  if (!token) return <Login onLogin={login} />;

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark"><span /><span /><span /></div>
          <div>
            <strong>Telecom</strong>
            <small>Operations Console</small>
          </div>
        </div>

        <nav>
          {navItems.map((item) => (
            <button
              key={item.page}
              className={page === item.page ? "active" : ""}
              onClick={() => {
                setPage(item.page);
                setSearch("");
              }}
            >
              <span className="nav-icon">{item.icon}</span>
              {item.label}
              {item.page === "notifications" && notifications.length > 0 && (
                <span className="nav-count">{Math.min(notifications.length, 99)}</span>
              )}
            </button>
          ))}
        </nav>

        <div className="sidebar-status">
          <div className={`status-dot ${health.status === "ready" ? "online" : ""}`} />
          <div>
            <strong>Platform {health.status ?? "checking"}</strong>
            <small>{healthyServices}/{Object.keys(healthChecks).length || 6} dependencies ready</small>
          </div>
        </div>
      </aside>

      <div className="main-area">
        <header className="topbar">
          <div>
            <span className="eyebrow">Enterprise service management</span>
            <h1>{navItems.find((item) => item.page === page)?.label}</h1>
          </div>
          <div className="topbar-actions">
            {page !== "dashboard" && (
              <div className="search-box">
                <Icon name="search" />
                <input
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  placeholder={`Search ${page}…`}
                  aria-label={`Search ${page}`}
                />
              </div>
            )}
            <button
              className="icon-button"
              onClick={() => void refresh()}
              disabled={loading}
              title="Refresh all platform data"
            >
              <Icon name="refresh" />
            </button>
            <div className="user-menu">
              <span>{username.slice(0, 1).toUpperCase()}</span>
              <div>
                <strong>{username}</strong>
                <small>Administrator</small>
              </div>
            </div>
            <button className="icon-button" onClick={logout} title="Sign out">
              <Icon name="logout" />
            </button>
          </div>
        </header>

        <main className="content">
          {page === "dashboard" && (
            <>
              <section className="hero-card">
                <div>
                  <span className="eyebrow light">Live platform status</span>
                  <h2>Operate the telecom estate with confidence.</h2>
                  <p>
                    The console is connected through the API Gateway to your Kubernetes
                    microservices, PostgreSQL data, and RabbitMQ event flow.
                  </p>
                </div>
                <div className="hero-health">
                  <div className="pulse-ring"><span /></div>
                  <strong>{health.status ?? "Checking"}</strong>
                  <small>Gateway readiness</small>
                </div>
              </section>

              <section className="metric-grid">
                <article className="metric-card">
                  <span className="metric-icon">◇</span>
                  <div>
                    <small>Managed devices</small>
                    <strong>{devices.length}</strong>
                    <span>{devices.filter((item) => item.status === "active").length} active</span>
                  </div>
                </article>
                <article className="metric-card">
                  <span className="metric-icon">▦</span>
                  <div>
                    <small>Inventory records</small>
                    <strong>{inventory.length}</strong>
                    <span className={lowStock ? "danger-text" : ""}>{lowStock} low stock</span>
                  </div>
                </article>
                <article className="metric-card">
                  <span className="metric-icon">▶</span>
                  <div>
                    <small>Active workflows</small>
                    <strong>{activeWorkflows}</strong>
                    <span className={failedWorkflows ? "danger-text" : ""}>{failedWorkflows} failed</span>
                  </div>
                </article>
                <article className="metric-card">
                  <span className="metric-icon">●</span>
                  <div>
                    <small>Notifications</small>
                    <strong>{notifications.length}</strong>
                    <span>{audit.length} audit events</span>
                  </div>
                </article>
              </section>

              <section className="dashboard-grid">
                <article className="panel">
                  <header className="panel-header">
                    <div>
                      <span className="eyebrow">Dependency map</span>
                      <h3>Service readiness</h3>
                    </div>
                    <Badge value={health.status ?? "checking"} />
                  </header>
                  <div className="service-grid">
                    {Object.entries(healthChecks).length ? (
                      Object.entries(healthChecks).map(([name, state]) => (
                        <div className="service-row" key={name}>
                          <span className={`service-indicator ${statusTone(state)}`} />
                          <div>
                            <strong>{name.replaceAll("-", " ")}</strong>
                            <small>Internal Kubernetes service</small>
                          </div>
                          <Badge value={state} />
                        </div>
                      ))
                    ) : (
                      <EmptyState text="Gateway health information has not arrived yet." />
                    )}
                  </div>
                </article>

                <article className="panel">
                  <header className="panel-header">
                    <div>
                      <span className="eyebrow">Recent activity</span>
                      <h3>Latest platform events</h3>
                    </div>
                    <button className="text-button" onClick={() => setPage("audit")}>View audit</button>
                  </header>
                  <div className="activity-list">
                    {audit.slice(0, 6).map((event) => (
                      <div className="activity-row" key={event.id}>
                        <span className={`activity-dot ${statusTone(event.event_type.includes("failed") ? "failed" : "completed")}`} />
                        <div>
                          <strong>{event.event_type}</strong>
                          <small>{event.source} · {formatDate(event.occurred_at)}</small>
                        </div>
                      </div>
                    ))}
                    {!audit.length && <EmptyState text="Events will appear when services publish domain activity." />}
                  </div>
                </article>
              </section>
            </>
          )}

          {page === "devices" && (
            <section className="panel data-panel">
              <header className="panel-header">
                <div>
                  <span className="eyebrow">Network estate</span>
                  <h3>Managed devices <span className="record-count">{filteredDevices.length}</span></h3>
                </div>
                <Button onClick={() => setModal("device")}><Icon name="plus" /> Add device</Button>
              </header>
              <TableShell loading={loading} empty={!filteredDevices.length} emptyText="Add the first router, switch, OLT, or firewall.">
                <table>
                  <thead><tr><th>Hostname</th><th>Management IP</th><th>Vendor / model</th><th>Site</th><th>Status</th><th>Updated</th><th /></tr></thead>
                  <tbody>
                    {filteredDevices.map((item) => (
                      <tr key={item.id}>
                        <td><strong>{item.hostname}</strong><small className="cell-subtitle">{item.software_version || "Software unknown"}</small></td>
                        <td className="mono">{item.management_ip}</td>
                        <td>{item.vendor}<small className="cell-subtitle">{item.model || "—"}</small></td>
                        <td>{item.site || "—"}</td>
                        <td><Badge value={item.status} /></td>
                        <td>{formatDate(item.updated_at)}</td>
                        <td className="actions-cell">
                          <button className="icon-button danger" onClick={() => void remove(`/api/v1/devices/${item.id}`, item.hostname)} title="Delete device"><Icon name="trash" /></button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </TableShell>
            </section>
          )}

          {page === "inventory" && (
            <section className="panel data-panel">
              <header className="panel-header">
                <div>
                  <span className="eyebrow">Spares and stock</span>
                  <h3>Inventory <span className="record-count">{filteredInventory.length}</span></h3>
                </div>
                <Button onClick={() => setModal("inventory")}><Icon name="plus" /> Add stock item</Button>
              </header>
              <TableShell loading={loading} empty={!filteredInventory.length} emptyText="Add your first spare part or consumable.">
                <table>
                  <thead><tr><th>Item</th><th>Category</th><th>Location</th><th>Quantity</th><th>Threshold</th><th>Health</th><th /></tr></thead>
                  <tbody>
                    {filteredInventory.map((item) => {
                      const low = item.quantity <= item.low_stock_threshold;
                      return (
                        <tr key={item.id}>
                          <td><strong>{item.name}</strong><small className="cell-subtitle">{formatDate(item.updated_at)}</small></td>
                          <td>{item.category}</td>
                          <td>{item.location}</td>
                          <td className="quantity-cell">{item.quantity}</td>
                          <td>{item.low_stock_threshold}</td>
                          <td><Badge value={low ? "low_stock" : "healthy"} /></td>
                          <td className="actions-cell">
                            <button
                              className="icon-button"
                              onClick={async () => {
                                const value = window.prompt("New quantity", String(item.quantity));
                                if (value === null) return;
                                const quantity = Number(value);
                                if (!Number.isInteger(quantity) || quantity < 0) {
                                  showToast("error", "Quantity must be a non-negative whole number");
                                  return;
                                }
                                try {
                                  await request(`/api/v1/inventory/${item.id}`, {
                                    method: "PATCH",
                                    body: JSON.stringify({ quantity })
                                  });
                                  showToast("success", "Inventory quantity updated");
                                  await refresh();
                                } catch (reason) {
                                  showToast("error", reason instanceof Error ? reason.message : "Update failed");
                                }
                              }}
                              title="Update quantity"
                            ><Icon name="edit" /></button>
                            <button className="icon-button danger" onClick={() => void remove(`/api/v1/inventory/${item.id}`, item.name)} title="Delete inventory item"><Icon name="trash" /></button>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </TableShell>
            </section>
          )}

          {page === "workflows" && (
            <section className="panel data-panel">
              <header className="panel-header">
                <div>
                  <span className="eyebrow">Asynchronous operations</span>
                  <h3>Workflows <span className="record-count">{filteredWorkflows.length}</span></h3>
                </div>
                <Button onClick={() => setModal("workflow")}><Icon name="plus" /> Create workflow</Button>
              </header>
              <TableShell loading={loading} empty={!filteredWorkflows.length} emptyText="Create a workflow definition, then queue it for the worker.">
                <table>
                  <thead><tr><th>Name</th><th>Action</th><th>Device</th><th>State</th><th>Created</th><th>Result</th><th /></tr></thead>
                  <tbody>
                    {filteredWorkflows.map((item) => (
                      <tr key={item.id}>
                        <td><strong>{item.name}</strong>{item.error_message && <small className="cell-subtitle danger-text">{item.error_message}</small>}</td>
                        <td className="mono">{item.action}</td>
                        <td className="mono">{item.device_id ? item.device_id.slice(0, 8) + "…" : "Any / none"}</td>
                        <td><Badge value={item.state} /></td>
                        <td>{formatDate(item.created_at)}</td>
                        <td className="result-cell" title={valueText(item.result)}>{item.result ? valueText(item.result).slice(0, 44) : "—"}</td>
                        <td className="actions-cell">
                          <button
                            className="icon-button play"
                            onClick={() => void runWorkflow(item.id)}
                            disabled={!["pending", "failed"].includes(item.state)}
                            title="Queue workflow"
                          ><Icon name="play" /></button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </TableShell>
            </section>
          )}

          {page === "notifications" && (
            <section className="panel data-panel">
              <header className="panel-header">
                <div>
                  <span className="eyebrow">Operations inbox</span>
                  <h3>Notifications <span className="record-count">{filteredNotifications.length}</span></h3>
                </div>
                <Button onClick={() => setModal("notification")}><Icon name="plus" /> New notification</Button>
              </header>
              <div className="card-list">
                {loading && <LoadingRows />}
                {!loading && !filteredNotifications.length && <EmptyState text="Low-stock and workflow events will create notifications automatically." />}
                {!loading && filteredNotifications.map((item) => (
                  <article className="notification-card" key={item.id}>
                    <div className={`notification-symbol ${statusTone(item.source_event_type?.includes("failed") ? "failed" : item.status)}`}>●</div>
                    <div className="notification-content">
                      <div className="notification-title">
                        <div><strong>{item.subject}</strong><small>{item.recipient} · {item.channel}</small></div>
                        <Badge value={item.status} />
                      </div>
                      <p>{item.body}</p>
                      <footer>
                        <span>{item.source_event_type || "manual.notification"}</span>
                        <time>{formatDate(item.created_at)}</time>
                      </footer>
                    </div>
                  </article>
                ))}
              </div>
            </section>
          )}

          {page === "audit" && (
            <section className="panel data-panel">
              <header className="panel-header">
                <div>
                  <span className="eyebrow">Immutable operations history</span>
                  <h3>Audit trail <span className="record-count">{filteredAudit.length}</span></h3>
                </div>
              </header>
              <div className="timeline">
                {loading && <LoadingRows />}
                {!loading && !filteredAudit.length && <EmptyState text="Domain events will be recorded here by the audit consumer." />}
                {!loading && filteredAudit.map((item) => (
                  <article className="timeline-item" key={item.id}>
                    <span className={`timeline-marker ${statusTone(item.event_type.includes("failed") ? "failed" : "completed")}`} />
                    <div className="timeline-card">
                      <header>
                        <div>
                          <strong>{item.event_type}</strong>
                          <small>{item.source}</small>
                        </div>
                        <time>{formatDate(item.occurred_at)}</time>
                      </header>
                      <dl>
                        <div><dt>Event ID</dt><dd className="mono">{item.event_id}</dd></div>
                        <div><dt>Correlation</dt><dd className="mono">{item.correlation_id || "—"}</dd></div>
                      </dl>
                      <details>
                        <summary>View payload</summary>
                        <pre>{JSON.stringify(item.payload, null, 2)}</pre>
                      </details>
                    </div>
                  </article>
                ))}
              </div>
            </section>
          )}
        </main>
      </div>

      {toast && <div className={`toast toast-${toast.kind}`}>{toast.message}</div>}

      {modal === "device" && (
        <DeviceForm
          onClose={() => setModal(null)}
          onSubmit={async (payload) => {
            await request("/api/v1/devices", { method: "POST", body: JSON.stringify(payload) });
            setModal(null);
            showToast("success", "Device created");
            await refresh();
          }}
        />
      )}
      {modal === "inventory" && (
        <InventoryForm
          onClose={() => setModal(null)}
          onSubmit={async (payload) => {
            await request("/api/v1/inventory", { method: "POST", body: JSON.stringify(payload) });
            setModal(null);
            showToast("success", "Inventory item created");
            await refresh();
          }}
        />
      )}
      {modal === "workflow" && (
        <WorkflowForm
          devices={devices}
          onClose={() => setModal(null)}
          onSubmit={async (payload) => {
            await request("/api/v1/workflows", { method: "POST", body: JSON.stringify(payload) });
            setModal(null);
            showToast("success", "Workflow definition created");
            await refresh();
          }}
        />
      )}
      {modal === "notification" && (
        <NotificationForm
          onClose={() => setModal(null)}
          onSubmit={async (payload) => {
            await request("/api/v1/notifications", { method: "POST", body: JSON.stringify(payload) });
            setModal(null);
            showToast("success", "Notification created");
            await refresh();
          }}
        />
      )}
    </div>
  );
}

function DeviceForm({
  onClose,
  onSubmit
}: {
  onClose: () => void;
  onSubmit: (payload: Json) => Promise<void>;
}) {
  const [form, setForm] = useState({
    hostname: "",
    management_ip: "",
    vendor: "nokia",
    model: "",
    site: "",
    software_version: "",
    status: "active"
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      await onSubmit(form);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Device could not be created");
      setBusy(false);
    }
  }

  return (
    <Modal title="Add managed device" onClose={onClose}>
      <form className="modal-form" onSubmit={submit}>
        {error && <div className="form-error">{error}</div>}
        <div className="form-grid">
          <Field label="Hostname"><input value={form.hostname} onChange={(e) => setForm({ ...form, hostname: e.target.value })} required placeholder="cairo-core-01" /></Field>
          <Field label="Management IP"><input value={form.management_ip} onChange={(e) => setForm({ ...form, management_ip: e.target.value })} required placeholder="10.10.0.11" /></Field>
          <Field label="Vendor">
            <select value={form.vendor} onChange={(e) => setForm({ ...form, vendor: e.target.value })}>
              {["nokia", "cisco", "juniper", "huawei", "arista", "other"].map((value) => <option key={value}>{value}</option>)}
            </select>
          </Field>
          <Field label="Model"><input value={form.model} onChange={(e) => setForm({ ...form, model: e.target.value })} placeholder="7750 SR-1" /></Field>
          <Field label="Site"><input value={form.site} onChange={(e) => setForm({ ...form, site: e.target.value })} placeholder="Cairo POP" /></Field>
          <Field label="Software version"><input value={form.software_version} onChange={(e) => setForm({ ...form, software_version: e.target.value })} placeholder="24.7.R1" /></Field>
          <Field label="Status">
            <select value={form.status} onChange={(e) => setForm({ ...form, status: e.target.value })}>
              {["active", "inactive", "maintenance", "unreachable", "unknown"].map((value) => <option key={value}>{value}</option>)}
            </select>
          </Field>
        </div>
        <div className="modal-actions"><Button variant="secondary" onClick={onClose}>Cancel</Button><Button type="submit" disabled={busy}>{busy ? "Creating…" : "Create device"}</Button></div>
      </form>
    </Modal>
  );
}

function InventoryForm({
  onClose,
  onSubmit
}: {
  onClose: () => void;
  onSubmit: (payload: Json) => Promise<void>;
}) {
  const [form, setForm] = useState({
    name: "",
    category: "optic",
    quantity: 0,
    low_stock_threshold: 5,
    location: ""
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      await onSubmit(form);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Inventory item could not be created");
      setBusy(false);
    }
  }

  return (
    <Modal title="Add inventory item" onClose={onClose}>
      <form className="modal-form" onSubmit={submit}>
        {error && <div className="form-error">{error}</div>}
        <div className="form-grid">
          <Field label="Item name"><input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required placeholder="Nokia 100G SFP" /></Field>
          <Field label="Category"><input value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })} required placeholder="optic" /></Field>
          <Field label="Quantity"><input type="number" min="0" value={form.quantity} onChange={(e) => setForm({ ...form, quantity: Number(e.target.value) })} required /></Field>
          <Field label="Low-stock threshold"><input type="number" min="0" value={form.low_stock_threshold} onChange={(e) => setForm({ ...form, low_stock_threshold: Number(e.target.value) })} required /></Field>
          <Field label="Location"><input value={form.location} onChange={(e) => setForm({ ...form, location: e.target.value })} required placeholder="Cairo Warehouse" /></Field>
        </div>
        <div className="modal-actions"><Button variant="secondary" onClick={onClose}>Cancel</Button><Button type="submit" disabled={busy}>{busy ? "Creating…" : "Create item"}</Button></div>
      </form>
    </Modal>
  );
}

function WorkflowForm({
  devices,
  onClose,
  onSubmit
}: {
  devices: Device[];
  onClose: () => void;
  onSubmit: (payload: Json) => Promise<void>;
}) {
  const [form, setForm] = useState({
    name: "",
    device_id: "",
    action: "backup_config",
    parameters: '{\n  "destination": "gcs",\n  "format": "md-cli"\n}'
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      const parameters = JSON.parse(form.parameters) as Json;
      await onSubmit({
        name: form.name,
        device_id: form.device_id || null,
        action: form.action,
        parameters
      });
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Workflow could not be created");
      setBusy(false);
    }
  }

  return (
    <Modal title="Create workflow" onClose={onClose}>
      <form className="modal-form" onSubmit={submit}>
        {error && <div className="form-error">{error}</div>}
        <div className="form-grid">
          <Field label="Workflow name"><input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required placeholder="Backup Cairo core router" /></Field>
          <Field label="Target device">
            <select value={form.device_id} onChange={(e) => setForm({ ...form, device_id: e.target.value })}>
              <option value="">No specific device</option>
              {devices.map((item) => <option key={item.id} value={item.id}>{item.hostname}</option>)}
            </select>
          </Field>
          <Field label="Action"><input value={form.action} onChange={(e) => setForm({ ...form, action: e.target.value })} required placeholder="backup_config" /></Field>
          <Field label="Parameters (JSON)" hint="The worker currently performs safe mock execution only.">
            <textarea rows={7} value={form.parameters} onChange={(e) => setForm({ ...form, parameters: e.target.value })} required />
          </Field>
        </div>
        <div className="modal-actions"><Button variant="secondary" onClick={onClose}>Cancel</Button><Button type="submit" disabled={busy}>{busy ? "Creating…" : "Create workflow"}</Button></div>
      </form>
    </Modal>
  );
}

function NotificationForm({
  onClose,
  onSubmit
}: {
  onClose: () => void;
  onSubmit: (payload: Json) => Promise<void>;
}) {
  const [form, setForm] = useState({
    channel: "console",
    recipient: "operations",
    subject: "",
    body: ""
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      await onSubmit(form);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Notification could not be created");
      setBusy(false);
    }
  }

  return (
    <Modal title="Create notification" onClose={onClose}>
      <form className="modal-form" onSubmit={submit}>
        {error && <div className="form-error">{error}</div>}
        <div className="form-grid">
          <Field label="Channel"><input value={form.channel} onChange={(e) => setForm({ ...form, channel: e.target.value })} required /></Field>
          <Field label="Recipient"><input value={form.recipient} onChange={(e) => setForm({ ...form, recipient: e.target.value })} required /></Field>
          <Field label="Subject"><input value={form.subject} onChange={(e) => setForm({ ...form, subject: e.target.value })} required /></Field>
          <Field label="Message"><textarea rows={6} value={form.body} onChange={(e) => setForm({ ...form, body: e.target.value })} required /></Field>
        </div>
        <div className="modal-actions"><Button variant="secondary" onClick={onClose}>Cancel</Button><Button type="submit" disabled={busy}>{busy ? "Sending…" : "Create notification"}</Button></div>
      </form>
    </Modal>
  );
}
EOF

write_file "$FRONTEND_DIR/src/styles.css" <<'EOF'
:root {
  font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  color: #172033;
  background: #f3f6fa;
  font-synthesis: none;
  text-rendering: optimizeLegibility;
  --navy: #08111f;
  --navy-2: #0d1d32;
  --blue: #1d65e8;
  --cyan: #30c7d9;
  --ink: #172033;
  --muted: #6f7c91;
  --line: #e2e8f0;
  --surface: #ffffff;
  --surface-soft: #f7f9fc;
  --positive: #118a62;
  --warning: #b66a07;
  --negative: #c83d4c;
  --shadow: 0 18px 45px rgba(28, 42, 67, 0.09);
}

* { box-sizing: border-box; }
html { min-width: 320px; background: #f3f6fa; }
body { margin: 0; min-width: 320px; min-height: 100vh; }
button, input, select, textarea { font: inherit; }
button { cursor: pointer; }
button:disabled { cursor: not-allowed; opacity: .55; }
h1, h2, h3, p { margin-top: 0; }
h1, h2, h3, strong { font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
input, select, textarea {
  width: 100%;
  border: 1px solid #d7dfeb;
  background: #fff;
  color: var(--ink);
  border-radius: 11px;
  padding: 11px 13px;
  outline: none;
  transition: border-color .18s, box-shadow .18s;
}
input:focus, select:focus, textarea:focus {
  border-color: #77a8f4;
  box-shadow: 0 0 0 3px rgba(29, 101, 232, .12);
}
textarea { resize: vertical; }
.mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: .85rem; }
.eyebrow {
  display: block;
  margin-bottom: 7px;
  color: #6a7890;
  font-size: .7rem;
  font-weight: 800;
  letter-spacing: .13em;
  text-transform: uppercase;
}
.eyebrow.light { color: #75dbe8; }

.login-page { min-height: 100vh; display: grid; grid-template-columns: minmax(0, 1.25fr) minmax(390px, .75fr); }
.login-visual {
  position: relative;
  overflow: hidden;
  display: flex;
  align-items: center;
  padding: clamp(48px, 8vw, 118px);
  color: #fff;
  background:
    radial-gradient(circle at 75% 30%, rgba(48, 199, 217, .18), transparent 29%),
    radial-gradient(circle at 16% 80%, rgba(29, 101, 232, .26), transparent 35%),
    linear-gradient(145deg, #08111f 0%, #0b1e35 62%, #0e2f45 100%);
}
.login-copy { position: relative; z-index: 2; max-width: 690px; }
.login-copy h1 { margin: 0 0 24px; font-size: clamp(2.75rem, 5vw, 5.4rem); line-height: .99; letter-spacing: -.055em; }
.login-copy p { max-width: 610px; margin: 0; color: #bbcadb; font-size: 1.12rem; line-height: 1.7; }
.login-panel { display: grid; place-items: center; padding: 40px; background: #f8fafc; }
.login-card { width: min(430px, 100%); }
.login-card h2 { margin-bottom: 8px; font-size: 2.25rem; letter-spacing: -.035em; }
.login-card > p { color: var(--muted); margin-bottom: 29px; line-height: 1.6; }
.login-card .field { margin-bottom: 17px; }
.login-card .button { width: 100%; margin-top: 8px; justify-content: center; padding: 13px; }
.login-note { display: block; margin-top: 17px; color: #8390a4; line-height: 1.5; text-align: center; }
.mobile-brand { display: none; align-items: center; gap: 12px; margin-bottom: 35px; }
.brand-mark { display: flex; align-items: flex-end; gap: 3px; width: 34px; height: 34px; padding: 7px; border-radius: 10px; background: linear-gradient(145deg, #2376ee, #1fc0d2); box-shadow: 0 8px 22px rgba(29, 101, 232, .28); }
.brand-mark span { display: block; flex: 1; border-radius: 2px; background: #fff; }
.brand-mark span:nth-child(1) { height: 35%; opacity: .75; }
.brand-mark span:nth-child(2) { height: 70%; opacity: .9; }
.brand-mark span:nth-child(3) { height: 100%; }
.brand-mark-large { position: absolute; left: clamp(48px, 8vw, 118px); top: clamp(36px, 6vw, 78px); width: 48px; height: 48px; }
.network-art { position: absolute; right: -60px; bottom: -40px; width: 540px; height: 460px; opacity: .42; }
.node { position: absolute; width: 17px; height: 17px; border: 3px solid #5ee4f0; border-radius: 50%; box-shadow: 0 0 30px #30c7d9; }
.n1 { left: 80px; top: 80px; }.n2 { right: 90px; top: 50px; }.n3 { left: 220px; bottom: 80px; }.n4 { right: 40px; bottom: 150px; }
.line { position: absolute; height: 1px; transform-origin: left; background: linear-gradient(90deg, #30c7d9, transparent); }
.l1 { left: 96px; top: 89px; width: 315px; transform: rotate(-6deg); }
.l2 { left: 92px; top: 96px; width: 292px; transform: rotate(47deg); }
.l3 { left: 230px; bottom: 90px; width: 245px; transform: rotate(-28deg); }

.app-shell { min-height: 100vh; display: grid; grid-template-columns: 252px minmax(0, 1fr); }
.sidebar {
  position: sticky; top: 0; height: 100vh; z-index: 10;
  display: flex; flex-direction: column;
  padding: 25px 17px;
  color: #c3d0df;
  background: linear-gradient(180deg, #08111f, #0b1a2c 70%, #0a2230);
}
.brand { display: flex; align-items: center; gap: 12px; padding: 0 8px 28px; color: #fff; }
.brand > div:last-child { display: flex; flex-direction: column; }
.brand strong { font-size: 1.05rem; }
.brand small { color: #8295aa; font-size: .72rem; }
.sidebar nav { display: flex; flex-direction: column; gap: 4px; }
.sidebar nav button {
  display: flex; align-items: center; gap: 12px;
  width: 100%; border: 0; border-radius: 11px;
  padding: 11px 12px;
  color: #91a4b8; background: transparent;
  text-align: left; font-size: .91rem; font-weight: 600;
  transition: color .18s, background .18s, transform .18s;
}
.sidebar nav button:hover { color: #fff; background: rgba(255,255,255,.06); transform: translateX(2px); }
.sidebar nav button.active { color: #fff; background: linear-gradient(100deg, rgba(29,101,232,.32), rgba(48,199,217,.09)); box-shadow: inset 3px 0 #3bc9da; }
.nav-icon { display: grid; place-items: center; width: 22px; height: 22px; color: #4fcddd; font-size: 1.05rem; }
.nav-count { margin-left: auto; border-radius: 999px; padding: 2px 7px; color: #cfeef3; background: rgba(48,199,217,.15); font-size: .68rem; }
.sidebar-status { display: flex; align-items: center; gap: 10px; margin-top: auto; padding: 15px 11px; border-top: 1px solid rgba(255,255,255,.08); }
.sidebar-status > div:last-child { display: flex; flex-direction: column; min-width: 0; }
.sidebar-status strong { color: #dfe8f1; font-size: .76rem; text-transform: capitalize; }
.sidebar-status small { overflow: hidden; color: #72879b; font-size: .67rem; text-overflow: ellipsis; white-space: nowrap; }
.status-dot { width: 9px; height: 9px; border-radius: 50%; background: #d07044; box-shadow: 0 0 0 4px rgba(208,112,68,.12); }
.status-dot.online { background: #27c58b; box-shadow: 0 0 0 4px rgba(39,197,139,.12); }

.main-area { min-width: 0; }
.topbar {
  position: sticky; top: 0; z-index: 8;
  display: flex; align-items: center; justify-content: space-between; gap: 24px;
  min-height: 91px; padding: 17px 30px;
  border-bottom: 1px solid rgba(218,226,237,.85);
  background: rgba(248,250,252,.91); backdrop-filter: blur(16px);
}
.topbar h1 { margin: 0; font-size: 1.6rem; letter-spacing: -.035em; }
.topbar .eyebrow { margin-bottom: 3px; }
.topbar-actions { display: flex; align-items: center; gap: 10px; }
.search-box { display: flex; align-items: center; gap: 8px; width: min(300px, 26vw); border: 1px solid #dce3ed; border-radius: 11px; padding: 0 12px; color: #8794a8; background: #fff; }
.search-box input { border: 0; box-shadow: none; padding: 10px 0; background: transparent; }
.user-menu { display: flex; align-items: center; gap: 9px; margin-left: 4px; padding: 5px 10px 5px 5px; }
.user-menu > span { display: grid; place-items: center; width: 34px; height: 34px; border-radius: 10px; color: #fff; background: linear-gradient(145deg, #172f51, #1d65e8); font-weight: 800; }
.user-menu > div { display: flex; flex-direction: column; }
.user-menu strong { font-size: .8rem; }
.user-menu small { color: #8995a6; font-size: .68rem; }

.content { padding: 29px; }
.hero-card {
  position: relative; overflow: hidden;
  display: flex; align-items: center; justify-content: space-between; gap: 35px;
  min-height: 215px; padding: 34px 39px;
  border-radius: 20px; color: #fff;
  background:
    radial-gradient(circle at 78% 40%, rgba(48,199,217,.25), transparent 28%),
    linear-gradient(125deg, #0a1628, #12345d 73%, #115665);
  box-shadow: var(--shadow);
}
.hero-card::after { content: ""; position: absolute; right: -60px; top: -110px; width: 330px; height: 330px; border: 1px solid rgba(255,255,255,.12); border-radius: 50%; box-shadow: 0 0 0 50px rgba(255,255,255,.025), 0 0 0 100px rgba(255,255,255,.018); }
.hero-card > div:first-child { position: relative; z-index: 2; max-width: 760px; }
.hero-card h2 { margin-bottom: 13px; font-size: clamp(1.7rem, 3vw, 2.75rem); letter-spacing: -.045em; }
.hero-card p { max-width: 710px; margin: 0; color: #bdcede; line-height: 1.65; }
.hero-health { position: relative; z-index: 2; display: flex; align-items: center; flex-direction: column; min-width: 155px; text-transform: capitalize; }
.hero-health strong { margin-top: 10px; font-size: 1.12rem; }
.hero-health small { color: #8faec4; }
.pulse-ring { display: grid; place-items: center; width: 74px; height: 74px; border: 1px solid rgba(86,225,236,.4); border-radius: 50%; box-shadow: 0 0 0 10px rgba(48,199,217,.06), 0 0 35px rgba(48,199,217,.28); }
.pulse-ring span { width: 16px; height: 16px; border-radius: 50%; background: #4be1c0; box-shadow: 0 0 20px #4be1c0; }

.metric-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 16px; margin-top: 18px; }
.metric-card { display: flex; align-items: center; gap: 17px; min-height: 128px; padding: 20px; border: 1px solid #e6ebf2; border-radius: 16px; background: var(--surface); box-shadow: 0 10px 28px rgba(39,52,76,.055); }
.metric-icon { display: grid; place-items: center; flex: 0 0 45px; height: 45px; border-radius: 13px; color: #1d65e8; background: #edf4ff; font-size: 1.2rem; font-weight: 800; }
.metric-card > div { display: flex; flex-direction: column; }
.metric-card small { color: var(--muted); font-size: .73rem; }
.metric-card strong { margin: 2px 0; font-size: 1.8rem; letter-spacing: -.04em; }
.metric-card span:last-child { color: #8793a4; font-size: .72rem; }

.dashboard-grid { display: grid; grid-template-columns: minmax(0, 1.15fr) minmax(350px, .85fr); gap: 18px; margin-top: 18px; }
.panel { border: 1px solid #e4eaf2; border-radius: 17px; background: #fff; box-shadow: 0 10px 30px rgba(28,42,67,.055); }
.panel-header { display: flex; align-items: center; justify-content: space-between; gap: 18px; padding: 22px 23px; border-bottom: 1px solid #edf0f5; }
.panel-header h3 { margin: 0; font-size: 1.07rem; letter-spacing: -.025em; }
.panel-header .eyebrow { margin-bottom: 3px; }
.record-count { display: inline-grid; place-items: center; min-width: 25px; height: 22px; margin-left: 6px; border-radius: 7px; color: #52709c; background: #edf3fb; font-family: Inter, ui-sans-serif, system-ui, sans-serif; font-size: .71rem; }
.service-grid { padding: 5px 20px 17px; }
.service-row { display: flex; align-items: center; gap: 12px; padding: 13px 2px; border-bottom: 1px solid #eef2f6; }
.service-row:last-child { border: 0; }
.service-row > div { display: flex; flex: 1; flex-direction: column; min-width: 0; }
.service-row strong { text-transform: capitalize; font-size: .84rem; }
.service-row small { color: #8a96a6; font-size: .69rem; }
.service-indicator { width: 9px; height: 9px; border-radius: 50%; background: #8d98a8; }
.service-indicator.positive { background: var(--positive); box-shadow: 0 0 0 4px rgba(17,138,98,.1); }
.service-indicator.warning { background: var(--warning); }
.service-indicator.negative { background: var(--negative); }
.activity-list { padding: 10px 21px 20px; }
.activity-row { display: flex; align-items: center; gap: 12px; padding: 11px 0; border-bottom: 1px solid #eef2f6; }
.activity-row:last-child { border: 0; }
.activity-row > div { display: flex; flex-direction: column; min-width: 0; }
.activity-row strong { overflow: hidden; font-size: .8rem; text-overflow: ellipsis; white-space: nowrap; }
.activity-row small { color: #8995a6; font-size: .69rem; }
.activity-dot { width: 9px; height: 9px; border-radius: 50%; background: #8491a3; }
.activity-dot.positive { background: var(--positive); }
.activity-dot.negative { background: var(--negative); }
.text-button { border: 0; color: #1d65e8; background: transparent; font-size: .75rem; font-weight: 700; }

.data-panel { min-height: calc(100vh - 150px); }
.table-scroll { overflow-x: auto; }
table { width: 100%; border-collapse: collapse; }
th { padding: 12px 18px; color: #7d899b; background: #f8fafc; font-size: .68rem; letter-spacing: .07em; text-align: left; text-transform: uppercase; white-space: nowrap; }
td { padding: 14px 18px; border-top: 1px solid #edf1f5; color: #455267; font-size: .82rem; vertical-align: middle; }
tbody tr { transition: background .15s; }
tbody tr:hover { background: #fbfcfe; }
td strong { color: #1e293b; font-size: .81rem; }
.cell-subtitle { display: block; max-width: 260px; margin-top: 3px; overflow: hidden; color: #8c98a9; font-size: .68rem; text-overflow: ellipsis; white-space: nowrap; }
.actions-cell { display: flex; justify-content: flex-end; gap: 5px; }
.quantity-cell { color: #172033; font-family: "Manrope"; font-size: 1rem; font-weight: 800; }
.result-cell { max-width: 210px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

.button { display: inline-flex; align-items: center; gap: 7px; border: 1px solid transparent; border-radius: 10px; padding: 9px 13px; font-size: .78rem; font-weight: 800; transition: transform .15s, box-shadow .15s, background .15s; }
.button:hover:not(:disabled) { transform: translateY(-1px); }
.button-primary { color: #fff; background: linear-gradient(120deg, #1d65e8, #1554c5); box-shadow: 0 8px 18px rgba(29,101,232,.2); }
.button-secondary { color: #4e5b70; border-color: #dce3ec; background: #fff; box-shadow: none; }
.button-danger { color: #fff; background: var(--negative); }
.button-ghost { color: #4f5d72; background: transparent; }
.icon-button { display: inline-grid; place-items: center; flex: 0 0 auto; width: 37px; height: 37px; border: 1px solid #dce3ec; border-radius: 10px; color: #5e6b7e; background: #fff; transition: color .15s, border-color .15s, background .15s; }
.icon-button:hover:not(:disabled) { color: #1d65e8; border-color: #a9c7f6; background: #f4f8ff; }
.icon-button.danger:hover { color: var(--negative); border-color: #f0bec4; background: #fff5f6; }
.icon-button.play { color: #118a62; }
.badge { display: inline-flex; align-items: center; justify-content: center; width: max-content; border-radius: 999px; padding: 4px 8px; font-size: .64rem; font-weight: 800; text-transform: capitalize; white-space: nowrap; }
.badge-positive { color: #08704e; background: #e5f7ef; }
.badge-warning { color: #925306; background: #fff3da; }
.badge-negative { color: #ab2c3a; background: #ffe8eb; }
.badge-neutral { color: #5f6c80; background: #edf1f5; }
.danger-text { color: var(--negative) !important; }

.card-list { display: grid; gap: 12px; padding: 18px; }
.notification-card { display: flex; gap: 14px; padding: 17px; border: 1px solid #e8edf3; border-radius: 14px; background: #fff; transition: transform .15s, box-shadow .15s; }
.notification-card:hover { transform: translateY(-1px); box-shadow: 0 10px 23px rgba(36,50,75,.07); }
.notification-symbol { display: grid; place-items: center; flex: 0 0 37px; height: 37px; border-radius: 11px; color: #758398; background: #eff2f6; font-size: .68rem; }
.notification-symbol.positive { color: #118a62; background: #e7f8f1; }
.notification-symbol.negative { color: #c83d4c; background: #ffeaed; }
.notification-content { flex: 1; min-width: 0; }
.notification-title { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; }
.notification-title > div { display: flex; flex-direction: column; }
.notification-title strong { font-size: .9rem; }
.notification-title small { margin-top: 2px; color: #8a96a7; font-size: .69rem; }
.notification-card p { margin: 11px 0; color: #59667a; font-size: .81rem; line-height: 1.55; }
.notification-card footer { display: flex; justify-content: space-between; gap: 15px; color: #94a0af; font-size: .66rem; }

.timeline { position: relative; padding: 23px 25px 30px 51px; }
.timeline::before { content: ""; position: absolute; left: 31px; top: 31px; bottom: 31px; width: 1px; background: #dfe6ef; }
.timeline-item { position: relative; margin-bottom: 15px; }
.timeline-marker { position: absolute; left: -26px; top: 22px; z-index: 2; width: 11px; height: 11px; border: 2px solid #fff; border-radius: 50%; background: #8290a2; box-shadow: 0 0 0 3px #dfe6ef; }
.timeline-marker.positive { background: var(--positive); box-shadow: 0 0 0 3px #cdeee2; }
.timeline-marker.negative { background: var(--negative); box-shadow: 0 0 0 3px #f7d5da; }
.timeline-card { padding: 17px 19px; border: 1px solid #e6ebf2; border-radius: 13px; background: #fff; }
.timeline-card header { display: flex; justify-content: space-between; gap: 16px; }
.timeline-card header > div { display: flex; flex-direction: column; }
.timeline-card header strong { font-size: .85rem; }
.timeline-card header small, .timeline-card time { color: #8b97a7; font-size: .68rem; }
.timeline-card dl { display: grid; grid-template-columns: 1fr 1fr; gap: 9px; margin: 14px 0 0; }
.timeline-card dl div { min-width: 0; }
.timeline-card dt { color: #8d99a9; font-size: .63rem; text-transform: uppercase; }
.timeline-card dd { margin: 3px 0 0; overflow: hidden; color: #5a687c; text-overflow: ellipsis; white-space: nowrap; }
details { margin-top: 12px; }
summary { color: #1d65e8; cursor: pointer; font-size: .72rem; font-weight: 700; }
pre { overflow: auto; max-height: 280px; padding: 13px; border-radius: 9px; color: #dbe8f4; background: #0c1827; font-size: .68rem; line-height: 1.5; }

.modal-backdrop { position: fixed; inset: 0; z-index: 50; display: grid; place-items: center; padding: 24px; background: rgba(5,13,24,.58); backdrop-filter: blur(6px); }
.modal { width: min(690px, 100%); max-height: min(90vh, 850px); overflow: auto; border-radius: 18px; background: #fff; box-shadow: 0 30px 100px rgba(2,9,18,.35); }
.modal-header { position: sticky; top: 0; z-index: 2; display: flex; align-items: center; justify-content: space-between; padding: 20px 22px; border-bottom: 1px solid #e8edf3; background: rgba(255,255,255,.96); backdrop-filter: blur(12px); }
.modal-header h2 { margin: 0; font-size: 1.3rem; letter-spacing: -.03em; }
.modal-form { padding: 22px; }
.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.field { display: flex; flex-direction: column; gap: 7px; }
.field > span { color: #536075; font-size: .74rem; font-weight: 800; }
.field small { color: #8b97a8; line-height: 1.45; }
.field:has(textarea) { grid-column: 1 / -1; }
.modal-actions { display: flex; justify-content: flex-end; gap: 9px; margin-top: 24px; padding-top: 18px; border-top: 1px solid #edf1f5; }
.form-error { margin-bottom: 16px; border: 1px solid #f2c4ca; border-radius: 10px; padding: 10px 12px; color: #a72f3d; background: #fff1f3; font-size: .78rem; }

.empty-state { display: flex; align-items: center; flex-direction: column; justify-content: center; min-height: 210px; padding: 30px; color: #8995a6; text-align: center; }
.empty-state strong { margin-bottom: 5px; color: #5c687a; }
.empty-state span { max-width: 430px; font-size: .78rem; line-height: 1.5; }
.empty-symbol { display: grid; place-items: center; width: 48px; height: 48px; margin-bottom: 12px; border-radius: 15px; color: #6e83a0; background: #edf2f7; font-size: 1.5rem; }
.loading-list { padding: 20px; }
.skeleton-row { height: 54px; margin-bottom: 10px; border-radius: 10px; background: linear-gradient(90deg, #f1f4f8 25%, #e8edf3 50%, #f1f4f8 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
@keyframes shimmer { to { background-position: -200% 0; } }

.toast { position: fixed; right: 24px; bottom: 24px; z-index: 100; max-width: min(420px, calc(100vw - 48px)); border-radius: 12px; padding: 13px 16px; color: #fff; box-shadow: 0 16px 40px rgba(18,31,50,.24); font-size: .82rem; font-weight: 700; animation: toast-in .2s ease-out; }
.toast-success { background: #087b58; }
.toast-error { background: #b83242; }
@keyframes toast-in { from { transform: translateY(12px); opacity: 0; } }

@media (max-width: 1120px) {
  .metric-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .dashboard-grid { grid-template-columns: 1fr; }
  .search-box { width: 220px; }
}
@media (max-width: 820px) {
  .login-page { grid-template-columns: 1fr; }
  .login-visual { display: none; }
  .login-panel { min-height: 100vh; padding: 28px; }
  .mobile-brand { display: flex; }
  .app-shell { grid-template-columns: 1fr; }
  .sidebar { position: sticky; width: 100%; height: auto; padding: 11px 14px; }
  .brand { padding: 0 4px 10px; }
  .sidebar nav { flex-direction: row; overflow-x: auto; padding-bottom: 3px; }
  .sidebar nav button { flex: 0 0 auto; width: auto; padding: 9px 11px; }
  .sidebar-status { display: none; }
  .topbar { top: 109px; min-height: 77px; padding: 13px 18px; }
  .topbar-actions .user-menu, .search-box { display: none; }
  .content { padding: 18px; }
  .hero-card { padding: 27px; }
  .hero-health { display: none; }
}
@media (max-width: 620px) {
  .metric-grid { grid-template-columns: 1fr; }
  .metric-card { min-height: 105px; }
  .form-grid { grid-template-columns: 1fr; }
  .field:has(textarea) { grid-column: auto; }
  .panel-header { align-items: flex-start; flex-direction: column; }
  .panel-header .button { width: 100%; justify-content: center; }
  .timeline { padding-left: 42px; }
  .timeline::before { left: 24px; }
  .timeline-marker { left: -23px; }
  .timeline-card dl { grid-template-columns: 1fr; }
  .notification-title, .notification-card footer { flex-direction: column; }
}
EOF

write_file "$FRONTEND_DIR/nginx/default.conf.template" <<'EOF'
server {
    listen 8080;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    server_tokens off;
    charset utf-8;

    location = /frontend-health {
        access_log off;
        add_header Content-Type text/plain;
        return 200 "ok\n";
    }

    location /assets/ {
        try_files $uri =404;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    location /auth/ {
        proxy_pass http://${API_GATEWAY_UPSTREAM};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
    }

    location /api/ {
        proxy_pass http://${API_GATEWAY_UPSTREAM};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 60s;
    }

    location /health/ {
        proxy_pass http://${API_GATEWAY_UPSTREAM};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_connect_timeout 5s;
        proxy_read_timeout 15s;
    }

    location / {
        try_files $uri $uri/ /index.html;
        add_header Cache-Control "no-cache";
    }

    add_header Content-Security-Policy "default-src 'self'; connect-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; font-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
}
EOF

write_file "$FRONTEND_DIR/Dockerfile" <<'EOF'
FROM node:22-alpine AS build

WORKDIR /app
COPY package.json ./
RUN npm install --no-audit --no-fund

COPY tsconfig.json tsconfig.app.json tsconfig.node.json vite.config.ts index.html ./
COPY src ./src
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.27-alpine

ENV API_GATEWAY_UPSTREAM=api-gateway:8080

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=4s --start-period=8s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/frontend-health || exit 1
EOF

write_file "$FRONTEND_DIR/.dockerignore" <<'EOF'
.git
node_modules
dist
npm-debug.log
.env*
*.md
EOF

write_file "$FRONTEND_DIR/README.md" <<EOF
# Telecom Operations Frontend

A production-built React/TypeScript single-page application served by unprivileged
Nginx. Nginx proxies browser calls to the API Gateway, keeping the microservices
private and avoiding browser CORS configuration.

## Local development

\`\`\`bash
npm install
npm run dev
\`\`\`

The Vite development proxy expects the gateway at \`http://localhost:8080\`.

## Container

\`\`\`bash
docker build -t telecom-frontend .
docker run --rm -p 3000:8080 \\
  -e API_GATEWAY_UPSTREAM=host.docker.internal:8080 \\
  telecom-frontend
\`\`\`

## Kubernetes image

\`\`\`text
$IMAGE
\`\`\`
EOF

write_file "$ROOT/docker-compose.frontend.yml" <<'EOF'
services:
  frontend:
    build:
      context: ./services/frontend
    ports:
      - "${FRONTEND_PORT:-3000}:8080"
    environment:
      API_GATEWAY_UPSTREAM: api-gateway:8080
    depends_on:
      - api-gateway
    restart: unless-stopped
EOF

# ----------------------------------------------------------------------------
# Kubernetes manifests
# ----------------------------------------------------------------------------

write_file "$K8S_DIR/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $FRONTEND_NAME
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: $FRONTEND_NAME
    app.kubernetes.io/component: web
    app.kubernetes.io/part-of: telecom-platform
spec:
  replicas: $REPLICAS
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: $FRONTEND_NAME
  template:
    metadata:
      labels:
        app.kubernetes.io/name: $FRONTEND_NAME
        app.kubernetes.io/component: web
        app.kubernetes.io/part-of: telecom-platform
    spec:
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: 20
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                topologyKey: kubernetes.io/hostname
                labelSelector:
                  matchLabels:
                    app.kubernetes.io/name: $FRONTEND_NAME
      containers:
        - name: $FRONTEND_NAME
          image: $IMAGE
          imagePullPolicy: IfNotPresent
          env:
            - name: API_GATEWAY_UPSTREAM
              value: api-gateway.$NAMESPACE.svc.cluster.local:80
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          startupProbe:
            httpGet:
              path: /frontend-health
              port: http
            periodSeconds: 2
            timeoutSeconds: 2
            failureThreshold: 30
          readinessProbe:
            httpGet:
              path: /frontend-health
              port: http
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /frontend-health
              port: http
            periodSeconds: 15
            timeoutSeconds: 2
            failureThreshold: 3
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 300m
              memory: 192Mi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: nginx-cache
              mountPath: /var/cache/nginx
            - name: nginx-run
              mountPath: /var/run
            - name: nginx-conf
              mountPath: /etc/nginx/conf.d
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: nginx-cache
          emptyDir: {}
        - name: nginx-run
          emptyDir: {}
        - name: nginx-conf
          emptyDir: {}
        - name: tmp
          emptyDir: {}
EOF


write_file "$K8S_DIR/backend-config.yaml" <<EOF
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: frontend-backend-config
  namespace: $NAMESPACE
spec:
  healthCheck:
    type: HTTP
    requestPath: /frontend-health
    port: 8080
    checkIntervalSec: 10
    timeoutSec: 5
    healthyThreshold: 1
    unhealthyThreshold: 3
EOF

write_file "$K8S_DIR/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: $FRONTEND_NAME
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: $FRONTEND_NAME
    app.kubernetes.io/part-of: telecom-platform
  annotations:
    cloud.google.com/neg: '{"ingress": true}'
    cloud.google.com/backend-config: '{"default":"frontend-backend-config"}'
spec:
  type: $SERVICE_TYPE
  selector:
    app.kubernetes.io/name: $FRONTEND_NAME
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
EOF

write_file "$K8S_DIR/hpa.yaml" <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: $FRONTEND_NAME
  namespace: $NAMESPACE
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: $FRONTEND_NAME
  minReplicas: $REPLICAS
  maxReplicas: 5
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
EOF

write_file "$K8S_DIR/pdb.yaml" <<EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: $FRONTEND_NAME
  namespace: $NAMESPACE
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: $FRONTEND_NAME
EOF

write_file "$K8S_DIR/networkpolicy.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: $FRONTEND_NAME
  namespace: $NAMESPACE
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: $FRONTEND_NAME
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - ports:
        - protocol: TCP
          port: 8080
  egress:
    - ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 80
EOF

write_file "$K8S_DIR/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - backend-config.yaml
  - deployment.yaml
  - service.yaml
  - hpa.yaml
  - pdb.yaml
  - networkpolicy.yaml
EOF

write_file "$ROOT/scripts/frontend-smoke-test.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"

check() {
  local path="$1"
  local description="$2"
  if curl -fsS "$BASE_URL$path" >/dev/null; then
    printf 'PASS  %s\n' "$description"
  else
    printf 'FAIL  %s (%s%s)\n' "$description" "$BASE_URL" "$path" >&2
    exit 1
  fi
}

check "/frontend-health" "Frontend Nginx health endpoint"
check "/" "Single-page application"
check "/health/live" "API Gateway proxy"
printf '\nFRONTEND SMOKE TEST: PASSED\n'
EOF
chmod +x "$ROOT/scripts/frontend-smoke-test.sh"

# ----------------------------------------------------------------------------
# Validation, build, push, and deployment
# ----------------------------------------------------------------------------

if [[ "$BUILD_PUSH" == "1" ]]; then
  need docker
  docker buildx version >/dev/null 2>&1 || die "Docker Buildx is required."
  need gcloud
  log "Ensuring Artifact Registry is available"
  gcloud services enable artifactregistry.googleapis.com --project "$PROJECT_ID" --quiet
  if ! gcloud artifacts repositories describe "$AR_REPOSITORY" \
      --location "$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; then
    gcloud artifacts repositories create "$AR_REPOSITORY" \
      --repository-format docker \
      --location "$REGION" \
      --project "$PROJECT_ID" \
      --description "DevOps portfolio container images" \
      --quiet
  fi

  log "Configuring Docker authentication for $REGISTRY_HOST"
  gcloud auth configure-docker "$REGISTRY_HOST" --quiet

  log "Building production frontend image"
  docker build \
    --label "org.opencontainers.image.source=devops-portfolio" \
    --label "org.opencontainers.image.revision=$IMAGE_TAG" \
    -t "$IMAGE" \
    "$FRONTEND_DIR"

  log "Pushing $IMAGE"
  docker push "$IMAGE"
  ok "Image pushed"
else
  warn "BUILD_PUSH=0: source and manifests were generated, but no image was built or pushed."
fi

if [[ "$DEPLOY" == "1" ]]; then
  if [[ "$GET_CREDENTIALS" == "1" ]]; then
    need gcloud
    log "Loading credentials for GKE cluster $GKE_CLUSTER"
    if [[ "$GKE_LOCATION_TYPE" == "zone" ]]; then
      gcloud container clusters get-credentials "$GKE_CLUSTER" \
        --zone "$GKE_LOCATION" --project "$PROJECT_ID"
    else
      gcloud container clusters get-credentials "$GKE_CLUSTER" \
        --region "$GKE_LOCATION" --project "$PROJECT_ID"
    fi
  fi

  need kubectl

  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log "Creating namespace $NAMESPACE"
    kubectl create namespace "$NAMESPACE"
  fi

  if ! kubectl -n "$NAMESPACE" get service api-gateway >/dev/null 2>&1; then
    die "Kubernetes Service api-gateway was not found in namespace $NAMESPACE. Deploy the backend gateway first, then rerun with BUILD_PUSH=0."
  fi

  log "Validating Kubernetes manifests"
  kubectl kustomize "$K8S_DIR" >/dev/null

  log "Applying frontend resources"
  kubectl apply -k "$K8S_DIR"

  log "Waiting for frontend rollout"
  kubectl -n "$NAMESPACE" rollout status deployment/"$FRONTEND_NAME" --timeout=180s

  ok "Frontend is running in Kubernetes"
  kubectl -n "$NAMESPACE" get deployment,pods,service,hpa,pdb \
    -l "app.kubernetes.io/name=$FRONTEND_NAME" \
    -o wide || true
else
  warn "DEPLOY=0: Kubernetes manifests were generated but not applied."
fi

cat <<SUMMARY

==============================================================================
TELECOM FRONTEND BOOTSTRAP COMPLETE
==============================================================================

Frontend source:
  ${FRONTEND_DIR#"$ROOT/"}

Kubernetes manifests:
  ${K8S_DIR#"$ROOT/"}

Container image:
  $IMAGE

GKE cluster:
  $GKE_CLUSTER ($GKE_LOCATION_TYPE: $GKE_LOCATION)

Kubernetes service type:
  $SERVICE_TYPE

External exposure:
  Use the existing telecom-ingress by running 03-apply-final-ingress.sh.

Local Compose:
  docker compose \\
    -p devops-portfolio \\
    --env-file .env.platform \\
    -f docker-compose.platform.yml \\
    -f docker-compose.frontend.yml \\
    up -d --build

Then open:
  http://localhost:3000

Kubernetes status:
  kubectl -n $NAMESPACE get svc $FRONTEND_NAME

For an internal preview before updating Ingress:
  kubectl -n $NAMESPACE port-forward svc/$FRONTEND_NAME 3000:80

Then open:
  http://localhost:3000

Smoke test:
  BASE_URL=http://localhost:3000 ./scripts/frontend-smoke-test.sh

Backup directory:
  ${BACKUP_ROOT#"$ROOT/"}
==============================================================================
SUMMARY

