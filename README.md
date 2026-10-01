# Sidecar

A small local work dashboard for **Codex, Claude Code, and GitHub**. Rails + SQLite + Hotwire, with a little plain JavaScript. No TypeScript, Node application runtime, external model calls, or automatic thread merging.

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

Open **http://127.0.0.1:4317/**. Stop with Ctrl-C. Use `PORT=4318 bin/start` for another port. Existing checkouts can keep their directory name.

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

`bin/start` runs a polling thread inside the Rails process. Enabled local agent readers poll about every 60 seconds, even with the browser closed. Configured snapshots are imported too. Stopping Rails, logging out or restarting the machine stops the worker; no OS service or launch agent is installed. Restart with `bin/start`. Use `WORK_PANEL_BACKGROUND=0 bin/start` for on-demand reads.

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
node --test test/auto_refresh_test.js
```

Current release checks passed: 31 Rails tests / 147 assertions, six client tests, Rails loading and HTTP rendering. Tests use separate `storage/test.sqlite3`. They cover atomic/partial imports, timestamps, failed-reader retention, explicit reader scope/cooldown, overlays, production evidence, review/CI rules, archive semantics, source/project/search filters, hidden views, revision reporting and CSRF. Client tests cover blurred drafts, asynchronous races, source navigation and untouched forms. macOS runtime and real local readers were tested. Linux lockfile platforms and portable setup paths are included; **Linux runtime tests have not been run**. HTTP checks are distinct from visual browser QA.

An agent can follow [the packaged setup/maintenance skill](skills/sidecar/SKILL.md). It resolves the checkout, checks prerequisites, installs locally, configures one source at a time and verifies honest coverage. The skill is not globally installed automatically; a separately installed copy needs the checkout location to find this README.

Local config, source snapshots, SQLite, logs, caches and installed dependencies are ignored and excluded from source packages. For a private backup, stop the server and copy `storage/development.sqlite3`, `config/panel.yml` and selected `data/` snapshots to a private destination. Share only audited source and generic examples. Optional AI/provider changes require a separate decision about credentials and private-data transmission.

## License

Sidecar's original source is [MIT licensed](LICENSE), copyright Jan Adamski. Third-party dependencies retain their own licenses; installed gems, SDKs and generated dependency assets are not distributed in this repository.

### Source filters and language

The English interface has All sources, Codex, Claude Code and GitHub buttons. Each button shows only its source and preserves search, project and snoozed/dismissed filters. Imported titles and summaries retain their original language. Slack is excluded from this release.

### Agent questions

The Agent questions page includes a guarded local request broker. A runtime integration must supply the actual owning connection before a question can be answered. Existing Desktop history readers do not provide that connection; replies remain disabled. Only explicit user-input requests are supported, never tool or permission approvals. Secret questions hand off to the original agent. Disconnected, expired or resolved requests cannot be sent, and uncertain deliveries are not retried automatically. No LLM suggestions or model calls are enabled.
