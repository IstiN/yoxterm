import 'package:test/test.dart';
import 'package:yoxterm/xterm.dart';

void main() {
  group('BufferRangeLine.normalized', () {
    test('returns the same instance when already normalized', () {
      final range = BufferRangeLine(CellOffset(10, 10), CellOffset(10, 12));

      expect(identical(range.normalized, range), isTrue);
    });

    test('swaps begin and end when reversed', () {
      final range = BufferRangeLine(CellOffset(10, 12), CellOffset(10, 10));

      final normalized = range.normalized;

      expect(normalized.begin, CellOffset(10, 10));
      expect(normalized.end, CellOffset(10, 12));
    });

    test('collapsed range is normalized', () {
      final range = BufferRangeLine.collapsed(CellOffset(3, 3));

      expect(range.isCollapsed, isTrue);
      expect(range.isNormalized, isTrue);
    });
  });

  group('BufferRangeLine.toSegments()', () {
    test('yields a single bounded segment for a single-line range', () {
      final range = BufferRangeLine(CellOffset(3, 1), CellOffset(7, 1));

      final segments = range.toSegments().toList();

      expect(segments, hasLength(1));
      expect(segments[0].line, 1);
      expect(segments[0].start, 3);
      expect(segments[0].end, 7);
    });

    test('segments carry the original (possibly reversed) range', () {
      final range = BufferRangeLine(CellOffset(10, 12), CellOffset(10, 10));

      final segments = range.toSegments().toList();

      expect(segments, hasLength(3));
      for (final segment in segments) {
        expect(identical(segment.range, range), isTrue);
      }
    });
  });

  group('BufferRangeLine.contains()', () {
    test('checks column bounds on a single-line range', () {
      final range = BufferRangeLine(CellOffset(3, 1), CellOffset(7, 1));

      expect(range.contains(CellOffset(3, 1)), isTrue);
      expect(range.contains(CellOffset(7, 1)), isTrue);
      expect(range.contains(CellOffset(2, 1)), isFalse);
      expect(range.contains(CellOffset(8, 1)), isFalse);
      expect(range.contains(CellOffset(5, 0)), isFalse);
      expect(range.contains(CellOffset(5, 2)), isFalse);
    });

    test('any column is inside on a fully covered middle line', () {
      final range = BufferRangeLine(CellOffset(10, 10), CellOffset(10, 12));

      expect(range.contains(CellOffset(0, 11)), isTrue);
      expect(range.contains(CellOffset(999, 11)), isTrue);
    });
  });

  group('BufferRangeLine.merge()', () {
    test('with a fully contained range keeps the extents', () {
      final range = BufferRangeLine(CellOffset(10, 10), CellOffset(10, 15));
      final other = BufferRangeLine(CellOffset(11, 11), CellOffset(11, 12));

      final merged = range.merge(other);

      expect(merged.begin, CellOffset(10, 10));
      expect(merged.end, CellOffset(10, 15));
    });

    test('takes the outermost offsets of both ranges', () {
      final range = BufferRangeLine(CellOffset(10, 10), CellOffset(10, 12));
      final other = BufferRangeLine(CellOffset(5, 8), CellOffset(5, 20));

      final merged = range.merge(other);

      expect(merged.begin, CellOffset(5, 8));
      expect(merged.end, CellOffset(5, 20));
    });

    test('normalizes itself before merging', () {
      final range = BufferRangeLine(CellOffset(10, 12), CellOffset(10, 10));
      final other = BufferRangeLine(CellOffset(0, 20), CellOffset(0, 25));

      final merged = range.merge(other);

      expect(merged.begin, CellOffset(10, 10));
      expect(merged.end, CellOffset(0, 25));
    });
  });

  group('BufferRangeLine.extend()', () {
    test('with a position inside keeps the extents', () {
      final range = BufferRangeLine(CellOffset(10, 10), CellOffset(10, 12));

      final extended = range.extend(CellOffset(11, 11));

      expect(extended.begin, CellOffset(10, 10));
      expect(extended.end, CellOffset(10, 12));
    });

    test('extends the begin when the position is before', () {
      final range = BufferRangeLine(CellOffset(10, 10), CellOffset(10, 12));

      final extended = range.extend(CellOffset(0, 5));

      expect(extended.begin, CellOffset(0, 5));
      expect(extended.end, CellOffset(10, 12));
    });

    test('extends the end when the position is after', () {
      final range = BufferRangeLine(CellOffset(10, 10), CellOffset(10, 12));

      final extended = range.extend(CellOffset(0, 20));

      expect(extended.begin, CellOffset(10, 10));
      expect(extended.end, CellOffset(0, 20));
    });
  });

  group('BufferRangeLine equality', () {
    test('equal line ranges are equal and have equal hash codes', () {
      final a = BufferRangeLine(CellOffset(1, 2), CellOffset(3, 4));
      final b = BufferRangeLine(CellOffset(1, 2), CellOffset(3, 4));

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a line range never equals a block with the same offsets', () {
      final line = BufferRangeLine(CellOffset(1, 2), CellOffset(3, 4));
      final block = BufferRangeBlock(CellOffset(1, 2), CellOffset(3, 4));

      expect(line == block, isFalse);
    });

    test('toString describes the line range', () {
      final range = BufferRangeLine(CellOffset(1, 2), CellOffset(3, 4));

      expect(range.toString(), 'Line Range(CellOffset(1, 2), CellOffset(3, 4))');
    });
  });
}
