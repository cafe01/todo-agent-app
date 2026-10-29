# To Do Agent App — experiment design

## Outcome
Install a local Codex plugin; ask to work on tasks; its skill obtains an application URL and opens the web UI. Human HTTP commands and agent MCP commands change one durable application. The UI receives changes without reload. Closing a chat does not erase tasks or terminate the application. No shared cursor/selection or inference service.

## Design
Standalone public repository, unrelated to production data. `server/` is a Dart package, `web/` Vue 3 + TypeScript + Vite. `plugin/` is the plugin source. `scripts/` builds and assembles a distributable marketplace containing native executable, compiled web assets, manifest and skill. GitHub Actions builds/tests release archives. Initial distribution is macOS arm64 and Linux x64; other targets require proof.

Dart Frog HTTP, mcp_dart SDK stdio adapter, SQLite persistence. A stdio bridge starts or discovers a detached local daemon and calls its authenticated HTTP API. This deliberately adapts the proposed Lexos Streamable HTTP boundary to Codex's bundled stdio server startup; business operations remain application use cases, never MCP-owned state. No hand-coded MCP protocol.

`server/lib/domain/`: immutable Task, validation and application error. `application/`: use cases plus repository port; no HTTP/MCP/SQL imports. `infrastructure/`: SQLite implementation. `adapters/`: HTTP and MCP codecs and handlers. `runtime/`: daemon ownership, credentials and lifecycle. `bin/todo_agent_app.dart`: thin command entrypoint.

Task: id UUID, title trimmed 1–200 characters, completed bool, revision integer. Snapshot: `{revision: int, tasks: Task[]}` ordered by creation. Global revision increments once per committed mutation. Commands create(title), update(id,title?,completed?,expectedRevision), delete(id,expectedRevision). Stale task revision -> conflict; invalid -> invalidInput; missing -> notFound. No bulk delete or automatic mutation retry. Repository transaction commits before change event; no event for failed writes.

HTTP: GET /health public only app identity/version; GET /api/tasks snapshot; POST /api/tasks {title} -> 201 Task; PATCH /api/tasks/:id -> Task; DELETE /api/tasks/:id with JSON expectedRevision -> 204. Errors `{error:{code,message}}` with 400/404/409. GET /api/events SSE emits `event: snapshot` with complete snapshot on connect and after every commit, plus heartbeat. Full snapshots simplify reconnection and avoid lost replay history. Subscribe before initial read; browser discards older revisions. Frontend uses fetch streaming with bearer auth, reconnect backoff, disables mutations while disconnected, preserves last snapshot with disconnected status. No optimistic success.

Bind 127.0.0.1 only, random port; bearer token on every /api route. Reject foreign Origin and unexpected Host. Browser bootstrap URL `http://127.0.0.1:PORT/#token=TOKEN`; frontend puts token in sessionStorage then strips fragment. Token never in HTTP query or logs. Assets served from web/ beside packaged executable. Data outside plugin cache, default platform user data directory `todo-agent-app`, override TODO_AGENT_APP_DATA for tests. Owner-only directory/descriptor, exclusive profile file lock, descriptor contains port/token/pid/version. Probe authenticated API before reusing. Race-safe launch: competing daemon cannot open DB. Stale descriptor replaced only after acquiring lock. App survives bridge EOF; explicit CLI stop ends own verified daemon. Daemon signals close listeners, database, descriptor and lock.

CLI: `serve`, `mcp`, `url`, `stop`; `--data PATH` and `--web PATH` override defaults. `url` ensures daemon then prints bootstrap URL. `mcp` ensures daemon then serves SDK tools: app_open -> {url}; tasks_list -> snapshot; tasks_create; tasks_update; tasks_delete. SDK annotations accurately mark read/write operations. Errors use isError and structured code. mcp stdout strictly protocol.

## Delivery and checks
1. Backend domain/application tests first, repository persistence/conflict tests; HTTP + SDK client tests across shared state, SSE, auth, restart, ownership.
2. Vue UI task CRUD, visible connection state, streaming snapshots; typecheck/build and automated browser integration against real backend.
3. Package release with executable + assets. Verify relocated package with no Dart/Node needed, and startup through stdio MCP. Install through real Codex marketplace tooling; test discovery in fresh harness session, record desktop observation limits.
4. Public GitHub repo and CI/release workflow. Publish only experiment files, never portfolio code, private documents or runtime data.

## Sources and decisions
- Codex packaging: https://developers.openai.com/plugins/build/plugins (read 2026-10-29). Portable plugin.json and mcp.json with a contained executable path are used for the current local client; local marketplace install is distinct from public directory submission.
- Technology choices follow existing Lexos 032 design, but this standalone experiment does not migrate Lexos or alter its specs.
