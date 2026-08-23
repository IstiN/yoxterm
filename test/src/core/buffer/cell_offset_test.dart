import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('CellOffset comparisons', () {
    test('isEqual compares both axes', () {
      expect(CellOffset(1, 2).isEqual(CellOffset(1, 2)), isTrue);
      expect(CellOffset(1, 2).isEqual(CellOffset(2, 2)), isFalse);
      expect(CellOffset(1, 2).isEqual(CellOffset(1, 3)), isFalse);
    });

    test('isBefore uses reading order', () {
      expect(CellOffset(1, 2).isBefore(CellOffset(1, 2)), isFalse);
      expect(CellOffset(1, 2).isBefore(CellOffset(2, 2)), isTrue);
      expect(CellOffset(1, 2).isBefore(CellOffset(0, 2)), isFalse);
      // An earlier row wins regardless of the column.
      expect(CellOffset(9, 1).isBefore(CellOffset(0, 2)), isTrue);
      expect(CellOffset(0, 2).isBefore(CellOffset(9, 1)), isFalse);
    });

    test('isAfter uses reading order', () {
      expect(CellOffset(1, 2).isAfter(CellOffset(1, 2)), isFalse);
      expect(CellOffset(2, 2).isAfter(CellOffset(1, 2)), isTrue);
      expect(CellOffset(0, 2).isAfter(CellOffset(1, 2)), isFalse);
      expect(CellOffset(0, 3).isAfter(CellOffset(9, 2)), isTrue);
      expect(CellOffset(9, 2).isAfter(CellOffset(0, 3)), isFalse);
    });

    test('isBeforeOrSame includes equality', () {
      expect(CellOffset(1, 2).isBeforeOrSame(CellOffset(1, 2)), isTrue);
      expect(CellOffset(1, 2).isBeforeOrSame(CellOffset(2, 2)), isTrue);
      expect(CellOffset(2, 2).isBeforeOrSame(CellOffset(1, 2)), isFalse);
      expect(CellOffset(9, 1).isBeforeOrSame(CellOffset(0, 2)), isTrue);
    });

    test('isAfterOrSame includes equality', () {
      expect(CellOffset(1, 2).isAfterOrSame(CellOffset(1, 2)), isTrue);
      expect(CellOffset(2, 2).isAfterOrSame(CellOffset(1, 2)), isTrue);
      expect(CellOffset(1, 2).isAfterOrSame(CellOffset(2, 2)), isFalse);
      expect(CellOffset(0, 3).isAfterOrSame(CellOffset(9, 2)), isTrue);
    });

    test('isAtSameRow and isAtSameColumn check a single axis', () {
      expect(CellOffset(1, 2).isAtSameRow(CellOffset(9, 2)), isTrue);
      expect(CellOffset(1, 2).isAtSameRow(CellOffset(1, 3)), isFalse);
      expect(CellOffset(1, 2).isAtSameColumn(CellOffset(1, 9)), isTrue);
      expect(CellOffset(1, 2).isAtSameColumn(CellOffset(2, 2)), isFalse);
    });
  });

  group('CellOffset.isWithin()', () {
    test('delegates to the range', () {
      final range = BufferRangeLine(CellOffset(1, 1), CellOffset(3, 3));

      expect(CellOffset(2, 2).isWithin(range), isTrue);
      expect(CellOffset(0, 0).isWithin(range), isFalse);
    });
  });

  group('CellOffset value semantics', () {
    test('equal offsets are equal and have equal hash codes', () {
      const a = CellOffset(1, 2);
      const b = CellOffset(1, 2);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a, isTrue);
    });

    test('offsets differ when any axis differs', () {
      const base = CellOffset(1, 2);

      expect(base, isNot(const CellOffset(0, 2)));
      expect(base, isNot(const CellOffset(1, 3)));
    });

    test('an offset never equals a non-offset object', () {
      expect(const CellOffset(1, 2) == Object(), isFalse);
    });

    test('toString renders both axes', () {
      expect(const CellOffset(1, 2).toString(), 'CellOffset(1, 2)');
    });
  });
}
