import 'package:test/test.dart';
import 'package:xterm/src/core/tabs.dart';

void main() {
  group('TabStops defaults', () {
    test('has stops every 8 columns up to the last column', () {
      final tabStops = TabStops();

      expect(tabStops.isSetAt(0), isTrue);
      expect(tabStops.isSetAt(8), isTrue);
      expect(tabStops.isSetAt(16), isTrue);
      // 1016 = 127 * 8 is the last default stop within the 1024 columns.
      expect(tabStops.isSetAt(1016), isTrue);
      expect(tabStops.isSetAt(1023), isFalse);
    });
  });

  group('TabStops.find()', () {
    test('returns null when start is not before end', () {
      final tabStops = TabStops();

      expect(tabStops.find(5, 5), isNull);
      expect(tabStops.find(8, 0), isNull);
    });

    test('returns null when there is no stop in the range', () {
      final tabStops = TabStops();

      expect(tabStops.find(1, 8), isNull);
      expect(tabStops.find(9, 16), isNull);
    });

    test('clamps the end to the number of columns', () {
      final tabStops = TabStops();

      // The range goes past the last column; the last stop is at 1016.
      expect(tabStops.find(1009, 5000), 1016);
      // There are no stops between 1017 and the end of the buffer.
      expect(tabStops.find(1017, 5000), isNull);
    });

    test('finds a stop set by setAt', () {
      final tabStops = TabStops();

      tabStops.setAt(3);

      expect(tabStops.find(1, 8), 3);
      expect(tabStops.find(3, 8), 3, reason: 'start is inclusive');
    });
  });

  group('TabStops.setAt() / clearAt()', () {
    test('setAt adds a stop and is idempotent', () {
      final tabStops = TabStops();

      tabStops.setAt(3);
      tabStops.setAt(3);

      expect(tabStops.isSetAt(3), isTrue);
    });

    test('clearAt removes a stop and is idempotent', () {
      final tabStops = TabStops();

      tabStops.clearAt(8);
      tabStops.clearAt(8);

      expect(tabStops.isSetAt(8), isFalse);
      expect(tabStops.find(0, 16), 0);
      expect(tabStops.find(1, 17), 16, reason: '8 is skipped');
    });

    test('clearAt on an unset stop does nothing', () {
      final tabStops = TabStops();

      tabStops.clearAt(3);

      expect(tabStops.isSetAt(3), isFalse);
    });
  });

  group('TabStops.clearAll() / reset()', () {
    test('clearAll removes every stop', () {
      final tabStops = TabStops();

      tabStops.clearAll();

      expect(tabStops.isSetAt(0), isFalse);
      expect(tabStops.isSetAt(8), isFalse);
      expect(tabStops.find(0, 1024), isNull);
    });

    test('reset restores the default 8 column stops', () {
      final tabStops = TabStops();
      tabStops.clearAll();
      tabStops.setAt(3);

      tabStops.reset();

      expect(tabStops.isSetAt(3), isFalse);
      expect(tabStops.isSetAt(0), isTrue);
      expect(tabStops.isSetAt(8), isTrue);
      expect(tabStops.isSetAt(1016), isTrue);
      expect(tabStops.find(0, 1024), 0);
    });

    test('clearAll does not affect stops set afterwards', () {
      final tabStops = TabStops();
      tabStops.clearAll();

      tabStops.setAt(5);

      expect(tabStops.find(0, 1024), 5);
    });
  });
}
