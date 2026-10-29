/// An immutable task row.
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.completed,
    required this.revision,
  });

  final String id;
  final String title;
  final bool completed;
  final int revision;

  static String validateTitle(String value) {
    final title = value.trim();
    if (title.isEmpty) throw ArgumentError.value(value, 'title', 'must not be empty');
    if (title.length > 200) {
      throw ArgumentError.value(value, 'title', 'must be at most 200 characters');
    }
    return title;
  }

  Task copyWith({String? title, bool? completed, int? revision}) => Task(
    id: id,
    title: title ?? this.title,
    completed: completed ?? this.completed,
    revision: revision ?? this.revision,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'completed': completed,
    'revision': revision,
  };

  factory Task.fromJson(Map<String, Object?> json) => Task(
    id: json['id']! as String,
    title: json['title']! as String,
    completed: json['completed']! as bool,
    revision: json['revision']! as int,
  );
}

/// A consistent full view of the task list.
class TaskSnapshot {
  TaskSnapshot(this.revision, List<Task> tasks) : tasks = List.unmodifiable(tasks);

  final int revision;
  final List<Task> tasks;

  Map<String, Object> toJson() => {
    'revision': revision,
    'tasks': tasks.map((task) => task.toJson()).toList(growable: false),
  };
}
