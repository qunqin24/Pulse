# OpenCode triage bot

Design and deployment for the Pulse GitHub triage commenter. Implementation lives in `.github/workflows/opencode-triage.yml`, `.github/opencode/**`, and `.github/scripts/opencode-*.mjs`. This page is the contract. Limits, SHAs, and timeouts: **read those files** — do not treat numbers here as the implementation.

Official product docs: [OpenCode Go](https://opencode.ai/docs/go/), [tools](https://opencode.ai/docs/tools/), [GitHub](https://opencode.ai/docs/github/), [environment variables](https://opencode.ai/docs/en/environment-variables/). Nothing here claims extra guarantees those pages do not.

## What it does

On **new issues** (`opened`) and pull requests (`opened`, `synchronize`, `reopened`) in `qunqin24/Pulse`, a workflow may post a triage comment. It does **not** run on comments, edits, labels, closes, reviews, or manual `workflow_dispatch`.

Pull requests are ignored unless `pull_request.base.repo.full_name` is `qunqin24/Pulse`. Any base **branch** is allowed. PRs **authored** by `qunqin24` (case-insensitive login) are ignored in every job; this uses `pull_request.user.login`, **not** `github.actor`, `sender`, or the head-repo owner. The owner’s **issues** are still triaged.

The comment is posted as **`github-actions[bot]`**. No GitHub App is required.

It does **not** write code, push branches, add labels, close threads, submit reviews, or merge. There is no auto-merge of its own output.

## Default off

Repo variable **`OPENCODE_BOT_ENABLED`** must be `true` or jobs no-op. Unset or any other value means **disabled** (the safe default).

Setting it to false stops **future** runs. Cancel **in-flight** Actions by hand in the Actions UI.

## Model and search

- Provider: OpenCode Go subscription (`opencode-go/glm-5.3-flash`).
- CLI pin: npm package `opencode-ai` **1.18.29** (see `.github/opencode/package-lock.json`).
- Builtin web search via Exa: `OPENCODE_WEBSEARCH_PROVIDER=exa`. See [OpenCode tools](https://opencode.ai/docs/tools/).
- API secret: **`OPENCODE_API_KEY`** (GitHub Actions secret).
- Child flags (in addition to `opencode --pure`): `OPENCODE_DISABLE_DEFAULT_PLUGINS=1`, `OPENCODE_DISABLE_EXTERNAL_SKILLS=1`, `OPENCODE_DISABLE_LSP_DOWNLOAD=1`, `OPENCODE_AUTO_SHARE=0`.

The Go model and Exa both **receive issue/PR text and search queries**. Treat that as leaving GitHub. Builtin search has **no** guaranteed query quota and **no** secret filter.

## Three jobs

Concurrency is **per target** (this issue or this PR), not one global group that would cancel unrelated pending work.

Checkout (collect and publish only) uses **`github.workflow_sha`** (the default-branch workflow commit for `pull_request_target`). Never PR head, never `github.sha`, never a mutable `main` ref checkout. `persist-credentials: false`. Analyze does **not** check out the repository.

1. **collect** — read-only GitHub API. Public, bounded metadata; for PRs, bounded patches. Does not check out the PR branch. Does not execute PR content. Uploads `triage-tools` (staged allowlist under `trusted-tools/` with hidden files) **before** the API collect step. Writes `disposition=analyze|skip` to `GITHUB_OUTPUT`. For PRs, `GET /pulls/N` **before and after** the files list must match the event head SHA, base ref, base repo, author, and `open`; mismatch is a successful **skip** (no input, no model, no comment). API failure leaves disposition unset so publish can use the fixed failure path.
2. **analyze** — `permissions: {}`. Runs only when `disposition == 'analyze'`. **No checkout.** Downloads `triage-tools` and executes only those trusted paths. Child environment has **no** `GITHUB_TOKEN`.
3. **publish** — `contents: read`, `issues: write`, `pull-requests: read` (not write). Runs on `always() && !cancelled()` when eligible and `disposition != 'skip'` (missing disposition is not skip). Before any comment it **GET**s the PR again; identity mismatch is a silent skip; if the GET cannot verify, it fail-closes with **no** comment. Dedup uses a v2 marker derived only from trusted fields (`number`, `kind`, `action`, `headSHA`, hash of `baseRef`) — not raw untrusted text. Issue reruns of the same opened event dedup. `synchronize` with a new SHA posts; the same SHA does not. `reopened` with the same SHA is **one** extra comment; repeating reopen with that SHA dedups. Retargeting the same head onto another base is a different marker. A model result is used only when the collect artifact identity fully matches the event; otherwise the fixed failure text with the **same** marker.

GET-then-POST is not atomic. A narrow race can still duplicate or skip; that is documented, not a guarantee.

Timeouts apply, and analyze is **four model steps**. The child process must exit **0**; error events, failed tools, mixed sessions, or truncated NDJSON become the fixed failure result.

## Token boundary

GitHub has no “comment-only” token scope. `issues: write` is **technically broader** than posting a comment (it could label or close if a script asked). The boundary is the **trusted publisher script** (fixed endpoint, validation, sanitization, dedup) — not a promise from the token. Do not add other GitHub writes to that job.

## Artifacts and logs

Bounded, **validated** artifacts may be kept (~1 day): `triage-input`, `triage-tools`, `triage-result`. They must **not** include raw model transcripts or raw search logs. Exact size/retention: read the workflow.

## Secrets in the payload

Already-public issues and PRs can still contain **accidentally pasted secrets**. Warn reporters not to submit keys, cookies, or tokens. The bot does **not** promise comprehensive redaction.

**Never** put `OPENCODE_API_KEY` (or any secret) in chat, issues, or this repo. Configure only in the GitHub UI or locally with `gh secret set`.

## Cost and abuse

Public `issues` / `pull_request_target` events can trigger work. There is **no** hard daily cap in-repo. Rely on OpenCode Go quota alerts and provider caps. A flood of new issues/PRs is a cost and load risk.

## Mentions and failures

Necessary risk, a decision that needs a human, or a run failure: comment **`@qunqin24`** when publish can still run **and** current PR identity still verifies. If GitHub itself is down, that notice may never appear. Collect API failure (unset disposition) can still reach the fixed failure comment when identity verifies — not raw model or API errors. Skip and unverifiable GET never comment.

## Deploy

1. Human reviews and **merges** the workflow, scripts, pin, and prompt to the **default branch**. `pull_request_target` runs that default-branch workflow (`github.workflow_sha`), independent of the PR target branch. Nothing enables itself from a fork PR.
2. In the GitHub UI (or `gh secret set` / `gh variable set` on a trusted machine): set `OPENCODE_API_KEY`; set `OPENCODE_BOT_ENABLED=true` only when you intend to turn it on.
3. After enablement, a **separate live smoke test** on a throwaway new issue (then disable or ignore). Do not treat that as done until a person runs it.

## Verification

```bash
node --test .github/scripts/opencode-bot.test.mjs
```

Offline mocks. **Not** proof against GitHub or OpenCode live. No live model or API posting is claimed here.

## Operators

| Want | Do |
|---|---|
| Enable | Merge to the default branch, set secret, set `OPENCODE_BOT_ENABLED=true` |
| Disable later | Set the variable false; cancel running jobs in Actions |
| Rotate the key | GitHub UI / `gh secret set` only |
