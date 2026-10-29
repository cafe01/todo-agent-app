import { describe, expect, it } from 'vitest';
import { acceptSnapshot, parseSseFrames, snapshotFromSseFrame, type TaskSnapshot } from './contracts';

const current: TaskSnapshot = { revision: 8, tasks: [{ id: 'a', title: 'Rascunho', completed: false, revision: 3 }] };

describe('snapshot stream contracts', () => {
  it('waits for a complete frame when the stream splits a snapshot across chunks', () => {
    const first = parseSseFrames('event: snapshot\ndata: {"revision":9,');
    expect(first.frames).toEqual([]);
    const second = parseSseFrames(`${first.remainder}\ndata: "tasks":[]}\n\n: heartbeat\n\n`);
    expect(second.frames).toHaveLength(2);
    expect(snapshotFromSseFrame(second.frames[0])).toEqual({ revision: 9, tasks: [] });
    expect(snapshotFromSseFrame(second.frames[1])).toBeNull();
  });

  it('accepts only valid snapshot events and ignores malformed data', () => {
    expect(snapshotFromSseFrame('event: update\ndata: {"revision":9,"tasks":[]}')).toBeNull();
    expect(snapshotFromSseFrame('event: snapshot\ndata: nope')).toBeNull();
    expect(snapshotFromSseFrame('event: snapshot\ndata: {"revision":9,"tasks":[{"id":"a"}]}')).toBeNull();
  });

  it('discards stale snapshots after a reconnect while accepting newer full state', () => {
    const stale: TaskSnapshot = { revision: 7, tasks: [] };
    const next: TaskSnapshot = { revision: 9, tasks: [] };
    expect(acceptSnapshot(current, stale)).toBe(current);
    expect(acceptSnapshot(current, next)).toBe(next);
  });
});
