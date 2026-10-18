import 'dart:async';

import 'package:logging/logging.dart';
import 'package:main_thread_processor/src/stall.dart';
import 'package:main_thread_processor/src/task.dart';
import 'package:main_thread_processor/src/task_context.dart';

const _defaultSchedulerPeriod = 20; // in milliseconds
const _defaultStallWarning = Duration(seconds: 10);
const _defaultStallLimit = Duration(seconds: 120);

/// The singleton engine that marshals all tasks.
///
/// Controls the global execution loop and timing, and is where the update
/// period and the stall limits are configured.
class Scheduler {
  static final Logger _log = Logger("Scheduler");

  static Scheduler? _one;

  StreamSubscription? _subscription;
  int _period = _defaultSchedulerPeriod;

  Scheduler._();

  /// The global shared scheduler instance.
  static Scheduler get shared => _one ??= Scheduler._();

  bool get _isPaused => _subscription == null;
  bool _inUpdate = false;

  Duration _stallWarning = _defaultStallWarning;
  Duration _stallLimit = _defaultStallLimit;
  final Expando<Stall> _stalls = Expando<Stall>();

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
          } else if (_isStalled(task, progress)) {
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

  // warns once when a task stops making progress, and removes it at the limit
  bool _isStalled(Task task, double progress) {
    final Stall stall = _stalls[task] ??= Stall(progress);

    if (!stall.isSameProgress(progress)) {
      stall.restart(progress);
      return false;
    }

    final Duration elapsed = stall.elapsed;

    if (elapsed >= _stallLimit) {
      _log.severe("${task.runtimeType} made no progress for "
          "${elapsed.inSeconds}s (limit ${_stallLimit.inSeconds}s), "
          "removing it from the queue");
      return true;
    }

    if (elapsed >= _stallWarning && !stall.warned) {
      stall.warned = true;
      _log.warning("${task.runtimeType} has made no progress for "
          "${elapsed.inSeconds}s (removed at ${_stallLimit.inSeconds}s)");
    }

    return false;
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

  /// The queue for a context, if it has one.
  List<Task>? taskQueueFor(TaskContext context) => _taskQueues[context];

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

  /// How long a task can make no progress before a warning is logged.
  Duration get stallWarning => _stallWarning;

  set stallWarning(Duration value) {
    _stallWarning = _positive(value);
  }

  /// How long a task can make no progress before it is removed.
  ///
  /// The limit cannot be switched off, only moved.
  Duration get stallLimit => _stallLimit;

  set stallLimit(Duration value) {
    _stallLimit = _positive(value);
  }

  void resetStallLimits() {
    _stallWarning = _defaultStallWarning;
    _stallLimit = _defaultStallLimit;
  }

  static Duration _positive(Duration value) {
    if (value <= Duration.zero) {
      throw ArgumentError.value(value, 'value', 'must be greater than zero');
    }

    return value;
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

  void resetPeriod() {
    period = _defaultSchedulerPeriod;
  }
}
