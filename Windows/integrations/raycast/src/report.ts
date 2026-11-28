export interface UsageWindow {
  id: string;
  kind: string;
  scope?: string;
  usedPercent: number;
  exhausted: boolean;
  estimated: boolean;
  estimatedFrom?: string;
  resetsAt?: string;
}

export interface Account {
  id: string;
  provider: string;
  name: string;
  label: string;
  plan?: string;
  creditBalance?: string;
  source?: string;
  observedAt?: string;
  ageSeconds?: number;
  headline?: { windowId: string; usedPercent: number; exhausted: boolean; resetsAt?: string };
  windows: UsageWindow[];
}

export interface Report {
  generatedAt: string;
  accounts: Account[];
}

function object(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function optionalString(value: unknown): boolean {
  return value === undefined || value === null || typeof value === "string";
}

function percent(value: unknown): boolean {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= 100;
}

function optionalDate(value: unknown): boolean {
  return value === undefined || value === null || (typeof value === "string" && Number.isFinite(Date.parse(value)));
}

export function parseReport(text: string): Report {
  const report: unknown = JSON.parse(text);
  if (!object(report) || typeof report.generatedAt !== "string" || !Number.isFinite(Date.parse(report.generatedAt)) || !Array.isArray(report.accounts)) {
    throw new Error("Invalid Pulse report");
  }
  for (const account of report.accounts) {
    if (!object(account) || ![account.id, account.provider, account.name, account.label].every((v) => typeof v === "string") ||
        ![account.plan, account.creditBalance, account.source].every(optionalString) ||
        !optionalDate(account.observedAt) ||
        !(account.ageSeconds == null || (typeof account.ageSeconds === "number" && Number.isFinite(account.ageSeconds))) ||
        !Array.isArray(account.windows)) throw new Error("Invalid Pulse account");
    if (account.headline != null && (!object(account.headline) || typeof account.headline.windowId !== "string" ||
        !percent(account.headline.usedPercent) || typeof account.headline.exhausted !== "boolean" || !optionalDate(account.headline.resetsAt))) {
      throw new Error("Invalid Pulse headline");
    }
    for (const window of account.windows) {
      if (!object(window) || typeof window.id !== "string" || typeof window.kind !== "string" ||
          !percent(window.usedPercent) || typeof window.exhausted !== "boolean" || typeof window.estimated !== "boolean" ||
          !optionalString(window.scope) || !optionalString(window.estimatedFrom) || !optionalDate(window.resetsAt)) {
        throw new Error("Invalid Pulse window");
      }
    }
  }
  return report as unknown as Report;
}

export function accountURL(id: string): string {
  return `pulse://account/${encodeURIComponent(id)}`;
}

export function status(account: Account): string {
  if (!account.headline) return account.creditBalance ?? "No reading";
  const window = account.windows.find((window) => window.id === account.headline?.windowId);
  return `${window?.estimated ? "≈" : ""}${account.headline.usedPercent}% used`;
}

export function age(account: Account, now = Date.now()): string {
  if (!account.observedAt) return "No dated reading";
  const seconds = Math.max(0, (now - Date.parse(account.observedAt)) / 1000);
  if (seconds < 60) return "Read <1m ago";
  if (seconds < 3600) return `Read ${Math.floor(seconds / 60)}m ago`;
  return `Read ${Math.floor(seconds / 3600)}h ago`;
}

export function windowName(window: UsageWindow): string {
  const names: Record<string, string> = {
    fiveHour: "5-hour limit", weekly: "Weekly limit", spend: "Spend limit",
    balance: "Balance", monthly: "Monthly limit",
  };
  return [names[window.kind] ?? "Other limit", window.scope].filter(Boolean).join(" · ");
}

export function resetText(value?: string, now = Date.now()): string {
  if (!value) return "Not reported";
  const date = new Date(value);
  if (date.getTime() <= now) return "Reset time passed — reload cache";
  return date.toLocaleString();
}
