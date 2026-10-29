import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount, type VueWrapper } from '@vue/test-utils';
import App from './App.vue';

const task = { id: 'task-1', title: 'Planejar a semana', completed: false, revision: 2 };
let streamController: ReadableStreamDefaultController<Uint8Array>;
let settleCreate: (() => void) | undefined;
let fetchMock: ReturnType<typeof vi.fn>;
let wrapper: VueWrapper | undefined;

function eventStream() {
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      streamController = controller;
      controller.enqueue(new TextEncoder().encode(`event: snapshot\ndata: ${JSON.stringify({ revision: 2, tasks: [task] })}\n\n`));
    },
  });
  return new Response(stream, { headers: { 'Content-Type': 'text/event-stream' } });
}

function setupFetch() {
  fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    if (url.endsWith('/api/tasks') && (!init?.method || init.method === 'GET')) {
      return new Response(JSON.stringify({ revision: 2, tasks: [task] }), { status: 200 });
    }
    if (url.endsWith('/api/events')) return eventStream();
    if (url.endsWith('/api/tasks') && init?.method === 'POST') {
      return await new Promise<Response>((resolve) => {
        settleCreate = () => resolve(new Response(JSON.stringify({ ...task, id: 'task-2', title: 'Comprar café' }), { status: 201 }));
      });
    }
    throw new Error(`Unexpected request: ${init?.method ?? 'GET'} ${url}`);
  });
  vi.stubGlobal('fetch', fetchMock);
}

async function mountConnected() {
  wrapper = mount(App);
  await vi.waitFor(() => expect(wrapper?.get('[role="status"]').text()).toContain('Sincronizado'));
  return wrapper;
}

describe('task interactions', () => {
  beforeEach(() => {
    sessionStorage.setItem('todo-agent-token', 'test-token');
    setupFetch();
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = undefined;
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('prevents duplicate create requests while the first request is pending', async () => {
    const app = await mountConnected();
    await app.get('input[aria-label="Nova tarefa"]').setValue('Comprar café');
    await app.get('.create-form').trigger('submit');
    await app.get('.create-form').trigger('submit');

    expect(fetchMock.mock.calls.filter(([url, init]) => String(url).endsWith('/api/tasks') && init?.method === 'POST')).toHaveLength(1);
    expect(app.get('button.add-button').attributes('disabled')).toBeDefined();

    settleCreate?.();
    await flushPromises();
    expect(app.text()).not.toContain('Comprar café');
  });

  it('disables an open edit when the SSE connection drops', async () => {
    const app = await mountConnected();
    await app.get('button[aria-label="Editar Planejar a semana"]').trigger('click');
    expect(app.get('input[aria-label="Editar Planejar a semana"]').attributes('disabled')).toBeUndefined();

    streamController.close();
    await vi.waitFor(() => expect(app.get('[role="status"]').text()).toContain('Reconectando'));
    expect(app.get('input[aria-label="Editar Planejar a semana"]').attributes('disabled')).toBeDefined();
    expect(app.get('button[aria-label="Salvar edição"]').attributes('disabled')).toBeDefined();
  });
});
