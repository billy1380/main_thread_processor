import 'dart:async';

import 'package:logging/logging.dart';
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
  bool get hasOutstanding =>
      Scheduler.shared.hasTasksForContext(_context);

  /// Manually triggers an update cycle (mostly for testing).
  Future<bool> update() {
    return Scheduler.shared.update();
  }

  /// Access to the underlying task queue (for testing).
  /// Returns only tasks belonging to this processor's context.
  List<Task>? get taskQueue {
    return Scheduler.shared._taskQueues[_context];
  }
}

/// The internal singleton engine that marshals all tasks.
///
/// Controls the global execution loop and timing.
class Scheduler {
  static final Logger _log = Logger("Scheduler");

  static Scheduler? _one;

  StreamSubscription? _subscription;
  int _period = 20; // in milliseconds

  Scheduler._();

  /// The global shared scheduler instance.
  static Scheduler get shared => _one ??= Scheduler._();

  bool get _isPaused => _subscription == null;
  bool _inUpdate = false;

  // Map of contexts to their respective task queues.
  final Map<TaskContext, List<Task>> _taskQueues = {};

  // Ordered list of active contexts for Round-Robin scheduling.
  final List<TaskContext> _activeContexts = [];

  // Index tracking the current position in the Round-Robin cycle.
  int _currentContextIndex = 0;

  /// Adds a task to the scheduler for a specific context.
  /// Typically called by [Processor.addTask].
  void addTask(Task task, {required TaskContext context}) {
    if (!_taskQueues.containsKey(context)) {
      _taskQueues[context] = [];
      _activeContexts.add(context);
    }

    _taskQueues[context]!.add(task);

    if (_isPaused && !_inUpdate) {
      _log.info("resuming update loop...");
      resume();
    }
  }

  /// Removes a task from the scheduler.
  /// Typically called by [Processor.removeTask].
  void removeTask(Task? task) {
    if (task == null) return;

    bool paused = false;
    if (!_isPaused) {
      pause();
      paused = true;
    }

    for (final queue in _taskQueues.values) {
      if (queue.remove(task)) {
        // Task found and removed.
      }
    }

    _cleanupEmptyContexts();

    if (paused) {
      resume();
    }
  }

  /// Removes all tasks for a specific context.
  /// Typically called by [Processor.removeAllTasks].
  void removeTasksForContext(TaskContext context) {
    bool paused = false;
    if (!_isPaused) {
      pause();
      paused = true;
    }

    _taskQueues.remove(context);
    _activeContexts.remove(context);
    _adjustContextIndex();

    if (paused) {
      resume();
    }
  }

  bool hasTasksForContext(TaskContext context) {
    return _taskQueues[context]?.isNotEmpty ?? false;
  }

  /// Manually runs one cycle of the scheduler.
  Future<bool> update() async {
    bool more = false;

    if (_isPaused) {
      more = hasOutstanding;
    } else {
      _inUpdate = true;

      if (!_isPaused && hasOutstanding) {
        // Round-Robin Selection
        if (_currentContextIndex >= _activeContexts.length) {
          _currentContextIndex = 0;
        }

        final currentContext = _activeContexts[_currentContextIndex];
        final currentQueue = _taskQueues[currentContext];

        if (currentQueue != null && currentQueue.isNotEmpty) {
          Task task = currentQueue.first;

          _log.info("Found task from context $currentContext");
          _log.info("running task...");
          task.run();

          double progress = task.progress;
          final progressPercentage = progress * 100;
          _log.info("current run is ${progressPercentage.toStringAsFixed(1)}%");

          if (progress >= 1) {
            _log.info("task complete removing...");
            currentQueue.remove(task);
          }
        }

        // Cleanup if the current queue became empty
        if (currentQueue == null || currentQueue.isEmpty) {
          _taskQueues.remove(currentContext);
          _activeContexts.removeAt(_currentContextIndex);
          _adjustContextIndex();
        } else {
          // Move to next context
          _currentContextIndex++;
        }

        if (hasOutstanding) {
          _log.info("resuming update loop...");
          more = true;
        }
      } else {
        _log.info("Task queue is empty");
      }

      if (!more) {
        pause();
      }

      _inUpdate = false;
    }

    return more;
  }

  void _cleanupEmptyContexts() {
    final emptyContexts = _taskQueues.entries
        .where((e) => e.value.isEmpty)
        .map((e) => e.key)
        .toList();

    for (final context in emptyContexts) {
      _taskQueues.remove(context);
      _activeContexts.remove(context);
    }
    _adjustContextIndex();
  }

  void _adjustContextIndex() {
    if (_activeContexts.isEmpty) {
      _currentContextIndex = 0;
    } else if (_currentContextIndex >= _activeContexts.length) {
      _currentContextIndex = 0;
    }
  }

  /// Checks if there are any tasks in any queue.
  bool get hasOutstanding => _taskQueues.isNotEmpty;

  /// Pauses the global scheduling loop.
  void pause() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Resumes the global scheduling loop.
  void resume() {
    if (!_inUpdate && hasOutstanding && _isPaused) {
      _subscription = Stream.periodic(Duration(milliseconds: _period))
          .listen((event) => update());
    }
  }

  /// Gets the global processing period in milliseconds.
  int get period {
    return _period;
  }

  /// Sets the global processing period in milliseconds.
  ///
  /// This setting controls the interval of the central timer loop.
  /// Adjusting this value restarts the timer.
  set period(int value) {
    pause();
    _period = value;
    resume();
  }
}