import 'dart:async';

import 'package:uuid/uuid.dart';

import '../domain/app_error.dart';
import '../domain/task.dart';
import 'task_repository.dart';

/// Task use cases shared by the HTTP and MCP adapters.
class TaskService {
  TaskService(this._repository, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final TaskRepository _repository;
  final Uuid _uuid;
  final StreamController<TaskSnapshot> _changes = StreamController<TaskSnapshot>.broadcast(
    sync: true,
  );

  Stream<TaskSnapshot> get snapshots => _changes.stream;

  TaskSnapshot list() => _repository.snapshot();

  Future<Task> create(String title) async {
    final normalized = _validateTitle(title);
    final task = _repository.create(_uuid.v4(), normalized);
    _publish();
    return task;
  }

  Future<Task> update(
    String id, {
    String? title,
    bool? completed,
    required int expectedRevision,
  }) async {
    if (title == null && completed == null) {
      throw AppError.invalidInput('At least one field must be provided');
    }
    final normalized = title == null ? null : _validateTitle(title);
    final task = _repository.update(
      id,
      title: normalized,
      completed: completed,
      expectedRevision: expectedRevision,
    );
    _publish();
    return task;
  }

  Future<void> delete(String id, {required int expectedRevision}) async {
    _repository.delete(id, expectedRevision: expectedRevision);
    _publish();
  }

  Future<void> close() => _changes.close();

  String _validateTitle(String title) {
    try {
      return Task.validateTitle(title);
    } on ArgumentError catch (error) {
      throw AppError.invalidInput(error.message.toString());
    }
  }

  void _publish() => _changes.add(_repository.snapshot());
}
