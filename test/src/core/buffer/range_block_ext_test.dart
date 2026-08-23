import 'package:test/test.dart';
import 'package:yoxterm/xterm.dart';

void main() {
  group('BufferRangeBlock.isNormalized', () {
    test('is true for a top-left to bottom-right range', () {
      final range = BufferRangeBlock(CellOffset(5, 10), CellOffset(10, 12));

      expect(range.isNormalized, isTrue);
    });

    test('is false when the columns cross even if the rows are ordered', () {
      // begin is before end in reading order, but begin.x > end.x.
      final range = BufferRangeBlock(CellOffset(10, 10), CellOffset(5, 12));

      expect(range.isNormalized, isFalse);
    });

    test('is false for a fully reversed range', () {
      final range = BufferRangeBlock(CellOffset(12, 12), CellOffset(10, 10));

      expect(range.isNormalized, isFalse);
    });

    test('is true for a collapsed range', () {
      final range = BufferRangeBlock.collapsed(CellOffset(3, 3));

      expect(range.isNormalized, isTrue);
      expect(range.isCollapsed, isTrue);
    });
  });

  group('BufferRangeBlock.normalized', () {
    test('returns the same instance when already normalized', () {
      final range = BufferRangeBlock(CellOffset(5, 10), CellOffset(10, 12));

      expect(identical(range.normalized, range), isTrue);
    });

    test('computes the top-left and bottom-right corners', () {
      final range = BufferRangeBlock(CellOffset(10, 12), CellOffset(5, 10));

      final normalized = range.normalized;

      expect(normalized.begin, CellOffset(5, 10));
      expect(normalized.end, CellOffset(10, 12));
      expect(normalized.isNormalized, isTrue);
    });

    test('fixes crossed columns', () {
      final range = BufferRangeBlock(CellOffset(10, 10), CellOffset(5, 12));

      final normalized = range.normalized;

      expect(normalized.begin, CellOffset(5, 10));
      expect(normalized.end, CellOffset(10, 12));
    });
  });

  group('BufferRangeBlock.toSegments()', () {
    test('yields one segment per row with min/max columns', () {
      final range = BufferRangeBlock(CellOffset(7, 1), CellOffset(3, 3))
          .normalized;

      final segments = range.toSegments().toList();

      expect(segments, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(segments[i].line, 1 + i);
        expect(segments[i].start, 3);
        expect(segments[i].end, 7);
      }
    });

    test('normalizes the corners of a column-crossed range', () {
      // The columns cross (begin.x > end.x) while the rows are ordered;
      // the range is segmented using the normalized corners.
      final range = BufferRangeBlock(CellOffset(10, 10), CellOffset(5, 12));

      final segments = range.toSegments().toList();

      expect(segments, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(segments[i].line, 10 + i);
        expect(segments[i].start, 5);
        expect(segments[i].end, 10);
      }
    });
  });

  group('BufferRangeBlock.contains()', () {
    test('checks both axes for a normalized range', () {
      final range = BufferRangeBlock(CellOffset(3, 1), CellOffset(7, 3));

      expect(range.contains(CellOffset(3, 1)), isTrue);
      expect(range.contains(CellOffset(7, 3)), isTrue);
      expect(range.contains(CellOffset(5, 2)), isTrue);
      expect(range.contains(CellOffset(2, 2)), isFalse);
      expect(range.contains(CellOffset(8, 2)), isFalse);
      expect(range.contains(CellOffset(5, 0)), isFalse);
      expect(range.contains(CellOffset(5, 4)), isFalse);
    });

    test('uses the normalized corners of a column-crossed range', () {
      // The columns cross (begin.x > end.x) while the rows are ordered;
      // positions inside the normalized corners are contained.
      final range = BufferRangeBlock(CellOffset(10, 10), CellOffset(5, 12));

      expect(range.contains(CellOffset(7, 11)), isTrue);
      expect(range.contains(CellOffset(5, 10)), isTrue);
      expect(range.contains(CellOffset(10, 12)), isTrue);
      expect(range.contains(CellOffset(4, 11)), isFalse);
      expect(range.contains(CellOffset(7, 9)), isFalse);
    });
  });

  group('BufferRangeBlock.extend()', () {
    test('returns the same instance when the position is inside', () {
      final range = BufferRangeBlock(CellOffset(5, 5), CellOffset(10, 10));

      expect(identical(range.extend(CellOffset(7, 7)), range), isTrue);
    });

    test('extends the top-left corner', () {
      final range = BufferRangeBlock(CellOffset(5, 5), CellOffset(10, 10));

      final extended = range.extend(CellOffset(2, 3));

      expect(extended.begin, CellOffset(2, 3));
      expect(extended.end, CellOffset(10, 10));
    });

    test('extends the bottom-right corner', () {
      final range = BufferRangeBlock(CellOffset(5, 5), CellOffset(10, 10));

      final extended = range.extend(CellOffset(12, 20));

      expect(extended.begin, CellOffset(5, 5));
      expect(extended.end, CellOffset(12, 20));
    });

    test('extends diagonally on both corners at once', () {
      final range = BufferRangeBlock(CellOffset(10, 10), CellOffset(5, 5));

      final extended = range.extend(CellOffset(0, 20));

      expect(extended.begin, CellOffset(0, 5));
      expect(extended.end, CellOffset(10, 20));
    });
  });

  group('BufferRangeBlock.merge()', () {
    test('extends the block to contain the other range', () {
      final range = BufferRangeBlock(CellOffset(5, 5), CellOffset(10, 10));
      final other = BufferRangeBlock(CellOffset(0, 0), CellOffset(3, 2));

      final merged = range.merge(other);

      expect(merged.begin, CellOffset(0, 0));
      expect(merged.end, CellOffset(10, 10));
    });

    test('works with a BufferRangeLine argument', () {
      final range = BufferRangeBlock(CellOffset(5, 5), CellOffset(10, 10));
      final other = BufferRangeLine(CellOffset(20, 20), CellOffset(25, 25));

      final merged = range.merge(other);

      expect(merged, isA<BufferRangeBlock>());
      expect(merged.begin, CellOffset(5, 5));
      expect(merged.end, CellOffset(25, 25));
    });

    test('with a fully contained range returns an equal block', () {
      final range = BufferRangeBlock(CellOffset(5, 5), CellOffset(10, 10));
      final other = BufferRangeBlock(CellOffset(6, 6), CellOffset(7, 7));

      final merged = range.merge(other);

      expect(merged, range);
    });
  });

  group('BufferRangeBlock equality', () {
    test('equal blocks are equal and have equal hash codes', () {
      final a = BufferRangeBlock(CellOffset(1, 2), CellOffset(3, 4));
      final b = BufferRangeBlock(CellOffset(1, 2), CellOffset(3, 4));

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a block never equals a line range with the same offsets', () {
      final block = BufferRangeBlock(CellOffset(1, 2), CellOffset(3, 4));
      final line = BufferRangeLine(CellOffset(1, 2), CellOffset(3, 4));

      expect(block == line, isFalse);
    });

    test('toString describes the block', () {
      final range = BufferRangeBlock(CellOffset(1, 2), CellOffset(3, 4));

      expect(range.toString(), 'Block Range(CellOffset(1, 2), CellOffset(3, 4))');
    });
  });
}
