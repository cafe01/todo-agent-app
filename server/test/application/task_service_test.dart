import 'package:test/test.dart';
import 'package:todo_agent_app/application/task_service.dart';
import 'package:todo_agent_app/domain/app_error.dart';
import 'package:todo_agent_app/domain/task.dart';
import 'package:todo_agent_app/application/task_repository.dart';

void main() {
  group('TaskService', () {
    late InMemoryTaskRepository repository;
    late TaskService service;

    setUp(() {
      repository = InMemoryTaskRepository();
      service = TaskService(repository);
    });

    test('commits create and update revisions and publishes snapshots', () async {
      final events = <TaskSnapshot>[];
      final subscription = service.snapshots.listen(events.add);
      final task = await service.create('Plan');

      expect(task.revision, 1);
      final updated = await service.update(task.id, completed: true, expectedRevision: 1);

      expect(updated.revision, 2);
      expect(events.map((snapshot) => snapshot.revision), [1, 2]);
      await subscription.cancel();
    });

    test('rejects stale writes without publishing a change', () async {
      final task = await service.create('Plan');
      final events = <TaskSnapshot>[];
      final subscription = service.snapshots.listen(events.add);

      await expectLater(
        service.update(task.id, completed: true, expectedRevision: 9),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'conflict')),
      );
      expect(events, isEmpty);
      expect(service.list().revision, 1);
      await subscription.cancel();
    });

    test('reports missing tasks and invalid input with stable error codes', () async {
      await expectLater(
        service.create('  '),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'invalidInput')),
      );
      await expectLater(
        service.delete('missing', expectedRevision: 0),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'notFound')),
      );
    });
  });
}

class InMemoryTaskRepository implements TaskRepository {
  final Map<String, Task> _tasks = {};
  int _revision = 0;

  @override
  TaskSnapshot snapshot() => TaskSnapshot(_revision, _tasks.values.toList());

  @override
  Task create(String id, String title) {
    _revision++;
    final task = Task(id: id, title: title, completed: false, revision: _revision);
    _tasks[id] = task;
    return task;
  }

  @override
  Task update(String id, {String? title, bool? completed, required int expectedRevision}) {
    final old = _tasks[id];
    if (old == null) throw AppError.notFound('Task not found');
    if (old.revision != expectedRevision) throw AppError.conflict('Task changed');
    _revision++;
    final task = old.copyWith(
      title: title ?? old.title,
      completed: completed ?? old.completed,
      revision: _revision,
    );
    _tasks[id] = task;
    return task;
  }

  @override
  void delete(String id, {required int expectedRevision}) {
    final old = _tasks[id];
    if (old == null) throw AppError.notFound('Task not found');
    if (old.revision != expectedRevision) throw AppError.conflict('Task changed');
    _tasks.remove(id);
    _revision++;
  }
}
