import type { Task, TaskSnapshot } from './contracts';

export class ApiError extends Error {
  constructor(message: string, readonly status: number, readonly code?: string) {
    super(message);
    this.name = 'ApiError';
  }
}

export class TasksApi {
  constructor(private readonly token: string, private readonly baseUrl = '') {}

  private async request(path: string, init: RequestInit = {}): Promise<Response> {
    const response = await fetch(`${this.baseUrl}/api${path}`, {
      ...init,
      headers: {
        Authorization: `Bearer ${this.token}`,
        ...(init.body ? { 'Content-Type': 'application/json' } : {}),
        ...init.headers,
      },
    });
    if (!response.ok) {
      let message = 'Não foi possível concluir a ação.';
      let code: string | undefined;
      try {
        const body = await response.json() as { error?: { message?: string; code?: string } };
        message = body.error?.message ?? message;
        code = body.error?.code;
      } catch { /* Keep the fallback message. */ }
      throw new ApiError(message, response.status, code);
    }
    return response;
  }

  async snapshot(): Promise<TaskSnapshot> {
    return await (await this.request('/tasks')).json() as TaskSnapshot;
  }

  async create(title: string): Promise<Task> {
    return await (await this.request('/tasks', { method: 'POST', body: JSON.stringify({ title }) })).json() as Task;
  }

  async update(task: Task, changes: { title?: string; completed?: boolean }): Promise<Task> {
    return await (await this.request(`/tasks/${encodeURIComponent(task.id)}`, {
      method: 'PATCH', body: JSON.stringify({ ...changes, expectedRevision: task.revision }),
    })).json() as Task;
  }

  async delete(task: Task): Promise<void> {
    await this.request(`/tasks/${encodeURIComponent(task.id)}`, {
      method: 'DELETE', body: JSON.stringify({ expectedRevision: task.revision }),
    });
  }

  stream(signal: AbortSignal): Promise<Response> {
    return fetch(`${this.baseUrl}/api/events`, {
      headers: { Authorization: `Bearer ${this.token}`, Accept: 'text/event-stream' },
      signal,
    });
  }
}
