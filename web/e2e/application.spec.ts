import { test, expect } from '@playwright/test';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { mkdtemp, rm, cp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

test('installed native bundle shares durable tasks between browser and MCP', async ({ page, context }) => {
  test.setTimeout(90_000);
  const original = process.env.TODO_APP_BINARY;
  if (!original) throw new Error('Set TODO_APP_BINARY to the packaged native executable.');
  const temporary = await mkdtemp(join(tmpdir(), 'todo-agent-e2e-'));
  const profile = join(temporary, 'profile');
  // Relocate all native assets and UI. PATH intentionally excludes developer SDKs.
  const bundle = join(temporary, 'relocated plugin');
  await cp(resolve(dirname(original), '..'), bundle, { recursive: true });
  const binary = join(bundle, 'bin', 'todo_agent_app');
  const env = { ...process.env, PATH: '/usr/bin:/bin', TODO_AGENT_APP_DATA: profile } as Record<string, string>;
  let client: Client | undefined;
  async function connect() {
    client = new Client({ name: 'todo-package-e2e', version: '1.0.0' });
    await client.connect(new StdioClientTransport({ command: binary, args: ['mcp'], env, stderr: 'pipe' }));
  }
  async function tool(name: string, args: Record<string, unknown> = {}) {
    const result = await client!.callTool({ name, arguments: args });
    if (result.isError) throw new Error(JSON.stringify(result));
    return result.structuredContent as Record<string, any>;
  }
  try {
    await connect();
    const names = (await client!.listTools()).tools.map((t) => t.name);
    expect(names).toEqual(expect.arrayContaining(['app_open', 'tasks_list', 'tasks_create', 'tasks_update', 'tasks_delete']));
    const opened = await tool('app_open');
    const url = new URL(opened.url);
    const token = new URLSearchParams(url.hash.slice(1)).get('token')!;
    const endpoint = new URL('/api/tasks', url).href;
    expect((await fetch(endpoint)).status).toBe(401);
    expect((await fetch(endpoint, { headers: { Authorization: `Bearer ${token}`, Origin: 'https://untrusted.example' } })).status).toBe(403);
    await page.goto(opened.url);
    await expect(page.getByRole('status')).toHaveText('Sincronizado');
    expect(page.url()).not.toContain('token=');

    const created = await tool('tasks_create', { title: 'Preparar a reunião' });
    await expect(page.locator('.task-title')).toHaveText('Preparar a reunião');
    await page.getByRole('textbox', { name: 'Nova tarefa' }).fill('Revisar o contrato');
    await page.getByRole('button', { name: 'Adicionar', exact: true }).click();
    await expect(page.locator('.task-row')).toHaveCount(2);
    let snapshot = await tool('tasks_list');
    expect(snapshot.tasks.map((t: any) => t.title)).toEqual(['Preparar a reunião', 'Revisar o contrato']);

    await page.getByRole('button', { name: 'Concluir Preparar a reunião', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Marcar Preparar a reunião como pendente' })).toBeVisible();
    snapshot = await tool('tasks_list');
    const completed = snapshot.tasks.find((t: any) => t.id === created.id);
    expect(completed.completed).toBe(true);
    const conflict = await client!.callTool({ name: 'tasks_update', arguments: { id: created.id, title: 'Stale overwrite', expectedRevision: created.revision } });
    expect(conflict.isError).toBe(true);
    const edited = await tool('tasks_update', { id: completed.id, title: 'Reunião preparada', expectedRevision: completed.revision });
    await expect(page.getByText('Reunião preparada', { exact: true })).toBeVisible();
    await tool('tasks_delete', { id: edited.id, expectedRevision: edited.revision });
    await expect(page.locator('.task-row')).toHaveCount(1);

    // The browser remains operational after the agent connection closes.
    await client!.close(); client = undefined;
    await page.getByRole('button', { name: 'Editar Revisar o contrato', exact: true }).click();
    await page.getByRole('textbox', { name: 'Editar Revisar o contrato' }).fill('Revisar contrato amanhã');
    await page.getByRole('button', { name: 'Salvar edição' }).click();
    await expect(page.getByText('Revisar contrato amanhã', { exact: true })).toBeVisible();
    await page.reload();
    await expect(page.getByRole('status')).toHaveText('Sincronizado');
    await expect(page.locator('.task-title')).toHaveText('Revisar contrato amanhã');

    await connect();
    const resumed = await tool('app_open');
    expect(new URL(resumed.url).origin).toBe(url.origin);
    await page.screenshot({ path: 'test-results/todo-desktop.png', fullPage: true });
    await page.setViewportSize({ width: 390, height: 844 });
    await expect(page.locator('body')).toHaveJSProperty('scrollWidth', 390);
    await page.screenshot({ path: 'test-results/todo-mobile.png', fullPage: true });
    await client!.close(); client = undefined;
    execFileSync(binary, ['stop'], { env, timeout: 10_000 });
    await expect(page.getByRole('status')).toHaveText('Reconectando');
    await expect(page.getByRole('button', { name: 'Adicionar', exact: true })).toBeDisabled();
    await expect(page.locator('.task-title')).toHaveText('Revisar contrato amanhã');

    await connect();
    const restarted = await tool('app_open');
    await context.clearCookies();
    await page.goto(restarted.url);
    await expect(page.getByRole('status')).toHaveText('Sincronizado');
    await expect(page.locator('.task-title')).toHaveText('Revisar contrato amanhã');
    expect((await tool('tasks_list')).tasks).toHaveLength(1);
  } finally {
    await client?.close();
    try { execFileSync(binary, ['stop'], { env, timeout: 10_000, stdio: 'ignore' }); } catch { /* Already stopped. */ }
    await rm(temporary, { recursive: true, force: true });
  }
});
