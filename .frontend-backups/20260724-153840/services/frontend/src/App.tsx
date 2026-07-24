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
