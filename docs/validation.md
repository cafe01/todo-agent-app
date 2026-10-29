# Experiment validation

Candidate: 0.1.0, 29 October 2026. This file distinguishes the application/package proof from the Codex host and distribution proof.

## Passed locally (macOS arm64)

- Dart analysis and 12 backend tests: domain validation, SQLite transactions and persistence, stale revisions, HTTP authorization/CRUD/SSE, MCP SDK client round trip, concurrent daemon startup, exclusive profile ownership, clean restart and recovery after SIGKILL.
- Vue typecheck, five unit/component tests, production build; `npm audit` reports zero vulnerabilities.
- Native build through `dart build cli`, including SQLite's native library; no Dart/Flutter/Node runtime required by the installed application.
- Playwright + Node MCP SDK against a relocated native bundle, with developer runtimes absent from its PATH. Exercises agent create, human create/complete/edit, agent read/update/delete, stale-write rejection, immediate browser updates, missing-token and foreign-Origin rejection, chat closure independence, page reload, disconnect UI and durable restart.
- Desktop and 390px mobile screenshots inspected; no horizontal overflow.
- Codex marketplace registration and installation to its plugin cache. Portable `plugin.json` + `mcp.json` with contained `./bin/todo_agent_app` command loads all five MCP tools.

## Host and release validation

Fresh Codex CLI read-only smoke test and GitHub CI results will be recorded after completion. CLI requires approval policy for a newly installed plugin; Café authorized app_open and tasks_list only for the test invocation, with no persistent policy change.

## Reproduce

```sh
(cd server && dart pub get && dart analyze --fatal-infos && dart test)
(cd web && npm ci && npm run typecheck && npm test)
python3 scripts/build.py
cd web
TODO_APP_BINARY="/absolute/path/to/marketplace/plugins/todo-agent-app/bin/todo_agent_app" npm run test:e2e
```

Playwright needs its test browser (`npx playwright install chromium`) on the developer/CI machine only. Screenshots are emitted to `web/test-results/`. Each E2E test uses an isolated temporary profile and removes it afterward.

## Deliberate limits

- This is an unsigned experiment, not a signed/notarized commercial installer or a public plugin-directory submission.
- No Windows build or other agent-harness compatibility is claimed.
- A new daemon gets a fresh port and credential. After a daemon restart, use app_open again; a browser tab with the old URL cannot discover the new listener by itself. Connection retry covers interruptions while the same listener is alive.
- Commands are not automatically retried after uncertain responses. Durable idempotency receipts are outside this tiny task domain experiment.
- Plugin updates do not yet negotiate replacement of an already running daemon. Stop the current daemon before updating the experimental package.
- The skill uses whichever browser-opening capability the harness provides. The current chat does not hot-load newly installed MCP tools; natural skill routing in a fresh desktop chat remains distinct from the automated SDK/browser proof.
