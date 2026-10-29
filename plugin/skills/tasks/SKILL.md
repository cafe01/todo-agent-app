---
name: tasks
description: Work in the installed To Do Agent App when the user wants to open their task list, resume working on their tasks, or add, edit, complete or remove tasks there. Portuguese examples include “vamos trabalhar nas minhas tarefas” and “abra o To Do”.
---

Use this plugin's MCP tools to work on the same local application the user sees.

When starting or resuming, call `app_open`. Open its returned URL in the harness's embedded browser when available, otherwise its ordinary browser-opening capability. The URL includes a local session credential: pass it directly to the browser, do not quote it in the conversation or save it in documents. If this harness cannot open a browser, explain that limitation and use the packaged `bin/todo_agent_app url` command only if needed to recover the address.

Use `tasks_list` to inspect current tasks. Create, update and delete through the MCP tools. Before update/delete, use the task's current revision as `expectedRevision`. A conflict means the task changed: re-read it and reconcile the user's request before trying again. Do not retry an uncertain mutation blindly.

The UI updates itself after committed changes. You do not need to click its buttons, reload the page, inspect the user's screen or infer a selected task. Refer to tasks by their returned IDs. Opening the application does not authorize creating sample tasks or clearing existing ones.

Tasks persist outside the installed plugin folder. Closing the chat or browser leaves the local application and data available for the next session. This plugin uses the user's existing agent; it does not call an inference provider.
