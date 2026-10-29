export interface Task {
  id: string;
  title: string;
  completed: boolean;
  revision: number;
}

export interface TaskSnapshot {
  revision: number;
  tasks: Task[];
}

export function isTaskSnapshot(value: unknown): value is TaskSnapshot {
  if (typeof value !== 'object' || value === null) return false;
  const snapshot = value as Record<string, unknown>;
  return Number.isInteger(snapshot.revision) && Array.isArray(snapshot.tasks) && snapshot.tasks.every((item) => {
    if (typeof item !== 'object' || item === null) return false;
    const task = item as Record<string, unknown>;
    return typeof task.id === 'string' && typeof task.title === 'string' &&
      typeof task.completed === 'boolean' && Number.isInteger(task.revision);
  });
}

export function acceptSnapshot(current: TaskSnapshot | null, next: TaskSnapshot): TaskSnapshot {
  return current && next.revision < current.revision ? current : next;
}

/** Parse complete SSE frames; a trailing partial frame is retained for the next chunk. */
export function parseSseFrames(buffer: string): { frames: string[]; remainder: string } {
  const normalized = buffer.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const parts = normalized.split('\n\n');
  return { frames: parts.slice(0, -1), remainder: parts.at(-1) ?? '' };
}

export function snapshotFromSseFrame(frame: string): TaskSnapshot | null {
  let event = 'message';
  const data: string[] = [];
  for (const line of frame.split('\n')) {
    if (!line || line.startsWith(':')) continue;
    const colon = line.indexOf(':');
    const field = colon < 0 ? line : line.slice(0, colon);
    let value = colon < 0 ? '' : line.slice(colon + 1);
    if (value.startsWith(' ')) value = value.slice(1);
    if (field === 'event') event = value;
    if (field === 'data') data.push(value);
  }
  if (event !== 'snapshot' || data.length === 0) return null;
  try {
    const parsed: unknown = JSON.parse(data.join('\n'));
    return isTaskSnapshot(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

export function bootstrapToken(): string | null {
  const params = new URLSearchParams(window.location.hash.slice(1));
  const token = params.get('token');
  if (token) {
    window.sessionStorage.setItem('todo-agent-token', token);
    window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}`);
    return token;
  }
  return window.sessionStorage.getItem('todo-agent-token');
}
