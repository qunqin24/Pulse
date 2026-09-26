# Extensions

Owns: the extension contract. That covers where an extension lives, what its manifest says, how Pulse runs it, and what it has to print. The source is [`Sources/Pulse/Providers/PulseExtension.swift`](../Sources/Pulse/Providers/PulseExtension.swift), and [`Tests/PulseTests/PulseExtensionTests.swift`](../Tests/PulseTests/PulseExtensionTests.swift) pins this page. Proposal and discussion: [issue #51](https://github.com/qunqin24/Pulse/issues/51).

An extension is a program you add yourself, and it reports **one account's** usage: its limits, its prepaid balance, or both. Pulse runs it, reads one JSON object from its standard output, and draws that object with its own ring and card. Use one when a service does not belong in Pulse itself, such as an API relay, an organization's internal quota endpoint or a personal script. It saves you from keeping a fork of Pulse. Relay balances: [issue #40](https://github.com/qunqin24/Pulse/issues/40).

Scope, schema 1:

- **Rings only.** One account per extension, drawn with Pulse's own components. An extension cannot draw anything of its own, and cannot load code into Pulse.
- **Not yet in this schema:** several accounts from one program, an icon of its own, and a detail section on the card. Every extension shows the same puzzle-piece mark, and its name tells it apart.

## Where it lives

```
~/Library/Application Support/Pulse/Extensions/
  acme-quota/
    pulse-extension.json
    run                   ← the program; any executable file
```

Each extension is a folder of its own, directly inside `Extensions`. **Settings → Manage extensions** shows the folder, creates it the first time you open it, and lists every folder it found. A folder that could not be used appears there with the reason.

Pulse reads the folder when it starts and when that pane opens. After adding or changing an extension, press **Look again**. Pulse does not watch the folder, because a program being copied in is half-written for a moment.

## Manifest: `pulse-extension.json`

```json
{
  "schemaVersion": 1,
  "id": "acme-quota",
  "name": "Acme Quota",
  "executable": "run",
  "timeoutSeconds": 20
}
```

| Field | Rule |
|---|---|
| `schemaVersion` | `1`. Any other value is refused, with a message naming the version. |
| `id` | 1–64 characters: lowercase letters, digits, `.`, `-`, `_`, starting with a letter or digit. It becomes the account id `extension#<id>`, and Pulse stores the account's switch, order, ring colour and pinned limit under it. Changing it makes a new account. The first folder in name order keeps a duplicated id. |
| `name` | Shown on the rail's card, in Settings and in notifications. Trimmed and cut to 60 characters. It is never translated. |
| `executable` | A path relative to the folder. After links and `..` are resolved, it must still be a file **inside the folder** and executable. `/bin/sh` or `../other/run` is refused, so the folder Settings shows is always the folder whose program runs. |
| `timeoutSeconds` | Optional; default 20, kept within 1–60. |

Reading a manifest never runs anything.

## How Pulse runs it

- **Only once it is switched on.** A new extension appears in Settings switched off. It runs after **Show in panel** is turned on in its own pane, the same rule every built-in service follows.
- **On the refresh schedule**: every full refresh, and whenever its ring is clicked. Extensions run side by side, so a slow one does not hold the others up.
- **No arguments. Standard input is empty.** The working directory is the extension's folder.
- **A small environment, not Pulse's.** `HOME`, `USER`, `LOGNAME`, `TMPDIR`, `LANG`, `LC_ALL`, `LC_CTYPE` and `SHELL` are passed on, plus any proxy variables, including the manual proxy from **Network and refresh**; see [networking.md](networking.md). `PATH` is `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`, so `#!/usr/bin/env node` and `python3` resolve. Pulse also sets `PULSE_EXTENSION_ID` and `PULSE_EXTENSION_SCHEMA=1`. Nothing else from Pulse's environment is passed on, so a token exported for another tool does not reach the program.
- **No credentials.** The program owns its login. Pulse does not read one for it, store one for it, or pass it one.
- **Bounded.** A program still running at its time limit is stopped: SIGTERM to its process group, then SIGKILL. Output past 256 KiB is discarded. This uses the same runner as `arkcli` (`BoundedProcess`).

A program that exits non-zero shows "The extension stopped with an error." Anything it wrote to stderr is not displayed. One that runs out of time shows "The extension didn't answer in time." A program that has disappeared since the last scan shows "This extension's program can't be run."

## What it prints

One JSON object on standard output, then exit 0:

```json
{
  "schemaVersion": 1,
  "plan": "Team",
  "limits": [
    {
      "id": "monthly",
      "label": "Monthly requests",
      "usedPercent": 42.5,
      "resetsAt": "2026-10-01T00:00:00Z",
      "windowSeconds": 2592000
    },
    {
      "id": "tokens",
      "label": "Tokens",
      "used": 30000,
      "limit": 120000
    }
  ]
}
```

| Field | Rule |
|---|---|
| `schemaVersion` | `1`, or the reply cannot be read. |
| `status` | Optional; `"ok"` by default. See below. |
| `plan` | Optional plan name, shown on the card. Cut to 60 characters. |
| `limits[]` | Each one is a row on the card. The fullest limit drives the ring, unless one is pinned in Settings. |
| `limits[].label` | Required. The row's name, in the program's own words. |
| `limits[].id` | Optional, but recommended. Pinning a ring to a limit is stored against it, so it has to stay the same from run to run. Without it the row's position is used. |
| `limits[].usedPercent` | How much is used, 0–100, or more once a limit is exceeded. |
| `limits[].used` + `limits[].limit` | Instead of `usedPercent`, both as numbers; `limit` must be above zero. |
| `limits[].resetsAt` | Optional ISO 8601 time, with or without fractional seconds. |
| `limits[].windowSeconds` | Optional length of the window. With `resetsAt`, it is what the window clock draws. Leave it out when the length is not known. |
| `balance` | Optional prepaid money left in the account: `{"amount": 16.33, "currency": "USD"}`. |
| `balance.amount` | A JSON number, not a string. Below zero is allowed; some services keep serving an account in debt. |
| `balance.currency` | A three-letter ISO 4217 code such as `USD` or `CNY`, in either case. |

**Pulse does not invent a figure.** A limit with no `usedPercent`, or without both `used` and `limit`, is left off rather than drawn at zero. So is a negative figure, or one that is not a number. A balance without both an amount and a currency code is left off the same way, and the limits beside it are still drawn. A reply with neither a limit nor a balance left shows "No limits reported." A limit at or past 100% counts as spent.

### A balance

A balance is drawn the way every API account's is (`BalanceRing`; see [providers/deepseek.md](providers/deepseek.md)):

- **With no limits**, the money is the reading. The extension's pane in Settings gets **Ring shows**, with the same three choices: since the last top-up that Pulse saw, balance only, or against a budget you type. With balance only, the rail shows the amount itself.
- **With limits**, the limits drive the ring and the card still lists the balance.
- **Never spent on Pulse's say-so.** A balance at or below zero does not mark the account spent. Only a limit at 100% does.
- **Warn below.** Once an extension has reported a balance, its pane offers the low-balance notification, in the balance's own currency. See [notifications.md](notifications.md).

### When there is no reading

Set `status` to one of these names, and Pulse shows its own wording for it. None of the wording names a provider:

| `status` | Shown |
|---|---|
| `signedOut` | The extension says its login has expired. |
| `unreachable` | The service didn't respond. |
| `rateLimited` | Checking too often — easing off. |
| `serverError` | The service returned an error. |
| `noLimits` | No limits reported. |

Any other status, or output that is not this object, shows "Couldn't read the reply." Free text from the program is not shown. The card's wording is translated into every language Pulse ships, and a program's own message would not be.

When a run fails, the last good reading stays on the ring, marked stale. This is the same cache rule as every provider; see [refresh-and-data.md](refresh-and-data.md). Notifications treat a working extension that stops like any other route going down; see [notifications.md](notifications.md).

## Complete examples

### A quota endpoint

```sh
#!/bin/sh
# ~/Library/Application Support/Pulse/Extensions/acme-quota/run
# The program owns its credential. Here it is read from the extension's own file.
token=$(cat "$HOME/.config/acme/token") || { echo '{"schemaVersion":1,"status":"signedOut"}'; exit 0; }
reply=$(curl -fsS -H "Authorization: Bearer $token" https://quota.acme.internal/v1/usage) \
  || { echo '{"schemaVersion":1,"status":"unreachable"}'; exit 0; }
echo "$reply" | /usr/bin/python3 -c '
import json, sys
r = json.load(sys.stdin)
print(json.dumps({"schemaVersion": 1, "plan": r["plan"], "limits": [
  {"id": "monthly", "label": "Monthly requests",
   "used": r["used"], "limit": r["quota"], "resetsAt": r["resets_at"]}]}))'
```

### An API relay's balance

Many relays built on new-api or sub2api answer `GET /v1/usage` with the key's balance. This one reads the key from its own file and reports the balance only:

```sh
#!/bin/sh
# ~/Library/Application Support/Pulse/Extensions/my-relay/run
key=$(cat "$HOME/.config/my-relay/key") || { echo '{"schemaVersion":1,"status":"signedOut"}'; exit 0; }
reply=$(curl -fsS -H "Authorization: Bearer $key" https://relay.example.com/v1/usage) \
  || { echo '{"schemaVersion":1,"status":"unreachable"}'; exit 0; }
echo "$reply" | /usr/bin/python3 -c '
import json, sys
r = json.load(sys.stdin)
left = r.get("remaining", r.get("balance"))
print(json.dumps({"schemaVersion": 1,
  "balance": {"amount": float(left), "currency": r.get("unit", "USD")}}))'
```

Change the field names to match your relay's reply. If the relay counts in points instead of money, report them as a limit with `used` and `limit`, not as a balance.

### Trying it

To test it, run it by hand from its folder. It should print one line of JSON and exit 0. Then open **Settings → Manage extensions**, press **Look again**, and turn on **Show in panel** in the extension's own pane.

## In the rest of Pulse

- **Accounts.** Each extension is an account of the one `Provider.pulseExtension` case, with its id as the slot. `Provider.builtIn` leaves the type out, so the first-run chooser, defaults and upgrade offers never list it. `AppSettings.allAccounts` adds one account per extension found. `ProviderSelection.restore` keeps an extension's switch while its folder is there and drops it once the folder is gone.
- **Settings.** Extensions have their own sidebar section: **Manage extensions**, then one row per extension, with the same pane every account has plus an **Extension** group giving the program, its time limit and its id. See [ui/settings.md](ui/settings.md).
- **`--json`.** It never reads the folder: the app writes down each extension it finds, account id to name, under `settings.extensionNames`, and `AppSettings.storedRail()` lists those. `provider` is `extension`, `source` is `extension`, and each window carries the program's `label`; see [json-output.md](json-output.md).
