import '../domain/task.dart';

/// Persistence port for the task use cases.
abstract interface class TaskRepository {
  TaskSnapshot snapshot();
  Task create(String id, String title);
  Task update(String id, {String? title, bool? completed, required int expectedRevision});
  void delete(String id, {required int expectedRevision});
}
