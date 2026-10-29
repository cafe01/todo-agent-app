import 'package:sqlite3/sqlite3.dart';

import '../domain/app_error.dart';
import '../domain/task.dart';
import '../application/task_repository.dart';

/// SQLite-backed task store. Each mutation and its global revision update
/// commit in one IMMEDIATE transaction.
class SqliteTaskRepository implements TaskRepository {
  SqliteTaskRepository._(this._database);

  factory SqliteTaskRepository.open(String path) {
    final database = sqlite3.open(path);
    database.execute('PRAGMA journal_mode = WAL');
    database.execute('PRAGMA foreign_keys = ON');
    database.execute('''
      CREATE TABLE IF NOT EXISTS app_state (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        revision INTEGER NOT NULL
      )
    ''');
    database.execute('INSERT OR IGNORE INTO app_state(singleton, revision) VALUES (1, 0)');
    database.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        completed INTEGER NOT NULL CHECK (completed IN (0, 1)),
        revision INTEGER NOT NULL,
        created_order INTEGER NOT NULL UNIQUE
      )
    ''');
    return SqliteTaskRepository._(database);
  }

  final Database _database;
  bool _closed = false;

  @override
  TaskSnapshot snapshot() {
    _ensureOpen();
    final revision =
        _database.select('SELECT revision FROM app_state WHERE singleton = 1').single['revision']
            as int;
    final rows = _database.select(
      'SELECT id, title, completed, revision FROM tasks ORDER BY created_order',
    );
    return TaskSnapshot(
      revision,
      rows
          .map(
            (row) => Task(
              id: row['id'] as String,
              title: row['title'] as String,
              completed: row['completed'] == 1,
              revision: row['revision'] as int,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Task create(String id, String title) => _transaction(() {
    final revision = _nextRevision();
    _database.execute(
      'INSERT INTO tasks(id, title, completed, revision, created_order) VALUES (?, ?, 0, ?, ?)',
      [id, title, revision, revision],
    );
    return Task(id: id, title: title, completed: false, revision: revision);
  });

  @override
  Task update(String id, {String? title, bool? completed, required int expectedRevision}) =>
      _transaction(() {
        final rows = _database.select('SELECT * FROM tasks WHERE id = ?', [id]);
        if (rows.isEmpty) throw AppError.notFound('Task not found');
        final row = rows.single;
        if (row['revision'] != expectedRevision) {
          throw AppError.conflict('Task revision does not match expectedRevision');
        }
        final revision = _nextRevision();
        final task = Task(
          id: id,
          title: title ?? row['title'] as String,
          completed: completed ?? row['completed'] == 1,
          revision: revision,
        );
        _database.execute('UPDATE tasks SET title = ?, completed = ?, revision = ? WHERE id = ?', [
          task.title,
          task.completed ? 1 : 0,
          revision,
          id,
        ]);
        return task;
      });

  @override
  void delete(String id, {required int expectedRevision}) => _transaction(() {
    final rows = _database.select('SELECT revision FROM tasks WHERE id = ?', [id]);
    if (rows.isEmpty) throw AppError.notFound('Task not found');
    if (rows.single['revision'] != expectedRevision) {
      throw AppError.conflict('Task revision does not match expectedRevision');
    }
    _database.execute('DELETE FROM tasks WHERE id = ?', [id]);
    _nextRevision();
  });

  void close() {
    if (_closed) return;
    _closed = true;
    _database.close();
  }

  T _transaction<T>(T Function() action) {
    _ensureOpen();
    _database.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      _database.execute('COMMIT');
      return result;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  int _nextRevision() {
    _database.execute('UPDATE app_state SET revision = revision + 1 WHERE singleton = 1');
    return _database.select('SELECT revision FROM app_state WHERE singleton = 1').single['revision']
        as int;
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Repository is closed');
  }
}
