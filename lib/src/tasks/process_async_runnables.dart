import 'package:logging/logging.dart';
import 'package:main_thread_processor/src/task.dart';

typedef AsyncRunnable = Future<void> Function();

class ProcessAsyncRunnables extends Task {
  static final Logger _log = Logger("ProcessAsyncRunnables");

  final List<(String, AsyncRunnable)> _asyncRunnables = [];
  final bool runInParallel;

  ProcessAsyncRunnables({this.runInParallel = true});

  ProcessAsyncRunnables.single(String name, AsyncRunnable runnable,
      {this.runInParallel = true}) {
    addAsyncRunnable(name, runnable);
  }

  ProcessAsyncRunnables.list(List<(String, AsyncRunnable)> namedAsyncRunnables,
      {this.runInParallel = true}) {
    for (final (String name, AsyncRunnable runnable) in namedAsyncRunnables) {
      addAsyncRunnable(name, runnable);
    }
  }

  int _completed = 0;
  bool _started = false;

  @override
  double get progress =>
      _asyncRunnables.isEmpty ? 1 : _completed / _asyncRunnables.length;

  @override
  void run() {
    if (_started) return;
    _started = true;

    if (runInParallel) {
      for (final (String name, AsyncRunnable asyncRunnable)
          in _asyncRunnables) {
        _log.info("Running task named [$name]");

        asyncRunnable().whenComplete(() {
          _completed++;
        });
      }
    } else {
      _runSequential();
    }
  }

  void _runSequential([int index = 0]) {
    if (index >= _asyncRunnables.length) {
      _completed = _asyncRunnables.length;
      return;
    }

    final (name, asyncRunnable) = _asyncRunnables[index];
    _log.info("Running task named [$name]");

    asyncRunnable().whenComplete(() {
      _completed++;
      _runSequential(index + 1);
    });
  }

  @override
  void reset() {
    _completed = 0;
    _started = false;
  }

  void addAsyncRunnable(String name, AsyncRunnable runnable) {
    if (_started) {
      _log.warning(
          "[$name] cannot be added (discarded)... task is already running");
      return;
    }
    _asyncRunnables.add((name, runnable));
  }
}
