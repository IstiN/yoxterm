import 'package:test/test.dart';
import 'package:xterm/src/base/event.dart';

void main() {
  group('EventEmitter', () {
    test('delivers emitted events to a registered listener', () {
      final emitter = EventEmitter<int>();
      final received = <int>[];
      emitter(received.add);

      emitter.emit(1);
      emitter.emit(2);

      expect(received, [1, 2]);
    });

    test('delivers to multiple listeners in registration order', () {
      final emitter = EventEmitter<String>();
      final order = <String>[];
      emitter((event) => order.add('first:$event'));
      emitter((event) => order.add('second:$event'));

      emitter.emit('x');

      expect(order, ['first:x', 'second:x']);
    });

    test('listener registered via the event getter receives events', () {
      final emitter = EventEmitter<int>();
      final received = <int>[];
      emitter.event(received.add);

      emitter.emit(42);

      expect(received, [42]);
    });

    test('no listeners is a no-op', () {
      final emitter = EventEmitter<int>();
      expect(() => emitter.emit(1), returnsNormally);
    });
  });

  group('EventSubscription', () {
    test('dispose unsubscribes the listener', () {
      final emitter = EventEmitter<int>();
      final received = <int>[];
      final subscription = emitter(received.add);

      emitter.emit(1);
      subscription.dispose();
      emitter.emit(2);

      expect(received, [1]);
    });

    test('disposing one listener leaves the others active', () {
      final emitter = EventEmitter<int>();
      final first = <int>[];
      final second = <int>[];
      final sub1 = emitter(first.add);
      emitter(second.add);

      sub1.dispose();
      emitter.emit(7);

      expect(first, isEmpty);
      expect(second, [7]);
    });

    test('disposing twice is a harmless no-op', () {
      final emitter = EventEmitter<int>();
      final subscription = emitter((_) {});

      subscription.dispose();
      expect(subscription.dispose, returnsNormally);
    });
  });
}
