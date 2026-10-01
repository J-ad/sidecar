# Sidecar

A small local work dashboard for **Codex, Claude Code, and GitHub**. Rails + SQLite + Hotwire, with a little plain JavaScript. No TypeScript, Node application runtime or automatic thread merging. Optional click-to-generate AI reply drafts use an existing agent CLI login.

Sidecar keeps each source independent. Cards show a title, project/color, source status, next action, observation time, source evidence and a link or session identity where available. Search and source/project filters make the list smaller. Snooze, dismissal and manual corrections stay local. An agent finishing a response does **not** mark a task complete.

## Install and run

Requirements:

- Ruby >= 3.2 and Bundler 4; Ruby 4.0.5 / Bundler 4.0.13 were tested on macOS.
- Native gem build tools. Linux source builds may require SQLite development headers.
- Optional readers: an existing Codex CLI/runtime; Python >= 3.10 for the pinned Claude SDK; an already authenticated GitHub CLI (`gh`).

Use an existing Ruby/toolchain installation. Setup does not install global prerequisites or alter agent configurations.

```sh
git clone https://github.com/J-ad/sidecar.git
cd sidecar
ruby -v
bundle -v
bin/setup
bin/start
```

Open **http://127.0.0.1:47391/**. Stop with Ctrl-C. Use `PORT=47392 bin/start` for another port. Existing checkouts can keep their directory name.

`bin/setup` installs gems under `vendor/bundle`, copies the bundled Turbo asset, copies example config only when local config is absent, and prepares SQLite. No CDN is used. The app binds to loopback and checks host, remote IP and CSRF. It is a personal local app, not a network-facing multi-user service.

## Configure the readers

Edit ignored `config/panel.yml`, copied from [the example](config/panel.example.yml). Use exact project directories, explicit repository mappings, labels and HEX colors. Never put credentials in this file. Unconfigured readers show “Not connected”; partial coverage is a compact indicator with expandable details. Actual sync failures remain visible. Empty or unavailable data does not prove there is no work.

```yaml
projects:
  - id: example
    name: Example project
    color: '#4f46e5'
    repositories: [example/app]
    local_paths: [/absolute/path/to/your/project]
sources:
  codex:
    path: data/codex.json
    automatic: false
    python: python3
    binary: codex
  claude:
    path: data/claude.json
    automatic: false
    python: vendor/claude-sdk/bin/python
  github:
    path: data/github.json
    automatic: false
```

### Codex

Configure an existing CLI path in `sources.codex.binary` and Python 3, then set `automatic: true`. The helper uses standard-library Python and a short-lived [Codex app-server](https://developers.openai.com/codex/app-server) stdio process. It sends only initialize, state-DB-only lists and metadata reads for explicit configured projects. It does not start/resume conversations, start turns, log in, or edit settings.

Reads are bounded to the latest 20 active and 20 archived threads per project. Source-confirmed archived rows are retained but hidden. Separate-runtime coverage and live agent state remain unconfirmed. Codex may update its normal runtime SQLite/log files under its existing home; conversation APIs are read-only, but runtime startup is not guaranteed to make zero filesystem writes. A sandbox may require its normal approval mechanism for those writes. Never bypass denied access or inspect private undocumented stores.

### Claude Code / Desktop

Prefer an existing documented summary export if you have one. For supported local SDK history reads:

```sh
bin/setup-sessions
# Optionally: PYTHON=/path/to/existing/python3 bin/setup-sessions
```

This installs the pinned SDK in `vendor/claude-sdk`, not globally. Set exact project `local_paths`, keep `sources.claude.python` pointing to that environment, and opt in with `automatic: true`.

The reader uses [list_sessions / get_session_messages](https://code.claude.com/docs/en/agent-sdk/sessions), limited to 20 sessions per explicit project and excerpts from the first 20 messages. Session display titles and bounded excerpts are not AI task summaries or final-response evidence. [Desktop and CLI session lists differ](https://code.claude.com/docs/en/sessions); complete Desktop coverage is not guaranteed. This SDK exposes no archive flag, so archive state is labelled unknown rather than inferred from age, tag or idle status. Cards provide a copyable session ID and manual opening guidance; no Desktop URL scheme is invented.

Run `bin/sync-sessions` for an explicit refresh. The optional `bin/claude-event /absolute/path/data/claude.json` accepts supplied JSON from [official hooks](https://code.claude.com/docs/en/hooks). It never reads `transcript_path` or calls a model. Hooks are not installed automatically. Do not let a hook producer and SDK reader overwrite the same snapshot without a coordinated merging design.

### GitHub

Map explicit repositories, then run:

```sh
bin/sync-github
```

It uses existing `gh` authentication to read identity, PRs, review history and current-HEAD status checks. It never creates credentials, requests reviews, merges or writes remotely. Authored PRs and reviews requested from you are separate buckets. Recommendations distinguish waiting for a requested review from needing to request/re-request after checking history. CI is tied to the current commit; conflicts and unknown states are explicit.

Queries cover up to five repositories, bounded to 100 recently updated OPEN/MERGED PRs each. Review pagination affects confidence; team membership is not expanded. GitHub reads run manually via the command above, or every five minutes when `sources.github.automatic: true` is explicitly configured. Existing `gh` authentication is reused; no access is granted by Sidecar. The background worker also imports configured local snapshots. Failed reads preserve previous rows and their age.

## What needs you, and what is live?

Cards separate operational activity, action owner and one concrete next action. **Needs you** counts only grounded actions: fresh explicit agent input/approval or failure events, your requested PR reviews, current-HEAD CI failures/conflicts/review changes, verified review requests, and explicitly tracked production follow-up. Working/waiting appears next. Idle and unverified history is collapsed by default. Healthy partial coverage is not a sync error; capability limits and timestamps live in source details. Failed reads produce one source-health warning rather than making every task “failed.”

Plain session history never proves running or waiting. Codex's default isolated stdio reader cannot see another Desktop runtime's loaded status. Optional `sources.codex.transport: proxy` can use an already-running supported control server; only that server's explicit active/approval/input/idle/error status is used. Sidecar does not resume sessions to subscribe or automatically configure a daemon. If no shared server exists, those cards remain history-only.

For real Claude lifecycle signals, separately approve merging [the hook example](config/claude-hooks.example.json) into the chosen project's `.claude/settings.local.json`, substituting the actual checkout path and preserving existing hooks. Enable `sources.claude.events_path: data/claude-events.json` in Sidecar config. Notification types identify explicit permission/input requests; prompt/tool events indicate work; Stop means idle, not task complete. The event receiver never reads transcripts, stores supplied assistant/tool text, transmits data remotely, or answers approvals. Its event file contains only session/project identity, event/type, status and time. SDK history and events use separate files; event signals survive metadata refresh. Events are accepted only for explicitly configured project directories. Live claims expire after five minutes without a fresh signal, so a long silent operation becomes unverified rather than falsely live. No hooks are installed by setup.

GitHub operational recommendations require recent observations (one hour), current-commit CI and checked review history. Approval alone never means ready to merge: an exporter must explicitly verify the remaining merge gates. Merged items require user action only when follow-up is explicitly tracked, and that action persists until its stages are confirmed even if source data gets old. The “Track production follow-up” control creates that local intent.

## Updates and local actions

`bin/start` runs a polling thread inside the Rails process. Enabled local agent readers poll about every 60 seconds, even with the browser closed. Configured snapshots are imported too. Stopping Rails stops the worker. Login startup is optional and installed only by the explicit service command below. Use `WORK_PANEL_BACKGROUND=0 bin/start` for on-demand reads.

Visible pages check a local revision endpoint every 10 seconds and reload only after a change. Open details, focused inputs and unsaved form values pause reloads, including drafts after blur and editing/navigation during a pending request. This is polling, not a pushed event stream. No system notification permission is requested. Faster official lifecycle hooks, watchers on approved export files, or opt-in attention notifications can be added separately; do not watch private undocumented agent stores.

Manual corrections are overlays preserved across imports. Snooze lasts 24 hours. Dismissal is reversible and local. Source archive, idle, stale, dismissal and task completion are independent facts. Only an explicit source `archived: true` hides an agent thread; unknown archive state stays unknown.

When production follow-up is explicitly tracked after merge, **deployed**, **rake task run / not applicable**, and **effect verified** remain separate manual confirmations requiring evidence. Imports preserve them. Unfinished production follow-up stays visible even after snooze/dismiss. Sidecar never deploys or runs production commands.

## Snapshot contract

Approved exporters can write configured source files. `bundle exec rake panel:refresh` imports snapshots only. The UI's **Refresh sources** also runs opted-in local readers. This is a technical example, not demo work loaded by the app:

```json
{
  "version": 1,
  "source": "codex",
  "state": "unknown",
  "complete": false,
  "observed_at": "2026-10-01T07:00:00Z",
  "message": "Selected export scope",
  "items": [{
    "id": "stable-source-id",
    "title": "Source title",
    "repository": "example/app",
    "cwd": "/absolute/path/to/your/project",
    "status": "unknown",
    "updated_at": "2026-10-01T06:55:00Z",
    "url": "https://example.com/source",
    "evidence": "Source excerpt or existing summary",
    "facts": {"archived": false, "agent_finished": null, "task_completed": null}
  }]
}
```

Sources: `codex`, `claude`, `github`. States: `ok`, `unknown` (including partial coverage), `unavailable`. Set `complete: true` only for verified complete scope. Missing rows from complete snapshots are flagged, never deleted. Limits: 5 MB / 1000 rows. IDs are unique per source. Times are ISO8601; optional row `observed_at` prevents refreshing unrelated observations. Invalid imports roll back; older observations cannot replace newer facts. Unavailable snapshots cannot contain fresh rows. Local overlays and follow-up confirmations are retained.

GitHub facts include `bucket` (`mine` / `review_requested`), `merged`, `head_sha`, `ci_sha`, `ci`, `conflicts`, `requested_reviewers`, `review_history_checked`, `reviewed_sha`, `review_decision` and `draft`.

## Verification, privacy and agent setup

```sh
bundle exec rails test
bundle exec rails zeitwerk:check
# Optional developer check; Node is not needed to run Sidecar:
node --test test/auto_refresh_test.js test/pwa_test.js test/question_suggestions_test.js
```

Current release checks passed: 50 Rails tests, eleven client tests, Rails loading and HTTP rendering. Tests use separate `storage/test.sqlite3`. They cover atomic/partial imports, timestamps, failed-reader retention, explicit reader scope/cooldown, overlays, production evidence, review/CI rules, archive semantics, source/project/search filters, hidden views, revision reporting and CSRF. Client tests cover blurred drafts, asynchronous races, source navigation and untouched forms. macOS runtime and real local readers were tested. Linux lockfile platforms and portable setup paths are included; **Linux runtime tests have not been run**. HTTP checks are distinct from visual browser QA.

An agent can follow [the packaged setup/maintenance skill](skills/sidecar/SKILL.md). It resolves the checkout, checks prerequisites, installs locally, configures one source at a time and verifies honest coverage. The skill is not globally installed automatically; a separately installed copy needs the checkout location to find this README.

Local config, source snapshots, SQLite, logs, caches and installed dependencies are ignored and excluded from source packages. For a private backup, stop the server and copy `storage/development.sqlite3`, `config/panel.yml` and selected `data/` snapshots to a private destination. Share only audited source and generic examples. Optional AI/provider changes require a separate decision about credentials and private-data transmission.

## License

Sidecar's original source is [MIT licensed](LICENSE), copyright Jan Adamski. Third-party dependencies retain their own licenses; installed gems, SDKs and generated dependency assets are not distributed in this repository.

### Source filters and language

The English interface has All sources, Codex, Claude Code and GitHub buttons. Each button shows only its source and preserves search, project and snoozed/dismissed filters. Imported titles and summaries retain their original language. Slack is excluded from this release.

### Agent questions

The Agent questions page includes a guarded local request broker. A runtime integration must supply the actual owning connection before a question can be answered. Existing Desktop history readers do not provide that connection; replies remain disabled. Only explicit user-input requests are supported, never tool or permission approvals. Secret questions hand off to the original agent. Disconnected, expired or resolved requests cannot be sent, and uncertain deliveries are not retried automatically. AI suggestions are separate editable drafts, generated only after an explicit click for a verified pending non-secret request. They never send answers automatically.

## Install the app and login startup

Open **http://127.0.0.1:47391/**. In Chrome or Edge, use the address-bar install icon (or menu → Install Sidecar). In Safari on macOS, use File → Add to Dock. Browser support varies; a normal tab works too. Installing the PWA does not start the server. No notifications permission is requested.

The service worker caches only the static offline page and icons. Dashboard pages, questions, source data and reply payloads are never cached or queued. If the local server is unavailable, the installed app shows an explicit unavailable page instead of old private data. Changing the port creates a different browser origin; reinstall the app from the new address.

Using the existing Ruby that runs Sidecar:

```sh
PORT=47391 bin/service install
bin/service status
bin/service restart
bin/service uninstall
```

On macOS this generates a per-user `com.sidecar.local` LaunchAgent and starts it immediately, then at login. On Linux it generates a user `sidecar.service` systemd unit and enables it at login; systemd user services must be available. No root privileges or lingering are enabled. Linux execution is not tested. Generated files include the actual checkout/Ruby paths and stay outside Git. Moving the checkout or Ruby installation requires uninstalling and reinstalling the service.

Installation refuses to overwrite an existing service or use an occupied port. Stop only an identified existing Sidecar server before installation; never kill another application. `PORT` is configurable (1024–65535), binds only `127.0.0.1`, and the service uses the chosen port on every restart. Logs are local under `log/service.out.log` and `log/service.err.log` on macOS; on Linux use `journalctl --user -u sidecar.service`. Uninstalling stops only the installed service and preserves config, snapshots and SQLite.

### Headless reply suggestions

Default order: **Claude Code first, then Codex once** for ordinary authentication, quota, network, process or invalid-output failures. No fallback follows cancellation, secret input, access denial or safety restrictions. Each provider has a 30-second timeout; the two-attempt path is bounded to about 60 seconds. The draft identifies its actual provider and whether it was a fallback. Duplicate generation for a question is suppressed; cancellation kills only the dedicated drafting process group. Resolving/expiring/disconnecting the question discards its draft.

`Generate suggestion` sends only the exact question/options and optional user-entered relevant context (2,000 characters, 10 KB total). No session history, repo files or automatic context collection is added. The CLI uses its own existing login; Sidecar does not inspect/copy credentials, create API keys or use inherited API-key/provider-URL overrides. Model execution uses the provider cloud and existing subscription limits, not offline inference. Raw stderr is never persisted or displayed. Drafts stay in ignored local SQLite. The `Use draft` button fills empty reply fields only; edit and explicitly `Send reply` separately.

```yaml
suggestions:
  backend: claude
  fallback: codex
  claude_binary: claude
  codex_binary: codex
```

Check login with `claude auth status` or `codex login status` in your own terminal. Login is a separate user action, not performed by Sidecar. Binaries must support the flags used below; unsupported options fail closed rather than silently granting tools.

Claude uses [documented CLI flags](https://code.claude.com/docs/en/cli-reference): safe/restricted mode, an empty built-in tool list, denied MCP tools with an empty strict MCP configuration, disabled skills/hooks and no session persistence. Authentication remains available; `--bare` is deliberately avoided because it does not reuse subscription OAuth. Managed administrator policy remains authoritative.

Codex uses [non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode) in a temporary directory with `--no-daemon`, `--ephemeral`, ignored user config/rules, a read-only sandbox, no approvals, disabled shell/apps/plugins/hooks/memory/skills/multi-agent/web search, and no AGENTS.md bytes. Existing auth remains with the CLI. **The installed Codex CLI does not expose a verified switch removing every built-in tool.** This is the strongest supported isolation used here, not a claim of tool-free Codex. Set `fallback: null` if that capability gap is unacceptable.

Tests use a fake CLI and generic questions. No paid generation or private prompt transmission is performed by verification. A live suggestion remains untested until the user clicks Generate on a verified pending question. External Desktop reply routing is still unavailable without its owning connection; generating a fresh drafting session never answers the original session by itself.

### Todos

Open **Todos** in the workspace header for custom tasks, or choose **Add todo** on a Codex, Claude or GitHub item. Review the prefilled title/project/link and save. Each todo keeps its original source/title/ID/link as a durable reference. Source refresh, completion, dismissal, archive or removal does not change the todo's completion status or remove it. Todos support optional project assignment, editable HTTP(S)/Codex thread links, open/completed views, and explicit Complete/Reopen actions.

Notes use Rails Action Text with Trix (provided by the locked Rails dependencies), with formatting, links and local screenshot attachments. The separate checklist has actual checkboxes after saving; enter one task per line and prefix already-completed entries with `[x]`. Saving a checkbox or completing a todo affects only that todo. No todos are automatically sent to an agent or GitHub, and there is no delete action.

Use **Add screenshots**, drag an image into Notes, or paste an image clipboard item into the editor. PNG, JPEG, GIF and WebP are accepted up to 10 MB each. The server checks file bytes, sanitizes filenames and rich HTML, rejects unsupported attachments and does not fetch pasted URLs. Pasted web HTML keeps text/formatting without remote images. Upload failures prevent saving until the failed image is removed/retried. Chrome browser tests exercised the real Trix image clipboard-event handler, file upload, saved rendering and editing; native keyboard paste from the system clipboard and other browsers remain unverified.

Run `bin/setup` after updating: it copies the locked Trix JS/CSS into ignored local public assets and applies the additive Todos/Action Text/Active Storage migrations. No npm, TypeScript, cloud storage credentials, image-processing library or system installation is required. Active Storage uses local disk; its generic direct-upload/redirect routes are disabled in favor of loopback-only, CSRF-protected upload and signed image routes. Original images render without transformations or external analyzers.

Private backups must include the **whole `storage/` directory**, including `storage/.secret_key_base`, `storage/attachments/` and the SQLite database. The persisted signing secret keeps embedded images valid across restarts. Storage, logs, test/browser screenshots and generated assets are ignored; do not include them in source releases. Images uploaded before cancelling a form remain local as unattached blobs; there is no automatic purge of user data.

Todo verification: `bundle exec rails test test/todos_test.rb` and optional `node --test test/todos_client_test.js`. Optional real-browser check: run `test/todos_browser_test.js` with an existing Playwright module and Chromium (`PLAYWRIGHT_MODULE`, optional `TODOS_CHROMIUM_PATH`), against an isolated running checkout with automatic sources disabled (`TODOS_TEST_URL`, default loopback port 47392). It creates synthetic test todos/images only in that checkout; browser screenshots go to ignored `tmp/`. This is a developer check, not an application dependency. Rails integration follows the [official Action Text guide](https://guides.rubyonrails.org/action_text_overview.html) with a bounded local multipart upload adapter.
