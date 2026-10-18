class Stall {
  double progress;
  bool warned = false;
  final Stopwatch _stopwatch = Stopwatch()..start();

  Stall(this.progress);

  Duration get elapsed => _stopwatch.elapsed;

  // NaN is never equal to itself, so a 0 / 0 progress would look like movement
  bool isSameProgress(double other) =>
      progress == other || (progress.isNaN && other.isNaN);

  void restart(double newProgress) {
    progress = newProgress;
    warned = false;
    _stopwatch
      ..reset()
      ..start();
  }
}
