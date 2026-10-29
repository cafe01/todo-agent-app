import 'dart:io';

import 'package:test/test.dart';
import 'package:todo_agent_app/domain/app_error.dart';
import 'package:todo_agent_app/infrastructure/sqlite_task_repository.dart';

void main() {
  group('SqliteTaskRepository', () {
    late Directory directory;
    late SqliteTaskRepository repository;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('todo-agent-test-');
      repository = SqliteTaskRepository.open('${directory.path}/tasks.sqlite3');
    });

    tearDown(() async {
      repository.close();
      await directory.delete(recursive: true);
    });

    test('persists ordered tasks and global revisions across reopen', () {
      final first = repository.create('id-1', 'First');
      final second = repository.create('id-2', 'Second');
      expect(first.revision, 1);
      expect(second.revision, 2);
      repository.close();

      repository = SqliteTaskRepository.open('${directory.path}/tasks.sqlite3');
      final snapshot = repository.snapshot();
      expect(snapshot.revision, 2);
      expect(snapshot.tasks.map((task) => task.id), ['id-1', 'id-2']);
    });

    test('checks task revision before mutation and does not advance on conflict', () {
      final task = repository.create('id-1', 'First');
      expect(
        () => repository.update('id-1', completed: true, expectedRevision: 99),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'conflict')),
      );
      expect(repository.snapshot().revision, 1);
      expect(repository.snapshot().tasks.single.revision, task.revision);
    });
  });
}
