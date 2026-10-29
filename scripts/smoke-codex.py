#!/usr/bin/env python3
"""Opt-in read-only check of the installed plugin through a fresh Codex session."""
import argparse
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--approve-read-tools', action='store_true', help='Permit app_open and tasks_list only for this test process')
parser.add_argument('--plugin-root', type=Path, required=True, help='Installed plugin root returned by codex plugin add')
parser.add_argument('--model', default='gpt-6-luna')
args = parser.parse_args()
if not args.approve_read_tools:
    parser.error('This test needs explicit --approve-read-tools; no persistent permissions are changed.')
skill = args.plugin_root.resolve() / 'skills/tasks/SKILL.md'
if not skill.is_file():
    parser.error(f'Skill not found: {skill}')
command = ['codex', 'exec', '--ephemeral', '--json', '-m', args.model,
           '-c', 'model_reasoning_effort=low']
for tool in ('app_open', 'tasks_list'):
    command += ['-c', f'plugins.todo-agent-app@todo-agent-app-lab.mcp_servers.todo.tools.{tool}.approval_mode="approve"']
command += [f'Read the installed skill at {skill}. Validate this installed plugin using its MCP tools app_open and tasks_list. Do not mutate data or files, execute the app through shell, or open a browser in this CLI smoke test. Do not print URLs or credentials. Report success and the task count.']
result = subprocess.run(command, capture_output=True, text=True, timeout=120)
observed = {}
for line in result.stdout.splitlines():
    try:
        event = json.loads(line)
    except ValueError:
        continue
    item = event.get('item', {})
    if event.get('type') == 'item.completed' and item.get('type') == 'mcp_tool_call' and item.get('server') == 'todo':
        observed[item.get('tool')] = item.get('status')
print(json.dumps({'tools': observed, 'exitCode': result.returncode}, indent=2))
if result.returncode or any(observed.get(t) != 'completed' for t in ('app_open', 'tasks_list')):
    raise SystemExit('Installed-plugin smoke test failed; tool output is withheld because app_open carries a local credential.')
