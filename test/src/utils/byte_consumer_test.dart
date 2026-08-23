import 'package:test/test.dart';
import 'package:xterm/src/utils/byte_consumer.dart';

void main() {
  late ByteConsumer consumer;

  setUp(() {
    consumer = ByteConsumer();
  });

  group('add', () {
    test('empty string is ignored', () {
      consumer.add('');
      expect(consumer.isEmpty, isTrue);
      expect(consumer.length, 0);
    });

    test('adds code units to the queue', () {
      consumer.add('ab');
      expect(consumer.length, 2);
      expect(consumer.isNotEmpty, isTrue);
    });

    test('length accumulates across multiple adds', () {
      consumer.add('ab');
      consumer.add('cde');
      expect(consumer.length, 5);
    });
  });

  group('consume', () {
    test('returns code units in order', () {
      consumer.add('ab');
      expect(consumer.consume(), 'a'.codeUnitAt(0));
      expect(consumer.consume(), 'b'.codeUnitAt(0));
      expect(consumer.isEmpty, isTrue);
    });

    test('consumes across block boundaries seamlessly', () {
      consumer.add('ab');
      consumer.add('cd');
      final consumed = [
        consumer.consume(),
        consumer.consume(),
        consumer.consume(),
        consumer.consume(),
      ];
      expect(consumed, [97, 98, 99, 100]);
    });

    test('tracks length and totalConsumed', () {
      consumer.add('abc');
      consumer.consume();
      expect(consumer.length, 2);
      expect(consumer.totalConsumed, 1);
    });

    test('consuming an empty consumer throws', () {
      expect(consumer.consume, throwsStateError);
    });
  });

  group('peek', () {
    test('returns the next unit without consuming it', () {
      consumer.add('ab');
      expect(consumer.peek(), 97);
      expect(consumer.length, 2);
      expect(consumer.consume(), 97);
    });

    test('peeks across a block boundary', () {
      consumer.add('ab');
      consumer.add('cd');
      consumer.consume();
      consumer.consume();
      expect(consumer.peek(), 99);
      // State must be unchanged: the next consume returns the same unit.
      expect(consumer.consume(), 99);
      expect(consumer.consume(), 100);
    });
  });

  group('rollback', () {
    test('rolls back a single consumed unit', () {
      consumer.add('ab');
      consumer.consume();
      consumer.consume();
      consumer.rollback();
      expect(consumer.length, 1);
      expect(consumer.totalConsumed, 1);
      expect(consumer.consume(), 98);
    });

    test('rolls back across block boundaries', () {
      consumer.add('ab');
      consumer.add('cd');
      consumer.consume(); // a
      consumer.consume(); // b
      consumer.consume(); // c
      consumer.rollback(2);
      expect(consumer.length, 3);
      expect(consumer.totalConsumed, 1);
      expect(consumer.consume(), 98);
      expect(consumer.consume(), 99);
      expect(consumer.consume(), 100);
    });

    test('rolling back everything restores the full input', () {
      consumer.add('abc');
      consumer.consume();
      consumer.consume();
      consumer.consume();
      consumer.rollback(3);
      expect(consumer.isNotEmpty, isTrue);
      expect(consumer.length, 3);
      expect(consumer.totalConsumed, 0);
      expect(consumer.consume(), 97);
    });
  });

  group('rollbackTo', () {
    test('rolls back to the state with the given length', () {
      consumer.add('ab');
      consumer.add('cd');
      while (consumer.isNotEmpty) {
        consumer.consume();
      }
      consumer.rollbackTo(2);
      expect(consumer.length, 2);
      expect(consumer.consume(), 99);
      expect(consumer.consume(), 100);
      expect(consumer.isEmpty, isTrue);
    });
  });

  group('unrefConsumedBlocks', () {
    test('rollback within the current block still works afterwards', () {
      consumer.add('ab');
      consumer.consume();
      consumer.unrefConsumedBlocks();
      consumer.rollback();
      expect(consumer.consume(), 97);
    });

    test('rollback into an unreferenced block throws', () {
      // Documents current behavior: once a block is unreferenced, rolling
      // back past it fails with a StateError from the empty consumed queue.
      consumer.add('ab');
      consumer.add('cd');
      consumer.consume();
      consumer.consume();
      consumer.consume(); // crosses into the second block
      consumer.unrefConsumedBlocks();
      expect(() => consumer.rollback(2), throwsStateError);
    });
  });

  group('reset', () {
    test('clears all state', () {
      consumer.add('abc');
      consumer.consume();
      consumer.reset();
      expect(consumer.isEmpty, isTrue);
      expect(consumer.length, 0);
      expect(consumer.totalConsumed, 0);
    });
  });

  group('unicode handling', () {
    test('surrogate pair is combined into a single code point', () {
      consumer.add('😀');
      expect(consumer.length, 1);
      expect(consumer.consume(), 0x1F600);
    });

    test('surrogate pair between BMP characters', () {
      consumer.add('a😀b');
      expect(consumer.length, 3);
      expect(consumer.consume(), 97);
      expect(consumer.consume(), 0x1F600);
      expect(consumer.consume(), 98);
    });

    test('lone high surrogate is kept as-is', () {
      consumer.add('\ud83d');
      expect(consumer.length, 1);
      expect(consumer.consume(), 0xD83D);
    });

    test('lone low surrogate is kept as-is', () {
      consumer.add('\ude00');
      expect(consumer.length, 1);
      expect(consumer.consume(), 0xDE00);
    });

    test('high surrogate not followed by a low surrogate is kept as-is', () {
      consumer.add('\ud83dx');
      expect(consumer.length, 2);
      expect(consumer.consume(), 0xD83D);
      expect(consumer.consume(), 120);
    });

    test('pair split across two adds is NOT recombined', () {
      // Documents a limitation: each add() combines surrogates within its
      // own chunk only, so a pair split across writes stays split.
      consumer.add('\ud83d');
      consumer.add('\ude00');
      expect(consumer.length, 2);
      expect(consumer.consume(), 0xD83D);
      expect(consumer.consume(), 0xDE00);
    });
  });
}
