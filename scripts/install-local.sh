#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
  echo 'Usage: scripts/install-local.sh /absolute/path/to/extracted-marketplace' >&2
  exit 64
fi
marketplace=$(cd "$1" && pwd)
test -f "$marketplace/.agents/plugins/marketplace.json"
if message=$(codex plugin marketplace add "$marketplace" 2>&1); then
  printf "%s\n" "$message"
else
  case "$message" in
    *"already added from a different source"*)
      codex plugin marketplace remove todo-agent-app-lab
      codex plugin marketplace add "$marketplace"
      ;;
    *) printf "%s\n" "$message" >&2; exit 1 ;;
  esac
fi
codex plugin add todo-agent-app@todo-agent-app-lab
