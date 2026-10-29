# To Do Agent App

An experiment in local applications for agents people already use. A Codex plugin bundles a native Dart application, a Vue web interface, an MCP adapter and a skill. People and agents operate the same durable tasks, with live updates in the browser. No inference service or API key is included.

## Structure

- `server/`: Dart domain, application, SQLite repository, Dart Frog HTTP, MCP SDK adapter and local daemon lifecycle.
- `web/`: Vue 3 + TypeScript + Vite interface.
- `plugin/`: Codex manifest, MCP declaration and task skill.
- `scripts/`: native build, packaging, installation and integrated checks.
- `.github/workflows/`: checks and release artifacts.
- `docs/plan.md`: experiment scope, contracts and design.
- `docs/validation.md`: observed results and limits.

This standalone experiment does not contain or modify Lexos production code.

## Build

Development requires Dart 3.13+, Node 22.22.2+ (or a current supported Node LTS), npm and Python 3. Build on the target OS/architecture:

```sh
python3 scripts/build.py
```

The output is a relocatable marketplace archive in `dist/`, containing the native executable, its native libraries, compiled web assets and plugin metadata. Consumers do not need Dart, Flutter, Node or Python. Initial build targets: macOS arm64 and Linux x64. These are experimental unsigned packages.

## Install the compiled plugin

Download and verify the appropriate [release archive](https://github.com/cafe01/todo-agent-app/releases/latest) and its SHA-256 sidecar, then extract it to a durable folder. From a development checkout you can also use the built folder directly:

```sh
scripts/install-local.sh /absolute/path/to/todo-agent-app-0.1.1-macos-arm64
```

Equivalent commands, requiring only Codex:

```sh
codex plugin marketplace add /absolute/path/to/extracted-marketplace
codex plugin add todo-agent-app@todo-agent-app-lab
```

Start a fresh Codex conversation and say **“Vamos trabalhar nas minhas tarefas.”** The skill asks the MCP tool for the application URL and opens it using the harness's browser. Installation and MCP capabilities can require a fresh chat or app refresh; the current conversation is not assumed to hot-load them.

The local server starts on demand, serves only loopback, and survives closing a chat. User data is stored outside the plugin installation. `TODO_AGENT_APP_DATA` overrides the profile for tests. `bin/todo_agent_app stop` explicitly stops the local server without deleting tasks. Never share the URL fragment or runtime descriptor; they carry the local access credential.

## Development and validation

```sh
cd server && dart pub get && dart analyze && dart test
cd ../web && npm ci && npm run typecheck && npm test && npm run build
```

Full package and browser checks are described in `docs/validation.md`. The experiment demonstrates a native local plugin, not public plugin-directory approval or universal compatibility across agent platforms.

## Distribution

Pull requests and pushes run CI. Tags `v*` build platform archives and publish a GitHub release with checksums. The source checkout intentionally excludes binaries and runtime data; install the release archive, not `plugin/` by itself.

The packaging format follows the [official Codex plugin documentation](https://developers.openai.com/plugins/build/plugins). The stdio MCP bridge gives the harness a lifecycle entry point; it forwards to the same application HTTP API used by the web UI. This is an explicit experiment choice, not a requirement that every future app use stdio.
