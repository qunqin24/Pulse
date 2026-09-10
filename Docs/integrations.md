# Developer integrations / 开发者集成

Open **Pulse Settings → Developer integrations → Export integration files…**. Choose a folder; Pulse creates `Pulse Integrations` inside it. The kit contains a Raycast extension and scripts for tmux, sketchybar and a shell prompt. From a source checkout, the same files are in [`Integrations/`](../Integrations/).

在 **Pulse 设置 → 开发者集成 → 导出集成文件…** 中选择目录，即可获得 `Pulse Integrations` 文件夹。下方示例假定导出到了「下载」目录；其他位置请替换路径。Raycast 扩展通过本地导入安装，终端脚本需要 `jq`。

Every integration runs **`Pulse --json`**, which reads the cache without fetching providers or opening credentials. Keep Pulse running to update it. The output contains only accounts enabled on the rail. Missing figures stay missing; inferred figures carry `≈`; older readings remain explicitly dated. JSON contract: [json-output.md](json-output.md).

集成只读取缓存，不额外请求服务商。请保持 Pulse 运行；无读数显示 `—`，推算百分比显示 `≈`，脚本默认将至少 30 分钟前的读数标为 `(old)`。Raycast 会显示读数时间、所有限额及重置时间。

## Raycast

Requires Raycast and Node.js 22.18+ (or a current LTS). The local extension uses Raycast's own API; it is not automatically installed into Raycast by exporting the kit.

```bash
cd "$HOME/Downloads/Pulse Integrations/raycast"
npm ci
npm run dev
```

Once Raycast registers the extension, search for **Show AI Usage**. Search by provider or account label, inspect all limits and reset times in the detail pane, and press Return to open that account in Pulse. **⌘R reloads the cache**; it does not request new provider data. The action menu also copies an account link or a dated usage summary.

在 Raycast 搜索 **Show AI Usage**，可按服务商或账户名称筛选。回车直达对应账户设置；**⌘R 仅读取最新缓存**，不会强制请求服务商。

If Pulse is installed outside `/Applications`, set the extension's **Pulse Executable** preference to the full path ending in `Pulse.app/Contents/MacOS/Pulse`. Enter a plain path, without shell quotes. An unreadable executable or malformed report shows an error with a retry action; an empty cache offers Pulse Settings.

## Shell and tmux

Install `jq` if needed (`brew install jq`), then try:

```bash
/bin/bash "$HOME/Downloads/Pulse Integrations/pulse-status.sh"
PULSE_ACCOUNT=claudeCode /bin/bash "$HOME/Downloads/Pulse Integrations/pulse-status.sh"
```

Example: `Claude Code: 42% used · Codex: 81% used (old)`.

Environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `PULSE_BIN` | `/Applications/Pulse.app/Contents/MacOS/Pulse`, then `~/Applications` | Executable path, passed as one argument |
| `PULSE_ACCOUNT` | All enabled accounts | Exact account id, including an added account's `#slot` |
| `PULSE_MAX_AGE` | `1800` | Seconds before appending `(old)` |

Find account ids with the command copied from Settings:

```bash
/Applications/Pulse.app/Contents/MacOS/Pulse --json | jq -r '.accounts[] | [.id, .label] | @tsv'
```

Add to `~/.tmux.conf`:

```tmux
set -g status-interval 60
set -g status-right '#(PULSE_ACCOUNT=claudeCode /bin/bash "$HOME/Downloads/Pulse Integrations/pulse-status.sh" --tmux)'
```

Reload with `tmux source-file ~/.tmux.conf`. `--tmux` escapes `#` in account labels so labels cannot become tmux formatting. The script removes control characters and uses the reported display percentage, including the distinction between `99%` and exhausted.

For zsh, a `precmd` hook can put the same summary in the right prompt:

```zsh
function pulse_precmd() {
  local value
  value=$(PULSE_ACCOUNT=claudeCode /bin/bash "$HOME/Downloads/Pulse Integrations/pulse-status.sh") || value='Pulse —'
  RPROMPT="${value//\%/%%}"
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd pulse_precmd
```

This sets `RPROMPT`; incorporate it into an existing prompt configuration if you already use one. Remove the hook with `add-zsh-hook -d precmd pulse_precmd`.

## sketchybar

Keep `pulse-sketchybar.sh` beside `pulse-status.sh`. Add to `sketchybarrc`:

```bash
sketchybar --add item pulse right \
  --set pulse update_freq=60 \
    script="PULSE_ACCOUNT=claudeCode /bin/bash \"$HOME/Downloads/Pulse Integrations/pulse-sketchybar.sh\"" \
    click_script="open 'pulse://account/claudeCode'"
```

The plugin uses sketchybar's `NAME` variable. A failed cache read replaces the label with `Pulse —`, rather than leaving an old figure unmarked. Change `PULSE_ACCOUNT` and the click link together for another account. Remove the item with `sketchybar --remove pulse`.

## Account links

Copy an account link or its `open` command from **Developer integrations** in Settings:

```bash
open 'pulse://settings'
open 'pulse://integrations'
open 'pulse://account/codex'
open 'pulse://account/claudeCode%23YOUR-SLOT'
```

`%23` is the encoded `#` in an added account id. Use the copied link or the JSON `settingsURL` field instead of composing it by hand. Links select an existing account, clear the sidebar search, and open the settings window. They do not create accounts, change settings, or run a refresh/login command. A removed or unknown account does not create a pane. Query strings, fragments and unsupported routes are rejected.

The `pulse` URL scheme is registered by the **app bundle**, so install/open the bundled app for macOS to discover it. A bare `swift run Pulse` executable cannot register that scheme. Routing implementation: [architecture.md](architecture.md).

## Development checks

From `Integrations/raycast`, run `npm ci`, then `npm run build`, `npm run typecheck`, and `npm test`. Tests cover parsing, gaps, balance-only accounts, inferred figures, age, encoded links, and the actual shell formatter (requires `jq`). `ray build` compiles without opening Raycast; host UI interaction is a separate manual check.
