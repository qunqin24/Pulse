import assert from "node:assert/strict";
import { test } from "node:test";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { accountURL, age, parseReport, resetText, status } from "../src/report.ts";

const generatedAt = "2026-09-10T10:00:00Z";
const account = {
  id: "claudeCode#work", provider: "claudeCode", name: "Claude Code", label: "Work",
  observedAt: generatedAt, ageSeconds: 0,
  headline: { windowId: "w", usedPercent: 99, exhausted: false },
  windows: [{ id: "w", kind: "weekly", usedPercent: 99, exhausted: false, estimated: false }],
};

test("missing readings and balance-only accounts never turn into zero percent", () => {
  assert.equal(status({ ...account, headline: undefined, windows: [] }), "No reading");
  assert.equal(status({ ...account, headline: undefined, windows: [], creditBalance: "¥9.40" }), "¥9.40");
  assert.equal(status(account), "99% used");
  assert.equal(status({ ...account, windows: [{ ...account.windows[0], estimated: true }] }), "≈99% used");
});

test("age is measured from the observation, not frozen at JSON generation", () => {
  assert.equal(age(account, Date.parse(generatedAt) + 3600_000), "Read 1h ago");
  assert.equal(age({ ...account, observedAt: undefined }), "No dated reading");
  assert.match(resetText(generatedAt, Date.parse(generatedAt) + 1), /passed/);
});

test("deep links preserve the full added-account id", () => {
  assert.equal(accountURL(account.id), "pulse://account/claudeCode%23work");
});

test("the consumer accepts additive fields and rejects malformed nested readings", () => {
  const json = { generatedAt, accounts: [account], future: true };
  assert.equal(parseReport(JSON.stringify(json)).accounts.length, 1);
  assert.throws(() => parseReport(JSON.stringify({ generatedAt, accounts: [{ ...account, windows: [null] }] })));
  assert.throws(() => parseReport(JSON.stringify({ generatedAt, accounts: [{ ...account, headline: { usedPercent: "99" } }] })));
  assert.throws(() => parseReport("not-json"));
});

const script = fileURLToPath(new URL("../../pulse-status.sh", import.meta.url));
function shell(accounts, args = [], env = {}) {
  const result = spawnSync("/bin/bash", [script, "--stdin", ...args], {
    input: JSON.stringify({ generatedAt, accounts }), encoding: "utf8",
    env: { ...process.env, PULSE_ACCOUNT: "", PULSE_MAX_AGE: "1800", ...env },
  });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

test("shell integration handles gaps, estimates, stale readings and exact account selection", () => {
  const missing = { ...account, id: "codex", label: "Codex", headline: undefined, windows: [], observedAt: undefined, ageSeconds: undefined };
  assert.equal(shell([missing]), "Codex: — (no reading)");
  assert.equal(shell([{ ...missing, creditBalance: "¥9.40", observedAt: generatedAt, ageSeconds: 0 }]), "Codex: ¥9.40");
  assert.equal(shell([{ ...account, ageSeconds: 1800 }]), "Work: 99% used (old)");
  assert.equal(shell([{ ...account, windows: [{ ...account.windows[0], estimated: true }] }]), "Work: ≈99% used");
  assert.equal(shell([account, missing], [], { PULSE_ACCOUNT: account.id }), "Work: 99% used");
  assert.equal(shell([]), "Pulse —");
});

test("tmux labels cannot inject formatting or additional lines", () => {
  assert.equal(shell([{ ...account, label: "#[fg=red]\nwork" }], ["--tmux"]), "##[fg=red] work: 99% used");
});
