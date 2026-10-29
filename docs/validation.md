# Experiment validation

Candidate: 0.1.1, 29 October 2026. Version 0.1.1 fixes the lifecycle test harness to launch a precompiled executable, avoiding concurrent Dart native-hook preparation on macOS; application behavior is unchanged. This file distinguishes the application/package proof from the Codex host and distribution proof.

## Passed locally (macOS arm64)

- Dart analysis and 12 backend tests: domain validation, SQLite transactions and persistence, stale revisions, HTTP authorization/CRUD/SSE, MCP SDK client round trip, concurrent daemon startup, exclusive profile ownership, clean restart and recovery after SIGKILL.
- Vue typecheck, five unit/component tests, production build; `npm audit` reports zero vulnerabilities.
- Native build through `dart build cli`, including SQLite's native library; no Dart/Flutter/Node runtime required by the installed application.
- Playwright + Node MCP SDK against a relocated native bundle, with developer runtimes absent from its PATH. Exercises agent create, human create/complete/edit, agent read/update/delete, stale-write rejection, immediate browser updates, missing-token and foreign-Origin rejection, chat closure independence, page reload, disconnect UI and durable restart.
- Desktop and 390px mobile screenshots inspected; no horizontal overflow.
- Codex marketplace registration and installation to its plugin cache. Portable `plugin.json` + `mcp.json` with contained `./bin/todo_agent_app` command loads all five MCP tools.

## Host and release validation

A fresh Codex CLI 0.162.1 session read the installed skill and successfully called both app_open and tasks_list (zero tasks in the new default profile). Only these two tools received temporary per-invocation approval, explicitly authorized by Café; no persistent policy changed. The executable was loaded from the Codex plugin cache, not launched through shell by the agent.

GitHub Actions [run 40895396551](https://github.com/cafe01/todo-agent-app/actions/runs/40895396551) passed on both macOS arm64 and Ubuntu Linux x64: backend tests, frontend tests, native packaging and the full relocated MCP/browser E2E. Each platform uploaded its archive, checksum and screenshots.

Release [v0.1.1](https://github.com/cafe01/todo-agent-app/releases/tag/v0.1.1) was published automatically by [run 40896928482](https://github.com/cafe01/todo-agent-app/actions/runs/40896928482), after all checks and relocated-package E2E passed on both platforms. The installed 0.1.1 plugin also passed the fresh Codex smoke script.

## Reproduce

```sh
(cd server && dart pub get && dart analyze --fatal-infos && dart test)
(cd web && npm ci && npm run typecheck && npm test)
python3 scripts/build.py
cd web
TODO_APP_BINARY="/absolute/path/to/marketplace/plugins/todo-agent-app/bin/todo_agent_app" npm run test:e2e
```

The optional `scripts/smoke-codex.py --approve-read-tools --plugin-root /path/returned/by/plugin-install` reproduces the fresh harness check, consumes a model invocation, and reports only tool statuses (no credential-bearing URL).

Playwright needs its test browser (`npx playwright install chromium`) on the developer/CI machine only. Screenshots are emitted to `web/test-results/`. Each E2E test uses an isolated temporary profile and removes it afterward.

## Deliberate limits

- This is an unsigned experiment, not a signed/notarized commercial installer or a public plugin-directory submission.
- No Windows build or other agent-harness compatibility is claimed.
- A new daemon gets a fresh port and credential. After a daemon restart, use app_open again; a browser tab with the old URL cannot discover the new listener by itself. Connection retry covers interruptions while the same listener is alive.
- Commands are not automatically retried after uncertain responses. Durable idempotency receipts are outside this tiny task domain experiment.
- Plugin updates do not yet negotiate replacement of an already running daemon. Stop the current daemon before updating the experimental package.
- The skill uses whichever browser-opening capability the harness provides. The current chat does not hot-load newly installed MCP tools; natural skill routing in a fresh desktop chat remains distinct from the automated SDK/browser proof.
