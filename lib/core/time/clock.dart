/// Injectable source of wall-clock time (UTC epoch millis) so time-dependent
/// logic (HLC, timestamps) is deterministic under test.
abstract interface class Clock {
  int nowMillis();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  int nowMillis() => DateTime.now().toUtc().millisecondsSinceEpoch;
}

/// Test clock with controllable time.
class MutableClock implements Clock {
  int _t;
  MutableClock(this._t);

  set millis(int value) => _t = value;
  void advance(int by) => _t += by;

  @override
  int nowMillis() => _t;
}
