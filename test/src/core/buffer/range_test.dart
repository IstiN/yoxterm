import 'package:test/test.dart';
import 'package:yoxterm/xterm.dart';

/// Minimal concrete [BufferRange] used to exercise the base class behavior
/// that both [BufferRangeLine] and [BufferRangeBlock] override.
class _SimpleRange extends BufferRange {
  _SimpleRange(super.begin, super.end);

  @override
  BufferRange get normalized => this;

  @override
  Iterable<BufferSegment> toSegments() => const [];

  @override
  bool contains(CellOffset position) => false;

  @override
  BufferRange merge(BufferRange range) => this;

  @override
  BufferRange extend(CellOffset position) => this;
}

void main() {
  group('BufferRange base class', () {
    test('collapsed range has equal begin and end', () {
      final range = BufferRangeLine.collapsed(CellOffset(3, 4));

      expect(range.begin, CellOffset(3, 4));
      expect(range.end, CellOffset(3, 4));
      expect(range.isCollapsed, isTrue);
      expect(range.isNormalized, isTrue);
    });

    test('isCollapsed is false when begin and end differ', () {
      final range = BufferRangeLine(CellOffset(0, 0), CellOffset(0, 1));

      expect(range.isCollapsed, isFalse);
    });

    test('isNormalized is true when begin is before end', () {
      expect(
        BufferRangeLine(CellOffset(0, 0), CellOffset(0, 1)).isNormalized,
        isTrue,
      );
    });

    test('isNormalized is false when begin is after end', () {
      expect(
        BufferRangeLine(CellOffset(0, 1), CellOffset(0, 0)).isNormalized,
        isFalse,
      );
    });

    test('equality is based on begin and end', () {
      final range = _SimpleRange(CellOffset(1, 2), CellOffset(3, 4));

      expect(range, _SimpleRange(CellOffset(1, 2), CellOffset(3, 4)));
      expect(range, isNot(_SimpleRange(CellOffset(1, 2), CellOffset(3, 5))));
      expect(range, isNot(_SimpleRange(CellOffset(0, 2), CellOffset(3, 4))));
      expect(range == Object(), isFalse);
      expect(range == range, isTrue);
    });

    test('ranges of different subtypes are never equal', () {
      // The base operator== requires identical runtime types, keeping
      // equality symmetric with the subtype overrides that reject operands
      // of other subclasses.
      final range = _SimpleRange(CellOffset(1, 2), CellOffset(3, 4));

      expect(range == BufferRangeLine(CellOffset(1, 2), CellOffset(3, 4)),
          isFalse);
      expect(BufferRangeLine(CellOffset(1, 2), CellOffset(3, 4)) == range,
          isFalse);
      expect(BufferRangeLine(CellOffset(1, 2), CellOffset(3, 4)) ==
          BufferRangeBlock(CellOffset(1, 2), CellOffset(3, 4)), isFalse);
      expect(BufferRangeBlock(CellOffset(1, 2), CellOffset(3, 4)) ==
          BufferRangeLine(CellOffset(1, 2), CellOffset(3, 4)), isFalse);
    });

    test('equal ranges have equal hash codes', () {
      final a = _SimpleRange(CellOffset(1, 2), CellOffset(3, 4));
      final b = _SimpleRange(CellOffset(1, 2), CellOffset(3, 4));

      expect(a.hashCode, b.hashCode);
    });

    test('toString contains begin and end', () {
      final range = _SimpleRange(CellOffset(1, 2), CellOffset(3, 4));

      expect(range.toString(), 'Range(CellOffset(1, 2), CellOffset(3, 4))');
    });
  });
}
