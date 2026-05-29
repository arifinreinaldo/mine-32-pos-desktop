import 'dart:math' as math;

/// Hybrid Logical Clock — gives a **total order** across devices without a
/// central server, advancing past wall-clock skew and breaking ties by
/// [nodeId]. Used to stamp every write so sync can resolve conflicts
/// deterministically (last-write-wins for mutable master data).
class Hlc implements Comparable<Hlc> {
  /// Max counter that fits the fixed-width packed encoding (5 digits).
  static const int maxCounter = 99999;
  static const int _counterDigits = 5;
  static const int _millisDigits = 15;

  final int millis;
  final int counter;
  final String nodeId;

  const Hlc({
    required this.millis,
    required this.counter,
    required this.nodeId,
  });

  factory Hlc.zero(String nodeId) => Hlc(millis: 0, counter: 0, nodeId: nodeId);

  /// Produce the HLC for a new local event given the current wall clock.
  Hlc increment(int nowMillis) {
    final m = math.max(millis, nowMillis);
    final c = (m == millis) ? counter + 1 : 0;
    _checkCounter(c);
    return Hlc(millis: m, counter: c, nodeId: nodeId);
  }

  /// Merge a [remote] HLC observed on receive into this (local) clock.
  Hlc receive(Hlc remote, int nowMillis) {
    final m = math.max(math.max(millis, remote.millis), nowMillis);
    final int c;
    if (m == millis && m == remote.millis) {
      c = math.max(counter, remote.counter) + 1;
    } else if (m == millis) {
      c = counter + 1;
    } else if (m == remote.millis) {
      c = remote.counter + 1;
    } else {
      c = 0;
    }
    _checkCounter(c);
    return Hlc(millis: m, counter: c, nodeId: nodeId);
  }

  /// Lexicographically sortable encoding: `<millis>:<counter>:<nodeId>`.
  String pack() {
    final ms = millis.toString().padLeft(_millisDigits, '0');
    final ct = counter.toString().padLeft(_counterDigits, '0');
    return '$ms:$ct:$nodeId';
  }

  factory Hlc.unpack(String packed) {
    final parts = packed.split(':');
    if (parts.length < 3) {
      throw FormatException('Invalid HLC: $packed');
    }
    return Hlc(
      millis: int.parse(parts[0]),
      counter: int.parse(parts[1]),
      // nodeId (a UUID) never contains ':', but be defensive.
      nodeId: parts.sublist(2).join(':'),
    );
  }

  void _checkCounter(int c) {
    if (c > maxCounter) {
      throw StateError('HLC counter overflow ($c) for node $nodeId');
    }
  }

  @override
  int compareTo(Hlc other) {
    final byMillis = millis.compareTo(other.millis);
    if (byMillis != 0) return byMillis;
    final byCounter = counter.compareTo(other.counter);
    if (byCounter != 0) return byCounter;
    return nodeId.compareTo(other.nodeId);
  }

  bool operator >(Hlc o) => compareTo(o) > 0;
  bool operator <(Hlc o) => compareTo(o) < 0;
  bool operator >=(Hlc o) => compareTo(o) >= 0;
  bool operator <=(Hlc o) => compareTo(o) <= 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.millis == millis &&
      other.counter == counter &&
      other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(millis, counter, nodeId);

  @override
  String toString() => pack();
}
