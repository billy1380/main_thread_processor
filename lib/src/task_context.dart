/// A strong identifier for a group of tasks.
/// Used to isolate tasks within the [Processor] so they can be
/// managed (e.g., cleared) independently without affecting other contexts.
class TaskContext {
  late final String _debugName;

  /// Creates a new unique task context.
  /// [debugName] is optional and used only for logging/debugging.
  /// If null or empty, a name based on the instance hash is generated.
  TaskContext([String? debugName]) {
    final hash = identityHashCode(this).toRadixString(16);
    if (debugName == null || debugName.isEmpty) {
      _debugName = "TaskContext@$hash";
    } else {
      _debugName = "TaskContext($debugName#$hash)";
    }
  }

  @override
  String toString() => _debugName;
}
