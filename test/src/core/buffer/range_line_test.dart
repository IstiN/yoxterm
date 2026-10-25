import 'package:test/test.dart';
import 'package:yoxterm/xterm.dart';

void main() {
  group('BufferRangeLine', () {
    test('toSegments() works', () {
      final range = BufferRangeLine(CellOffset(10, 10), CellOffset(10, 12));
      final segments = range.toSegments().toList();

      expect(segments, hasLength(3));

      expect(segments[0].start, equals(10));
      expect(segments[0].end, null);

      expect(segments[1].start, null);
      expect(segments[1].end, null);

      expect(segments[2].start, null);
      expect(segments[2].end, 10);
    });

    test('toSegments() works with reversed range', () {
      final range = BufferRangeLine(CellOffset(10, 12), CellOffset(10, 10));
      final segments = range.toSegments().toList();

      expect(segments, hasLength(3));

      expect(segments[0].start, 10);
      expect(segments[0].end, null);

      expect(segments[1].start, null);
      expect(segments[1].end, null);

      expect(segments[2].start, null);
      expect(segments[2].end, 10);
    });

    test('toSegments(firstLine, lastLine) clips to the visible window', () {
      // A 10k-line selection: only the visible rows are segmented, and the
      // boundary rows keep their partial start/end.
      final range = BufferRangeLine(CellOffset(5, 0), CellOffset(7, 9999));
      final segments =
          range.toSegments(firstLine: 100, lastLine: 123).toList();

      expect(segments, hasLength(24));
      expect(segments.first.line, 100);
      expect(segments.first.start, null);
      expect(segments.first.end, null);
      expect(segments.last.line, 123);
      expect(segments.last.start, null);
      expect(segments.last.end, null);
    });

    test('toSegments(firstLine, lastLine) handles a window outside the range',
        () {
      final range = BufferRangeLine(CellOffset(5, 10), CellOffset(7, 12));

      expect(range.toSegments(firstLine: 0, lastLine: 5), isEmpty);
      expect(range.toSegments(firstLine: 20, lastLine: 30), isEmpty);
    });

    test('toSegments(firstLine, lastLine) works on a reversed range', () {
      final range = BufferRangeLine(CellOffset(7, 12), CellOffset(5, 10));
      final segments =
          range.toSegments(firstLine: 11, lastLine: 11).toList();

      expect(segments, hasLength(1));
      expect(segments.single.line, 11);
      expect(segments.single.start, null);
      expect(segments.single.end, null);
    });

    test('contains() works', () {
      final range = BufferRangeLine(CellOffset(10, 10), CellOffset(10, 12));

      expect(range.contains(CellOffset(10, 10)), isTrue);
      expect(range.contains(CellOffset(10, 11)), isTrue);
      expect(range.contains(CellOffset(10, 12)), isTrue);

      expect(range.contains(CellOffset(10, 9)), isFalse);
      expect(range.contains(CellOffset(10, 13)), isFalse);
    });

    test('contains() works with reversed range', () {
      final range = BufferRangeLine(CellOffset(10, 12), CellOffset(10, 10));

      expect(range.contains(CellOffset(10, 10)), isTrue);
      expect(range.contains(CellOffset(10, 11)), isTrue);
      expect(range.contains(CellOffset(10, 12)), isTrue);

      expect(range.contains(CellOffset(10, 9)), isFalse);
      expect(range.contains(CellOffset(10, 13)), isFalse);
    });

    test('merge() works', () {
      final range1 = BufferRangeLine(CellOffset(10, 10), CellOffset(10, 12));
      final range2 = BufferRangeLine(CellOffset(10, 13), CellOffset(10, 15));

      final merged = range1.merge(range2);

      expect(merged.begin, equals(CellOffset(10, 10)));
      expect(merged.end, equals(CellOffset(10, 15)));
    });

    test('merge() works with reversed range', () {
      final range1 = BufferRangeLine(CellOffset(10, 12), CellOffset(10, 10));
      final range2 = BufferRangeLine(CellOffset(10, 13), CellOffset(10, 15));

      final merged = range1.merge(range2);

      expect(merged.begin, equals(CellOffset(10, 10)));
      expect(merged.end, equals(CellOffset(10, 15)));
    });

    test('extend() works', () {
      final range = BufferRangeLine(CellOffset(10, 10), CellOffset(10, 12));

      final extended = range.extend(CellOffset(10, 13));

      expect(extended.begin, equals(CellOffset(10, 10)));
      expect(extended.end, equals(CellOffset(10, 13)));
    });

    test('extend() works with reversed range', () {
      final range = BufferRangeLine(CellOffset(10, 12), CellOffset(10, 10));

      final extended = range.extend(CellOffset(10, 13));

      expect(extended.begin, equals(CellOffset(10, 10)));
      expect(extended.end, equals(CellOffset(10, 13)));
    });

    test('extend() works with reversed range and reversed extend', () {
      final range = BufferRangeLine(CellOffset(10, 12), CellOffset(10, 10));

      final extended = range.extend(CellOffset(10, 9));

      expect(extended.begin, equals(CellOffset(10, 9)));
      expect(extended.end, equals(CellOffset(10, 12)));
    });
  });
}
