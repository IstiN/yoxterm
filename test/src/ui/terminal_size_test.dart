import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/src/ui/terminal_size.dart';

void main() {
  group('TerminalSize', () {
    test('stores width and height', () {
      const size = TerminalSize(80, 24);
      expect(size.width, 80);
      expect(size.height, 24);
    });

    test('toString includes both dimensions', () {
      expect(const TerminalSize(80, 24).toString(), 'TerminalSize(80, 24)');
      expect(const TerminalSize(0, 0).toString(), 'TerminalSize(0, 0)');
    });

    test('equal sizes compare equal', () {
      expect(const TerminalSize(80, 24), const TerminalSize(80, 24));
      expect(const TerminalSize(80, 24) == const TerminalSize(80, 24), isTrue);
    });

    test('identical instance compares equal', () {
      const size = TerminalSize(80, 24);
      expect(size == size, isTrue);
    });

    test('different width or height compares unequal', () {
      const base = TerminalSize(80, 24);
      expect(base == const TerminalSize(81, 24), isFalse);
      expect(base == const TerminalSize(80, 25), isFalse);
      expect(base == const TerminalSize(81, 25), isFalse);
    });

    test('non-TerminalSize compares unequal', () {
      const size = TerminalSize(80, 24);
      // ignore: unrelated_type_equality_checks
      expect(size == 'TerminalSize(80, 24)', isFalse);
      // ignore: unrelated_type_equality_checks
      expect(size == 8024, isFalse);
    });

    test('equal sizes have equal hashCodes', () {
      expect(
        const TerminalSize(80, 24).hashCode,
        const TerminalSize(80, 24).hashCode,
      );
    });

    test('hashCode differs when a dimension differs', () {
      // Not a strict contract, but guards against hashCode degenerating to a
      // constant (which would silently break hash-based collections).
      final hashes = {
        const TerminalSize(80, 24).hashCode,
        const TerminalSize(81, 24).hashCode,
        const TerminalSize(80, 25).hashCode,
      };
      expect(hashes, hasLength(3));
    });

    test('hashCode differs for swapped dimensions', () {
      // hashCode is Object.hash(width, height), which is order-sensitive, so
      // (80, 24) and (24, 80) must not collide (the previous width ^ height
      // implementation collided on swapped dimensions).
      expect(
        const TerminalSize(80, 24).hashCode,
        isNot(const TerminalSize(24, 80).hashCode),
      );
    });

    test('works as a hash-map key', () {
      final map = <TerminalSize, String>{
        const TerminalSize(80, 24): 'a',
        const TerminalSize(120, 40): 'b',
      };
      expect(map[const TerminalSize(80, 24)], 'a');
      expect(map[const TerminalSize(120, 40)], 'b');
      expect(map[const TerminalSize(80, 25)], isNull);
    });
  });
}
