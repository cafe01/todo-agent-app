import { computed, onScopeDispose, ref } from 'vue';
import { ApiError, TasksApi } from './api';
import { acceptSnapshot, parseSseFrames, snapshotFromSseFrame, type Task, type TaskSnapshot } from './contracts';

export function useTasks(api: TasksApi) {
  const snapshot = ref<TaskSnapshot | null>(null);
  const connected = ref(false);
  const error = ref('');
  const loading = ref(true);
  const pendingCreate = ref(false);
  const pendingTaskIds = ref(new Set<string>());
  let stopped = false;
  let streamController: AbortController | null = null;
  let reconnectTimer: ReturnType<typeof setTimeout> | undefined;
  let reconnectDelay = 500;

  function apply(next: TaskSnapshot) {
    snapshot.value = acceptSnapshot(snapshot.value, next);
  }

  async function reload() {
    try { apply(await api.snapshot()); }
    catch { /* The stream may recover first. Preserve the last known view. */ }
  }

  async function consume(signal: AbortSignal) {
    const response = await api.stream(signal);
    if (!response.ok || !response.body) throw new Error('O fluxo de atualizações não está disponível.');
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    try {
      while (!signal.aborted) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const parsed = parseSseFrames(buffer);
        buffer = parsed.remainder;
        for (const frame of parsed.frames) {
          const next = snapshotFromSseFrame(frame);
          if (next) {
            apply(next);
            connected.value = true;
            error.value = '';
          }
        }
      }
    } finally {
      reader.releaseLock();
    }
  }

  async function connect() {
    while (!stopped) {
      connected.value = false;
      streamController = new AbortController();
      const sessionStarted = Date.now();
      try { await consume(streamController.signal); }
      catch (cause) {
        if (!stopped) error.value = cause instanceof Error ? cause.message : 'Conexão interrompida.';
      }
      if (stopped) return;
      if (Date.now() - sessionStarted >= 30_000) reconnectDelay = 500;
      connected.value = false;
      await new Promise<void>((resolve) => {
        reconnectTimer = setTimeout(resolve, reconnectDelay + Math.random() * reconnectDelay * 0.2);
      });
      reconnectDelay = Math.min(reconnectDelay * 2, 10_000);
    }
  }

  void (async () => {
    await reload();
    loading.value = false;
    void connect();
  })();

  async function mutate(action: () => Promise<unknown>, taskId?: string) {
    if (!connected.value) return;
    if (taskId ? pendingTaskIds.value.has(taskId) : pendingCreate.value) return;
    error.value = '';
    if (taskId) pendingTaskIds.value = new Set(pendingTaskIds.value).add(taskId);
    else pendingCreate.value = true;
    try { await action(); }
    catch (cause) {
      if (cause instanceof ApiError && cause.status === 409) {
        await reload();
        error.value = 'Esta tarefa mudou em outro lugar. A lista foi atualizada; confira o estado atual e tente de novo.';
      } else {
        error.value = cause instanceof Error ? cause.message : 'Não foi possível salvar a alteração.';
      }
    } finally {
      if (taskId) {
        const next = new Set(pendingTaskIds.value);
        next.delete(taskId);
        pendingTaskIds.value = next;
      } else {
        pendingCreate.value = false;
      }
    }
  }

  const tasks = computed(() => snapshot.value?.tasks ?? []);
  function create(title: string) { return mutate(() => api.create(title)); }
  function update(task: Task, changes: { title?: string; completed?: boolean }) {
    return mutate(() => api.update(task, changes), task.id);
  }
  function remove(task: Task) { return mutate(() => api.delete(task), task.id); }

  onScopeDispose(() => {
    stopped = true;
    streamController?.abort();
    if (reconnectTimer) clearTimeout(reconnectTimer);
  });

  return { snapshot, tasks, connected, error, loading, pendingCreate, pendingTaskIds, create, update, remove };
}
