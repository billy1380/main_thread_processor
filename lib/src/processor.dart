import 'package:main_thread_processor/src/scheduler.dart';
import 'package:main_thread_processor/src/task.dart';
import 'package:main_thread_processor/src/task_context.dart';

/// The public facade for task processing.
///
/// Use [Processor.shared] for global tasks, or create a new [Processor]
/// instance to manage a dedicated queue of tasks (e.g., for a specific screen or feature).
///
/// All [Processor] instances delegate to a single background [Scheduler] to ensure
/// tasks are executed sequentially on the main thread, preventing jank.
class Processor {
  final TaskContext _context;

  Processor() : _context = TaskContext();

  Processor._withContext(this._context);

  static final Processor _shared =
      Processor._withContext(TaskContext("Default"));

  /// Returns the global shared processor instance.
  static Processor get shared => _shared;

  /// Adds a [task] to this processor's queue.
  void addTask(Task task) {
    Scheduler.shared.addTask(task, context: _context);
  }

  /// Removes a specific [task] from this processor's queue.
  void removeTask(Task? task) {
    Scheduler.shared.removeTask(task);
  }

  /// Removes all tasks associated with this processor instance.
  void removeAllTasks() {
    Scheduler.shared.removeTasksForContext(_context);
  }

  /// Pauses the global processing loop.
  /// Note: This affects ALL processor instances.
  /// Use [Scheduler.pause] for clarity that this is a global action.
  void pause() {
    Scheduler.shared.pause();
  }

  /// Resumes the global processing loop.
  /// Use [Scheduler.resume] for clarity that this is a global action.
  void resume() {
    Scheduler.shared.resume();
  }

  /// Checks if this specific processor has any tasks waiting.
  bool get hasOutstanding => Scheduler.shared.hasTasksForContext(_context);

  /// Manually triggers an update cycle (mostly for testing).
  Future<bool> update() {
    return Scheduler.shared.update();
  }

  /// Access to the underlying task queue (for testing).
  /// Returns only tasks belonging to this processor's context.
  List<Task>? get taskQueue {
    return Scheduler.shared.taskQueueFor(_context);
  }
}
