import 'package:test/test.dart';
import 'package:xterm/src/base/disposable.dart';

class _Owner with Disposable {}

class _Child with Disposable {}

void main() {
  group('Disposable', () {
    test('is not disposed initially', () {
      final owner = _Owner();
      expect(owner.disposed, isFalse);
    });

    test('dispose sets the disposed flag', () {
      final owner = _Owner();
      owner.dispose();
      expect(owner.disposed, isTrue);
    });

    test('dispose cascades to registered children', () {
      final owner = _Owner();
      final child = _Child();
      owner.register(child);

      owner.dispose();

      expect(child.disposed, isTrue);
    });

    test('dispose cascades to children in registration order', () {
      final owner = _Owner();
      final order = <String>[];
      owner.registerCallback(() => order.add('first'));
      owner.registerCallback(() => order.add('second'));

      owner.dispose();

      expect(order, ['first', 'second']);
    });

    test('registerCallback runs the callback on dispose', () {
      final owner = _Owner();
      var called = 0;
      owner.registerCallback(() => called++);

      expect(called, 0);
      owner.dispose();
      expect(called, 1);
    });

    test('onDisposed fires when disposed', () {
      final owner = _Owner();
      var fired = 0;
      owner.onDisposed((_) => fired++);

      owner.dispose();

      expect(fired, 1);
    });

    test('children are disposed before onDisposed fires', () {
      final owner = _Owner();
      final order = <String>[];
      owner.registerCallback(() => order.add('child'));
      owner.onDisposed((_) => order.add('onDisposed'));

      owner.dispose();

      expect(order, ['child', 'onDisposed']);
    });

    test('registering after dispose trips the assert in debug mode', () {
      final owner = _Owner();
      owner.dispose();
      expect(() => owner.register(_Child()), throwsA(isA<AssertionError>()));
      expect(
        () => owner.registerCallback(() {}),
        throwsA(isA<AssertionError>()),
      );
    });

    test('disposing twice is a no-op', () {
      final owner = _Owner();
      var callbacks = 0;
      var emissions = 0;
      owner.registerCallback(() => callbacks++);
      owner.onDisposed((_) => emissions++);

      owner.dispose();
      owner.dispose();

      expect(callbacks, 1);
      expect(emissions, 1);
    });
  });
}
