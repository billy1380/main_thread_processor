import 'dart:async';

import 'package:logging/logging.dart';
import 'package:main_thread_processor/src/task.dart';
import 'package:main_thread_processor/src/task_context.dart';

/// The public facade for task processing.
///
/// Use [Processor.shared] for global tasks, or create a new [Processor]
/// instance to manage a dedicated queue of tasks (e.g., for a specific screen or feature).
///
/// All [Processor] instances delegate to a single background "marshal" to ensure
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
    _CentralProcessor.shared.addTask(task, context: _context);
  }

  /// Removes a specific [task] from this processor's queue.
  void removeTask(Task? task) {
    _CentralProcessor.shared.removeTask(task);
  }

  /// Removes all tasks associated with this processor instance.
  void removeAllTasks() {
    _CentralProcessor.shared.removeTasksForContext(_context);
  }

  /// Pauses the global processing loop.
  /// Note: This affects ALL processor instances.
  void pause() {
    _CentralProcessor.shared.pause();
  }

  /// Resumes the global processing loop.
  void resume() {
    _CentralProcessor.shared.resume();
  }

  /// Checks if this specific processor has any tasks waiting.
  bool get hasOutstanding =>
      _CentralProcessor.shared.hasTasksForContext(_context);

  /// Manually triggers an update cycle (mostly for testing).
  Future<bool> update() {
    return _CentralProcessor.shared.update();
  }

  /// Gets or sets the global processing period in milliseconds.
  int get period => _CentralProcessor.shared.period;

  set period(int value) => _CentralProcessor.shared.period = value;

  /// Access to the underlying task queue (for testing).
  /// Returns only tasks belonging to this processor's context.
  List<Task>? get taskQueue {
    return _CentralProcessor.shared._taskQueues[_context];
  }
}

/// The internal singleton engine that marshals all tasks.
class _CentralProcessor {
  static final Logger _log = Logger("Processor");

  static _CentralProcessor? _one;

  StreamSubscription? _subscription;
  int _period = 20; // in milliseconds

  _CentralProcessor._();

  static _CentralProcessor get shared => _one ??= _CentralProcessor._();

  bool get _isPaused => _subscription == null;
  bool _inUpdate = false;

  // Map of contexts to their respective task queues.
  final Map<TaskContext, List<Task>> _taskQueues = {};

  // Ordered list of active contexts for Round-Robin scheduling.
  final List<TaskContext> _activeContexts = [];

  // Index tracking the current position in the Round-Robin cycle.
  int _currentContextIndex = 0;

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

  bool get hasOutstanding => _taskQueues.isNotEmpty;

  void pause() {
    _subscription?.cancel();
    _subscription = null;
  }

  void resume() {
    if (!_inUpdate && hasOutstanding && _isPaused) {
      _subscription = Stream.periodic(Duration(milliseconds: _period))
          .listen((event) => update());
    }
  }

  int get period {
    return _period;
  }

  set period(int value) {
    pause();
    _period = value;
    resume();
  }
}
