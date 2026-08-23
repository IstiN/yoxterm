import 'package:test/test.dart';
import 'package:yoxterm/xterm.dart';

void main() {
  final range = BufferRangeLine(CellOffset(0, 0), CellOffset(0, 0));

  group('BufferSegment construction', () {
    test('asserts that start is not after end', () {
      expect(
        () => BufferSegment(range, 0, 5, 2),
        throwsA(isA<AssertionError>()),
      );
    });

    test('allows null bounds', () {
      final segment = BufferSegment(range, 3, null, null);

      expect(segment.line, 3);
      expect(segment.start, isNull);
      expect(segment.end, isNull);
    });
  });

  group('BufferSegment.isWithin()', () {
    test('a position on another line is never within', () {
      final segment = BufferSegment(range, 3, null, null);

      expect(segment.isWithin(CellOffset(0, 2)), isFalse);
      expect(segment.isWithin(CellOffset(0, 4)), isFalse);
    });

    test('checks only the start when end is null', () {
      final segment = BufferSegment(range, 3, 5, null);

      expect(segment.isWithin(CellOffset(4, 3)), isFalse);
      expect(segment.isWithin(CellOffset(5, 3)), isTrue);
      expect(segment.isWithin(CellOffset(999, 3)), isTrue);
    });

    test('checks only the end when start is null', () {
      final segment = BufferSegment(range, 3, null, 5);

      expect(segment.isWithin(CellOffset(0, 3)), isTrue);
      expect(segment.isWithin(CellOffset(5, 3)), isTrue);
      expect(segment.isWithin(CellOffset(6, 3)), isFalse);
    });
  });

  group('BufferSegment.toString()', () {
    test('renders numeric bounds', () {
      final segment = BufferSegment(range, 3, 2, 5);

      expect(segment.toString(), 'Segment(3, 2 -> 5)');
    });

    test('renders null bounds as start/end', () {
      expect(
        BufferSegment(range, 3, null, null).toString(),
        'Segment(3, start -> end)',
      );
      expect(
        BufferSegment(range, 3, 2, null).toString(),
        'Segment(3, 2 -> end)',
      );
      expect(
        BufferSegment(range, 3, null, 5).toString(),
        'Segment(3, start -> 5)',
      );
    });
  });

  group('BufferSegment equality', () {
    test('equal segments are equal and have equal hash codes', () {
      final a = BufferSegment(range, 1, 2, 3);
      final b = BufferSegment(range, 1, 2, 3);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a, isTrue);
    });

    test('segments differ when any field differs', () {
      final base = BufferSegment(range, 1, 2, 3);

      expect(base, isNot(BufferSegment(range, 0, 2, 3)));
      expect(base, isNot(BufferSegment(range, 1, 0, 3)));
      expect(base, isNot(BufferSegment(range, 1, 2, 4)));
      expect(
        base,
        isNot(
          BufferSegment(
            BufferRangeLine(CellOffset(0, 0), CellOffset(1, 1)),
            1,
            2,
            3,
          ),
        ),
      );
    });

    test('a segment never equals a non-segment object', () {
      expect(BufferSegment(range, 1, 2, 3) == Object(), isFalse);
    });
  });
}
