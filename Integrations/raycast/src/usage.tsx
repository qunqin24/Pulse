import { Action, ActionPanel, Color, Detail, getPreferenceValues, Icon, List } from "@raycast/api";
import { execFile } from "node:child_process";
import { useEffect, useState } from "react";
import { Account, accountURL, age, parseReport, Report, resetText, status, windowName } from "./report";

export default function Command() {
  const [report, setReport] = useState<Report>();
  const [error, setError] = useState(false);
  const [loading, setLoading] = useState(true);
  const [generation, setGeneration] = useState(0);

  useEffect(() => {
    setLoading(true);
    setError(false);
    let active = true;
    const path = getPreferenceValues<{ pulsePath?: string }>().pulsePath?.trim() || "/Applications/Pulse.app/Contents/MacOS/Pulse";
    // No shell: a path containing spaces or metacharacters remains one path.
    const child = execFile(path, ["--json"], { timeout: 5000, maxBuffer: 2 * 1024 * 1024 }, (failure, stdout) => {
      if (!active) return;
      try {
        if (failure) throw failure;
        setReport(parseReport(stdout));
      } catch {
        setReport(undefined);
        setError(true);
      } finally {
        setLoading(false);
      }
    });
    return () => { active = false; child.kill(); };
  }, [generation]);

  const reload = () => setGeneration((value) => value + 1);
  if (error) {
    return <Detail markdown={"# Couldn't read Pulse\n\nInstall Pulse and check **Pulse Executable** in this extension's preferences. It must point to `Pulse.app/Contents/MacOS/Pulse`.\n\nThis command only reads the cache. Keep Pulse running to update it."} actions={
      <ActionPanel><Action title="Retry Cache Read" onAction={reload} /><Action.OpenInBrowser title="Open Pulse Settings" url="pulse://settings" /></ActionPanel>
    } />;
  }
  return <List isLoading={loading} isShowingDetail searchBarPlaceholder="Search Pulse accounts…">
    <List.EmptyView title="No accounts in the cache" description="Open Pulse, enable an account, and let it take a reading." actions={
      <ActionPanel><Action.OpenInBrowser title="Open Pulse Settings" url="pulse://settings" /><Action title="Reload Cache" onAction={reload} /></ActionPanel>
    } />
    {report?.accounts.map((account) => <AccountRow key={account.id} account={account} reload={reload} />)}
  </List>;
}

function AccountRow({ account, reload }: { account: Account; reload: () => void }) {
  const old = !account.observedAt || Date.now() - Date.parse(account.observedAt) >= 1800_000;
  const url = accountURL(account.id);
  return <List.Item
    title={account.label}
    subtitle={status(account)}
    keywords={[account.name, account.provider, account.id]}
    icon={{ source: Icon.CircleProgress, tintColor: old ? Color.SecondaryText : Color.PrimaryText }}
    accessories={[{ text: age(account) }]}
    detail={<List.Item.Detail metadata={<List.Item.Detail.Metadata>
      <List.Item.Detail.Metadata.Label title="Provider" text={account.name} />
      <List.Item.Detail.Metadata.Label title="Plan" text={account.plan ?? "Not reported"} />
      <List.Item.Detail.Metadata.Label title="Source" text={account.source ?? "Not recorded"} />
      <List.Item.Detail.Metadata.Label title="Reading taken" text={account.observedAt ? new Date(account.observedAt).toLocaleString() : "No reading"} />
      <List.Item.Detail.Metadata.Label title="Freshness" text={old ? "Old or missing — check Pulse" : "Cached reading"} />
      {account.creditBalance != null && <List.Item.Detail.Metadata.Label title="Balance" text={account.creditBalance} />}
      {account.windows.map((window) => <List.Item.Detail.Metadata.TagList key={window.id} title={windowName(window)}>
        <List.Item.Detail.Metadata.TagList.Item text={`${window.estimated ? "≈" : ""}${window.usedPercent}% used${window.exhausted ? " · exhausted" : ""}`} />
        {window.estimated && <List.Item.Detail.Metadata.TagList.Item text={`Inferred: ${window.estimatedFrom ?? "estimate"}`} />}
        <List.Item.Detail.Metadata.TagList.Item text={`Reset: ${resetText(window.resetsAt)}`} />
      </List.Item.Detail.Metadata.TagList>)}
    </List.Item.Detail.Metadata>} />}
    actions={<ActionPanel>
      <Action.OpenInBrowser title="Open Account in Pulse" url={url} />
      <Action title="Reload Cache" icon={Icon.ArrowClockwise} onAction={reload} shortcut={{ modifiers: ["cmd"], key: "r" }} />
      <Action.CopyToClipboard title="Copy Account Link" content={url} />
      <Action.CopyToClipboard title="Copy Usage Summary" content={`${account.label}: ${status(account)} · ${age(account)}`} />
    </ActionPanel>}
  />;
}
