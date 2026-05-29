import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/time/hlc.dart';

void main() {
  group('Hlc', () {
    test('increment advances counter when wall clock is not ahead', () {
      final a = Hlc(millis: 1000, counter: 0, nodeId: 'a');
      final b = a.increment(1000);
      expect(b.millis, 1000);
      expect(b.counter, 1);
    });

    test('increment uses wall clock when ahead and resets counter', () {
      final a = Hlc(millis: 1000, counter: 5, nodeId: 'a');
      final b = a.increment(2000);
      expect(b.millis, 2000);
      expect(b.counter, 0);
    });

    test('receive merges a remote clock that is ahead', () {
      final local = Hlc(millis: 1000, counter: 0, nodeId: 'a');
      final remote = Hlc(millis: 1500, counter: 3, nodeId: 'b');
      final merged = local.receive(remote, 1200);
      expect(merged.millis, 1500);
      expect(merged.counter, 4);
      expect(merged.nodeId, 'a'); // identity is preserved
    });

    test('pack/unpack round-trip', () {
      final h = Hlc(millis: 1717000000000, counter: 7, nodeId: 'device-x');
      expect(Hlc.unpack(h.pack()), h);
    });

    test('total order breaks ties by nodeId', () {
      final a = Hlc(millis: 1000, counter: 1, nodeId: 'a');
      final b = Hlc(millis: 1000, counter: 1, nodeId: 'b');
      expect(a < b, isTrue);
      expect(b > a, isTrue);
    });

    test('packed strings sort in causal order', () {
      final list = [
        Hlc(millis: 1000, counter: 2, nodeId: 'a'),
        Hlc(millis: 1000, counter: 0, nodeId: 'a'),
        Hlc(millis: 999, counter: 9, nodeId: 'z'),
        Hlc(millis: 1000, counter: 1, nodeId: 'b'),
      ];
      final packed = list.map((h) => h.pack()).toList()..sort();
      final unpacked = packed.map(Hlc.unpack).toList();
      for (var i = 1; i < unpacked.length; i++) {
        expect(unpacked[i - 1] < unpacked[i], isTrue);
      }
    });
  });
}
