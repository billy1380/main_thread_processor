import 'package:logging/logging.dart';
import 'package:main_thread_processor/src/task.dart';

typedef Runnable = void Function();

class ProcessRunnables extends Task {
  static final Logger _log = Logger("ProcessRunnables");

  final List<(String, Runnable)> _runnables = [];

  ProcessRunnables();

  ProcessRunnables.single(String name, Runnable runnable) {
    addRunnable(name, runnable);
  }

  ProcessRunnables.list(List<(String, Runnable)> runnables) {
    for (final (String name, Runnable runnable) in runnables) {
      addRunnable(name, runnable);
    }
  }

  int _progress = 0;
  bool _running = false;

  @override
  double get progress => _runnables.isEmpty ? 1 : _progress / _runnables.length;

  @override
  void run() {
    _running = true;

    if (_progress < _runnables.length) {
      _log.info("Running task named [${_runnables[_progress].$1}]");
      _runnables[_progress].$2();
    }

    _progress++;
  }

  @override
  void reset() {
    _progress = 0;
    _running = false;
  }

  void addRunnable(String name, Runnable runnable) {
    if (_running) {
      _log.warning(
          "[$name] cannot be updated (discarded)... task is already running");
    } else {
      _runnables.add((name, runnable));
    }
  }
}
