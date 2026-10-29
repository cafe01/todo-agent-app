#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
  echo 'Usage: scripts/install-local.sh /absolute/path/to/extracted-marketplace' >&2
  exit 64
fi
marketplace=$(cd "$1" && pwd)
test -f "$marketplace/.agents/plugins/marketplace.json"
codex plugin marketplace add "$marketplace"
codex plugin add todo-agent-app@todo-agent-app-lab
