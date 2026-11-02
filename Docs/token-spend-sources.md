# Token spend sources

Owns: the complete list of agent stores the Token spend pane can read — default macOS location, store format, the counters it really reports, and how well each one is evidenced. The pane itself and what may be said about its figures: [token-spend.md](token-spend.md).

The catalogue recognizes **54 agent sources**: the seven clients read on a real machine before the catalogue grew (`claudeCode`, `codex`, `openCode`, `kiloCLI`, `grok`, `kimiCLI`, `devinCLI`; the only ones with `hasCapturedValidation`) and **47** added from second-hand format specifications of a compatibility target (Tokscale 4.17.0). No upstream code, test or fixture is vendored: each added reader was written independently from file locations, field meanings, units and event identities, with original synthetic test data, and none has been verified against a live client store. The canonical id is `SpendAgent.sourceID`, the string the reader families dispatch on; the seven legacy cases keep their Swift `rawValue` identities. The cache format is versioned separately, and older formats are reread.

## Evidence levels

- **machine** — the reader was run against a real store with real work in it.
- **spec** — written from a second-hand format spec and checked with synthetic stores. The shape is pinned against change; it is **not** proof the shape is right.
- **export** — as *spec*, and additionally needs a prior export, sync or capture by another tool; without it there is nothing to read.

## Counter status

- **real** — the store reports measured input/output/cache counters; the reader uses only them.
- **real, session total** — real counters that exist only as a session/report aggregate; timing is coarse (`isAggregate`).
- **partial source** — some shape or row cannot prove the report is complete (an ambiguous cache or reasoning relation, or real usage with no locatable time or model), so its records are marked `isPartial`.
- **cost only** — money or request counts and no measured tokens. Pulse reports no token figure.
- **estimated only** — character-based estimates only. Pulse does not report them as usage.

`isPartial`, `unclassifiedTokens` and `isAggregate` are independent and may coexist; what each means and how the pane shows it: [token-spend.md](token-spend.md#unclassified-incomplete-and-coarse-are-three-different-things).

The six added families each expose `inputs(client:home:environment:)` (input candidates; the existing ones form the cache fingerprint, and roots are rediscovered after reading) and `records(client:roots:)` (`AgentUsageRecord` increments). Every counter is priced through the shared function ([token-spend.md](token-spend.md#what-the-readers-agree-on)). Compression failures are reported through `notes`, and a read with notes is shown but **not persisted**. Reading is opt-in and cancellable ([token-spend.md](token-spend.md#opt-in-reading-and-cancellation)); JSONL is streamed ([token-spend.md](token-spend.md#read-memory-and-workbuddy)).

## Group A — session logs (`SessionLogReaders`)

Pi-shaped JSONL: a session header, assistant `message` records, and a `usage` object with four independent buckets. Cross-session dedup by response/message identity, so a fork copy collapses.

| Client | Default macOS location | Counter status | Evidence |
|---|---|---|---|
| `pi` | `~/.pi/agent/sessions/**/*.jsonl` | real | spec |
| `omp` | `~/.omp/agent/sessions/**/*.jsonl` | real; a message's `provider` names the backend that served the request (e.g. `devin`) and is what `CardHistorySource.AgentSlice` filters on for that provider's card; a message with none falls back to `omp` | spec |
| `senpi` | `~/.senpi/agent/sessions`, plus `.omo/senpi-task/children` for each recorded `cwd` | real | spec |
| `kimchi` | `~/.config/kimchi/harness/sessions` | real | spec |
| `prime-agent` | `~/.prime/agent/sessions` + `session-artifacts`, redirected by a `settings.json` `sessionDir` | real, after parent/child reconciliation | spec |
| `gemini` | `~/.gemini/tmp` (legacy `session-*.json`, `tmp/<id>/chats/*.json`, headless `*.jsonl`) | real; both shapes fold tool tokens into fresh input; `--output-format json` counts are read from `stats.models.<m>.tokens`; a `stream-json` result names neither thoughts nor tool tokens, so its total beyond input and output is unclassified; an unsettled cache relation marks records partial | spec |
| `qwen` | `~/.qwen/projects/<project>/chats/*.jsonl` | real; `cache_read` sits **inside** `promptTokenCount`, and a reported total settles the overlap; an unsettled line is partial | spec |
| `amp` | `~/.local/share/amp/threads/T-*.json` | real | spec |
| `droid` | `~/.factory/sessions/*.settings.json` + sibling `*.jsonl` | real session total; with no total and a positive cache, output is priced, input is unclassified and the record is partial | spec |
| `openclaw` | `~/.openclaw/agents` (SQLite `openclaw-agent.sqlite`, legacy `sessions/*.jsonl`) plus legacy `~/.clawdbot`, `~/.moltbot`, `~/.moldbot` | real; mirrored Codex rollouts and `.zst` archives are not read; an incomplete read is partial | spec |

- `PI_CODING_AGENT_DIR` is read by both Pi and omp, so neither reader honours it; watching it twice would count one tree twice. `SENPI_CODING_AGENT_DIR`/`_SESSION_DIR`, `KIMCHI_CODING_AGENT_DIR`, the `PRIME_AGENT_*` keys and `GEMINI_CLI_HOME` are honoured where the spec says the client does.
- Qwen follows Google's documented `usageMetadata` (`totalTokenCount` is the authority); a relation the store does not state is carried as unclassified, not guessed.
- In the Pi-shaped family and Amp, real usage with no usable model or locatable time makes the whole read partial rather than being dropped silently.

## Group B — editors, buddies and standalone logs (`EditorLogReaders`)

| Client | Default macOS location | Counter status | Evidence |
|---|---|---|---|
| `roocode` | `~/Library/Application Support/Code/User/globalStorage/rooveterinaryinc.roo-cline/tasks/`, `~/.config/Code/…`, Insiders/VSCodium and `.vscode-server` variants | real | spec |
| `kilocode` | the same editor roots for `kilocode.kilo-code` | real | spec |
| `cline` | the Cline task logs plus the Cline CLI roots (`CLINE_SESSION_DATA_DIR`, `CLINE_DATA_DIR/sessions`, `~/.cline/data/sessions`) | real | spec |
| `codebuddy` | `~/.codebuddy/projects/**/*.jsonl`; IDE extension logs only when no transcript exists | real; transcript + excluded fallback is partial | spec |
| `workbuddy` | `~/.workbuddy/projects`, `~/.workbuddy-ai/projects`; `workbuddy.db` only as a fallback | real; the SQLite fallback reports an **unclassified** aggregate, not fresh input | spec |
| `cherrystudio` | `~/Library/Application Support/CherryStudio/Data/Agents/.claude/projects/` (V2), `~/Library/Application Support/CherryStudio/.claude/projects/` (V1) | real | spec |
| `commandcode` | `~/.commandcode/projects/<slug>/<session>.jsonl` | modern real; a legacy line with no `usage` block contributes **nothing** | spec |
| `opencodereview` | `~/.opencodereview/sessions/<encoded-repo>/<session-id>.jsonl` | the store's own total settles the cache relation; no total with a positive cache is skipped, and remaining records are partial | spec |
| `zcode` | `~/.zcode/projects/**/*.jsonl`, `~/.zcode/cli/db/db.sqlite` | modern real; a reported total subtracts the cache overlap, a bare total is unclassified, a legacy line with no usage contributes nothing | spec |

- **VS Code task logs** are `ui_messages.json` (`say == "api_req_started"`), each carrying the four counts in an inner JSON string.
- **Cherry Studio** appends the same API call several times with one `requestId`; the reader merges them by field-wise maximum so a streamed snapshot is not new usage.
- **Command Code** is a tree, but **every reply with reported usage counts**, abandoned branches included: `/rewind` changes context, not consumed tokens. Its session/message id folds replays, and its own ancestry resolves an omitted model, so a sibling branch's model change cannot reprice it.
- **Tencent (CodeBuddy/WorkBuddy): the JSONL transcript is the only reconcilable channel.** When present, the extension log and aggregate database are not returned, because they share no identity with its message ids; if that excluded fallback held records, the transcript records are marked `isPartial` (scanning stops at the first valid fallback record, which is enough to set the flag; none of its counters are added). With no transcript the fallback stands alone, and a mirrored log line may then count twice, which is preferred to folding two real same-second requests into one. The root-level `binaries/` subtree (runtime downloads) is excluded from reading and fingerprinting.

## Group C — databases and event logs (`DatabaseLogReaders`)

| Client | Default macOS location | Counter status | Evidence |
|---|---|---|---|
| `hermes` | `$HERMES_HOME` else `~/.hermes`, `state.db` and `profiles/*/state.db` | real session aggregate; with a cache, input is unclassified and the cache is not added; a positive cache or reasoning is partial | spec |
| `goose` | `~/Library/Application Support/goose/sessions/sessions.db` (and the `Block/goose` legacy roots) | input/output real; the `total − input − output` remainder is **unclassified**, not reasoning; no cache columns; aggregate | spec |
| `zed` | `~/Library/Application Support/Zed/threads/threads.db` | real aggregate; no reasoning field; `zstd` threads decoded through the shared system-library decoder | spec |
| `kiro` | `~/.kiro/sessions/cli/*.json` + sibling `*.jsonl` | only explicit `input_token_count`/`output_token_count` are real; estimate-only variants are not read | spec |
| `crush` | `projects.json` registry (XDG/`CRUSH_GLOBAL_DATA`) + each projected `crush.db` | **cost only** — no token records, by design | spec |
| `unsloth` | `$UNSLOTH_STUDIO_HOME` else `~/.unsloth/studio/studio.db` | real | spec |
| `antigravity-cli` | `$GEMINI_CLI_HOME` else `~/.gemini`, `antigravity-cli/conversations/*.db` | real; `#1` is not counted and `#9.#10` is never decoded into a time; every record is partial | spec |
| `antigravity-ide` | the same root, `antigravity/conversations/*.db` and `antigravity-ide/conversations/*.db` | as `antigravity-cli` — same store shape, same reader, same partial rule | spec |
| `micode` | `<xdg_data>/mimocode/mimocode*.db`, plus the Orca hook sandbox copy under `~/Library/Application Support/orca/` | real | spec |
| `devin-desktop` | `~/Library/Application Support/Devin/User/acp-events/*.ndjson`, `~/.config/devin/User/acp-events` | NDJSON counters; the native DB resolves identity and excludes counted-session mirrors, but does not establish Desktop presence | spec |

- **Hermes** carries `input_tokens` as **unclassified** once a cache column is non-zero, and adds neither the cache nor `reasoning_tokens`: the schema establishes neither relation, and summing would double count a subset. Neither Hermes nor Droid (Group A, same cache rule) is treated as Anthropic-independent.
- **Antigravity** counts only fields with an observed meaning (`#2`, `#5`, `#9`, `#10`, with `#9 + #10` the output contract counted once). The near-constant `#1` is not counted (its "fixed system prompt" reading is reverse-engineered, not established), and the unknown `#9.#10` bytes are never turned into a time; a turn with no proven timestamp falls back to the conversation's created-at and is marked aggregate. Every record is partial because no whole-usage total reconciles the counted fields.
- **Antigravity CLI and IDE are two clients sharing one reader, never one client reading both**: the same store shape written by different products, so pooling them would put one figure on screen for two things. The spec named only `antigravity-cli/conversations`, which is not where the IDE writes (historical, one Mac with the IDE: that folder was absent while `antigravity/conversations` held 38 readable generations, 3.3M tokens of `gemini-3.8-flash`). The spec's path is kept, a missing root yields no records, and `AntigravityRootsTests` pins that the two share no root. **`gemini-default` and `gemini-pro-default` are routing tiers, not models** (#90): neither has a price, so the row's display label resolves them through a verified table (`labelTable`: the three Gemini 3.5 Flash efforts, and "Gemini 3.1 Pro (High)" → `gemini-3.1-pro-preview-high`, observed on one Mac 2026-10-18), before the file's single named model — a Pro row beside a Flash one was otherwise priced as the Flash. An unknown label stays unpriced.

## Group D — per-product stores (`StructuredLogReaders`)

| Client | Default macOS location | Counter status | Evidence |
|---|---|---|---|
| `mux` | `~/.mux/sessions/<workspaceId>/session-usage.json` | real session total per model; ambiguous reasoning is omitted and the record is partial | spec |
| `codebuff` | `~/.config/manicode{,-dev,-staging}/projects/<project>/chats/<chatId>/chat-messages.json` | real; input is the provider's `prompt_tokens` and holds the cache read, which is taken out (Codebuff's own `tokens.ts`) | spec |
| `freebuff` | the same Codebuff trees, `base2-free*` chats | **estimated only** — no persisted counters | spec |
| `jcode` | `~/.jcode/sessions/session_*.json` + `session_*.journal.jsonl` | real; an ambiguous cache makes input unclassified and the record partial, as does omitted reasoning | spec |
| `augment` | `~/.augment/sessions/<sessionId>.json` | real | spec |
| `gjc` | `~/.gjc/agent/sessions` (plus `GJC_CODING_AGENT_DIR`/`GJC_CONFIG_DIR`/`PI_CONFIG_DIR`/`XDG_DATA_HOME` spellings) | real | spec |
| `junie` | `~/.junie/sessions/<session-id>/events.jsonl` | real; ambiguous reasoning is omitted and the record is partial | spec |
| `dsh` | `~/.dsh/sessions` (`session.jsonl` or `session.jsonl.zstd`) | real; `outputTokens` already includes reasoning, kept once | spec |
| `fx` | `~/.fx/sessions/<sessionId>/usage-v2.json` | real session total per model; ambiguous reasoning is omitted and the record is partial | spec |
| `lmstudio` | `~/.lmstudio/server-logs/**/*.log` | real; completion already includes reasoning, kept once | spec |
| `reasonix` | `~/.reasonix/stats/YYYY-MM-DD.jsonl` | real; completion already includes reasoning, kept once | spec |

- `CODEBUFF_DATA_DIR`, `FREEBUFF_DATA_DIR`, `JCODE_HOME`, `DSH_HOME`, `LM_STUDIO_HOME` and `REASONIX_HOME`/`REASONIX_STATE_HOME` replace the defaults.
- DSH's compression is decided by the zstd frame magic, not the extension, with raw and decoded ceilings so a torn trailing frame or a high-ratio file cannot allocate without bound.
- **Two reasoning conventions, kept apart.** Where the format states reasoning is inside output (`dsh`, `lmstudio`, `reasonix`) it is counted once and the record is complete on that axis; where it states nothing (`mux`, `fx`, `jcode`, `junie`) the figure is omitted and the record marked partial.
- Jcode never infers a cache convention from magnitude: an unmarked positive cache leaves the input unclassified and the cache uncounted.

## Group E — exports, caches and captures (`CapturedUsageReaders`)

None of these six products writes an unauthenticated native usage log Pulse can read. Each reader reads a cache/export/capture another tool produced, **plus** Pulse's drop folder `~/Library/Application Support/Pulse/UsageImports/<client>`, the supported way to add a file. A fresh install with neither yields nothing. Pulse does not log in, capture a cookie, call a language server or sync anything.

| Client | Default macOS location | Counter status | Evidence |
|---|---|---|---|
| `cursor` | `<config>/cursor-cache/` (`usage*.json`, legacy `usage*.csv`) | real; JSON supersedes CSV; no per-event id, so equal rows are kept and overlapping exports are reconciled by multiset and marked partial | export |
| `antigravity` | `<config>/antigravity-cache/sessions/*.jsonl` | real; ambiguous reasoning is omitted and the record is partial | export |
| `trae` | `<config>/trae-cache/sessions/*.json` | real; no per-row id, so equal rows are kept and overlapping pages are reconciled by multiset and marked partial | export |
| `warp` | `<config>/warp-cache/usage*.json` | **cost/requests only — no tokens in the format** | export |
| `hindsight` | `$HINDSIGHT_HOME/usage/` else `~/.hindsight/usage/*.jsonl` | real; output already includes reasoning, kept once | export |
| `mcode` | MiniMax Code's own log, `~/.minimax/v2/sessions/<yyyy>/<MM>/<dd>/<session>/messages.jsonl` (`MiniMaxCodeSessionReader`, issue #86); else `<config>/headless/mcode/*.jsonl` | real; own log: Pi-shaped `usage`, the answering model per message (routed ones too), `usage.cost` (always 0) not read, all-zero migrated lines skipped, `message_id` once across files; captures: a message is merged only by its own id, never by equal counts. Captures are left unread once the own log yields records — the same work in both would count twice — and the ledger's origin is decided by that same read (`CapturedUsageReaders.mcodeRead`, `AgentRecordReaders.Read.readsOwnLog`): a log of only zeroed migration lines reads the captures and is called imported, not this Mac's own | spec (own log); export (captures) |

- `<config>` is `$TOKSCALE_CONFIG_DIR` when set, else `~/.config/tokscale`.
- **Warp** carries `requestsUsed` and `spendCents` and no token fields, so its tally is zero and must stay zero; showing tokens, or a zero that reads as a token count, would invent one.
- `antigravity` here is the IDE cache, a different source from `antigravity-cli`/`antigravity-ide` in Group C, whose conversations are read directly.
- **Cursor and Trae carry no declared account and no per-event id.** Two equal rows **inside one file/page** stay two records (they can be two real requests); the same row across **files of one scope** is reconciled by content multiset (`{A}` and `{A, B}` give `A` and `B`), and an unconfirmed increment in the shared region is `isPartial`. A native `usage.<account>` name declares a real account; a file that declares none shares one unknown import scope. An event with no `conversationId`/`Cloud Agent ID` counts its tokens but creates **no** session row rather than a synthetic account or per-day id. A JSON file is read when its root holds `usageEventsDisplay`; a CSV when its header names the date, model and four counters. Because a dropped file may cover a narrower range than assumed, JSON and CSV coverage is a **known subset**.

- **MiniMax Code is the one Group E client with a log of its own.** The desktop app writes `messages.jsonl` per session as it runs, which the catalogue's capture-only reader predates. Read from TokenTracker's reader and fixture (which mirrors a real record); the MiniMax Code on the Mac this was written on was an older version with no usage in it. It borrows MiniMax's mark, so MiniMax's card and pane show its history (`CardHistorySource.agents`).

## Group F — the seven existing readers, and Copilot

`copilot` merges three local stores into one client, in priority order OTEL → Desktop SQLite → VS Code `chatSessions`; each later lane is filtered against the earlier ones so one call is counted once.

| Client | Default macOS location | Counter status | Evidence |
|---|---|---|---|
| `copilot` | `~/.copilot/otel/*.jsonl`; `~/.copilot/data.db` + `session-state/<id>/events.jsonl`; `~/Library/Application Support/Code/User/workspaceStorage/*/chatSessions/*.jsonl` | real; an OTEL record with no trace/response id, a desktop record with ambiguous reasoning, and OTEL covering only part of a desktop lifetime are all partial | spec |

- The lanes share no dedup key. An OTEL usage line with neither a trace nor a response id counts as its own event and is `isPartial`, never folded onto another by a shared instant.
- The desktop SQLite row is a lifetime total and the authority; its sidecar writes cumulative snapshots that are differenced per model. A session already seen in OTEL is dropped whole. When the desktop lifetime exceeds what OTEL recorded, the OTEL records are `isPartial`: the difference is **stated, not subtracted**, because an OTEL span and a desktop lifetime are not equal scopes.
- Desktop reasoning is ambiguous (not declared a subset of output), so it is omitted and the record is partial. Desktop input (row and sidecar) holds the cache, as the API's `prompt_tokens` does: the budget compares gross with gross, and the record takes the cache read and write out (a remainder has no write figure).
- VS Code's `promptTokens` is the same cache-holding figure with no cached count beside it, so it is **unclassified**, not fresh input. A VS Code request with no timestamp is **skipped**, not dated at the epoch.

The seven existing clients read these locations:

| Canonical client | Swift case | Current location |
|---|---|---|
| `claude` | `claudeCode` | `~/.claude/projects` |
| `codex` | `codex` | `~/.codex/sessions` |
| `opencode` | `openCode` | `~/.local/share/opencode/opencode.db` |
| `kilo` | `kiloCLI` | `~/.local/share/kilo/kilo.db` |
| `grok` | `grok` | `~/.grok/sessions` |
| `kimi` | `kimiCLI` | `~/.kimi/sessions`; Kimi Code's `$KIMI_CODE_HOME/sessions` (default `~/.kimi-code/sessions`) |
| `devin-cli` | `devinCLI` | `~/.local/share/devin/cli/sessions.db` |

The compatibility reference describes further locations and formats **not implemented in those seven readers**:

| Client | Additional sources (spec) |
|---|---|
| `claudeCode` | `$CLAUDE_CONFIG_DIR`; `<root>/transcripts`; cc-mirror variants; sidechain `subagents/**/agent-*.jsonl` (skip a `journal.jsonl`); tool-result usage |
| `codex` | `$CODEX_HOME`; headless captures; `reasoning_output_tokens` subtraction; `session_meta.originator == "openclaw"` retags the rollout to `openclaw` |
| `openCode` | channel DBs `opencode-<channel>.db`; legacy `storage/message` JSON; cross-DB dedup by embedded message id (the v2 `session_message` schema **is** read — see Cross-source routing) |
| `kiloCLI` | Kilo's snake_case session id; a timestamp-less message needs an evidenced time, not the database's modification date |
| `grok` | `logs/unified.jsonl`; sibling `signals.json` reconciliation; `GROK_HOME` |
| `kimiCLI` | Kimi Work desktop protocol; a model for the legacy log from `config.json` |
| `devinCLI` | Windows `%APPDATA%` root; `metadata.num_tokens` attributed to output when `metrics` is absent |

Codex's `input_tokens` includes cached input, so fresh input subtracts that overlap; its `output_tokens` already includes reasoning and is kept once.

**`devin-cli` is shown as Devin, not "Devin CLI".** Its `~/.local/share/devin/cli/sessions.db` path is Devin's directory layout, not a product marker: Desktop embeds the same core and starts it as a CLI (`init_cli`, `binary=devin`, `backend_type=windsurf` on every session), so the database is written with only Desktop installed (historical, one Mac with no `devin` on `PATH`). The database cannot say which client drove it, so the name claims neither. `devin-desktop` stays separate because its evidence, the `acp-events` capture tree, belongs to Desktop alone. Rows are **not** split by `backend_type`: one machine's sessions all carrying `windsurf` is not an established mapping.

## Compression is a local library, not an OS guarantee

DSH transcripts and Zed's `zstd` threads need a zstd decoder. Pulse vendors none: it resolves the system library by explicit path, in order `/usr/lib/libzstd.1.dylib`, `/opt/homebrew/lib/libzstd.1.dylib`, `/usr/local/lib/libzstd.1.dylib`, never by bare name. A Homebrew `libzstd` works; another machine may have none. When no library loads, a frame is corrupt, or a raw/decoded bound is exceeded, the reader reports a `note` rather than treating the transcript as empty, and the read is not written to the disk cache, so a later build with a decoder can still recover it. OpenClaw's `.zst` archives stay unread even with a decoder, because its own reader does not decode them.

## Cross-source routing and dedup

- **General rule.** The dedup identity is the product's own stable event id (message id, response id, trace+span, event id, cumulative-total watermark). File position or a synthetic timestamp bucket is a fallback only and is unstable under append — flag or avoid it. A globally unique embedded id must not be namespaced by file or database, or fork copies will not collapse.
- **OpenClaw** deduplicates its native stores by recorded event identity. Retagging Codex app-server rollouts and reconciling those mirrors are not implemented; combined mirrored source sets need further validation.
- **OpenCode** keeps its existing database reader, which also reads **OpenCode 2's** `session_message` (role in its `type` column, model under `model.id`) and `session_v2`: the upgrade copied history there under the same ids and stopped writing `message`, so the old query missed every later request. Old rows the copy lacks are still read; an id counts once. Multi-channel and legacy-message reconciliation remain unimplemented format work.
- **Copilot OTEL → Desktop → VS Code**, filtered by session id and then by dedup key or `(session_id, timestamp)`.
- **Kiro** reads explicit CLI counters; the estimate-based IDE and database snapshot variants are not parsed.
- **Devin Desktop vs Devin.** The Desktop NDJSON resolves its session/model/workspace from the database by an unambiguous title. A session with usable dated message counters in the native Devin database belongs to that database; its Desktop capture is a mirror and is excluded before pricing. The counted-session test uses `DevinCLIStore`'s actual message parser, not the existence of a metadata row: a metadata-only session still uses its capture, a database used only for lookup cannot suppress work, and unresolved or ambiguous titles are not identity matches. This is session-level source precedence, not subtraction of two differently scoped totals.
- **Tencent**: the JSONL transcript supersedes the extension log and the aggregate database for the same client (Group B).

## Limits and unimplemented variants

Each item is detailed in its group above; this is the index.

- **Unread:** `openclaw`'s mirrored Codex app-server rollouts and `.zst` archives; Kiro's IDE/globalStorage/SQLite variants.
- **Deliberately not reported:** estimated-only stores (`freebuff`, Kiro's estimate variants, legacy `commandcode`/`zcode` lines without a `usage` block) and cost-only stores (`crush`, `warp`).
- **Conditional:** `zed` and `dsh` compressed history needs a local `libzstd`, otherwise a `note`; Group E needs an export, capture or `UsageImports/<client>` file.
- **Partial or unclassified rather than guessed:** see each group's Counter status column and notes.
- **Evidence:** no client beyond the seven legacy readers carries `hasCapturedValidation`, and a reader that reports `notes` is validated no further than its synthetic stores. The suites assert the declared contract; they do not state that any added client passed on a real machine.
