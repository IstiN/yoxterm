import 'package:test/test.dart';
import 'package:yoxterm/xterm.dart';

/// Writes [text] (ASCII only) into [line] starting at cell 0.
void writeAscii(BufferLine line, String text) {
  for (var i = 0; i < text.length; i++) {
    line.setCodePoint(i, text.codeUnitAt(i));
  }
}

BufferLine asciiLine(String text, [int cols = 10]) {
  final line = BufferLine(cols);
  writeAscii(line, text);
  return line;
}

void main() {
  group('BufferLine cell access', () {
    test('cells are zeroed by default', () {
      final line = BufferLine(10);

      expect(line.getForeground(3), 0);
      expect(line.getBackground(3), 0);
      expect(line.getAttributes(3), 0);
      expect(line.getContent(3), 0);
      expect(line.getCodePoint(3), 0);
      expect(line.getWidth(3), 0);
    });

    test('setCell stores content, width and style', () {
      final line = BufferLine(10);
      final style = CursorStyle(foreground: 11, background: 22, attrs: 33);

      line.setCell(2, 'A'.codeUnitAt(0), 1, style);

      expect(line.getForeground(2), 11);
      expect(line.getBackground(2), 22);
      expect(line.getAttributes(2), 33);
      expect(line.getCodePoint(2), 'A'.codeUnitAt(0));
      expect(line.getWidth(2), 1);
      expect(
        line.getContent(2),
        'A'.codeUnitAt(0) | (1 << CellContent.widthShift),
      );
    });

    test('setCodePoint stores the codepoint and its measured width', () {
      final line = BufferLine(10);

      line.setCodePoint(0, 'A'.codeUnitAt(0));
      expect(line.getCodePoint(0), 'A'.codeUnitAt(0));
      expect(line.getWidth(0), 1);

      // U+4E16 (世) is an East Asian wide character.
      line.setCodePoint(1, 0x4E16);
      expect(line.getCodePoint(1), 0x4E16);
      expect(line.getWidth(1), 2);
    });

    test('individual setters update individual fields', () {
      final line = BufferLine(10);

      line.setForeground(1, 7);
      line.setBackground(1, 8);
      line.setAttributes(1, 9);
      line.setContent(1, 65 | (2 << CellContent.widthShift));

      expect(line.getForeground(1), 7);
      expect(line.getBackground(1), 8);
      expect(line.getAttributes(1), 9);
      expect(line.getCodePoint(1), 65);
      expect(line.getWidth(1), 2);
    });

    test('getCellData reads all fields of a cell', () {
      final line = BufferLine(10);
      final style = CursorStyle(foreground: 1, background: 2, attrs: 3);
      line.setCell(4, 'X'.codeUnitAt(0), 1, style);

      final cellData = CellData.empty();
      line.getCellData(4, cellData);

      expect(cellData.foreground, 1);
      expect(cellData.background, 2);
      expect(cellData.flags, 3);
      expect(cellData.content, 'X'.codeUnitAt(0) | (1 << CellContent.widthShift));
    });

    test('setCellData writes all fields of a cell', () {
      final line = BufferLine(10);
      final cellData = CellData(
        foreground: 5,
        background: 6,
        flags: 7,
        content: 66 | (1 << CellContent.widthShift),
      );

      line.setCellData(3, cellData);

      expect(line.getForeground(3), 5);
      expect(line.getBackground(3), 6);
      expect(line.getAttributes(3), 7);
      expect(line.getCodePoint(3), 66);
    });

    test('createCellData zeroes the cell and returns empty data', () {
      final line = asciiLine('ABC');

      final cellData = line.createCellData(1);

      expect(cellData.foreground, 0);
      expect(cellData.background, 0);
      expect(cellData.flags, 0);
      expect(cellData.content, 0);
      expect(line.getCodePoint(1), 0);
    });

    test('eraseCell clears the content and applies the style', () {
      final line = asciiLine('ABC');
      final style = CursorStyle(foreground: 1, background: 2, attrs: 3);

      line.eraseCell(1, style);

      expect(line.getCodePoint(1), 0);
      expect(line.getForeground(1), 1);
      expect(line.getBackground(1), 2);
      expect(line.getAttributes(1), 3);
    });

    test('resetCell clears everything including the style', () {
      final line = BufferLine(10);
      line.setCell(1, 65, 1, CursorStyle(foreground: 1, background: 2));

      line.resetCell(1);

      expect(line.getCodePoint(1), 0);
      expect(line.getForeground(1), 0);
      expect(line.getBackground(1), 0);
      expect(line.getAttributes(1), 0);
    });
  });

  group('BufferLine.eraseRange()', () {
    test('erases the given range and applies the style', () {
      final line = asciiLine('ABCDEF');
      final style = CursorStyle(background: 9);

      line.eraseRange(2, 4, style);

      expect(line.getText(0, 6), 'ABEF');
      expect(line.getCodePoint(2), 0);
      expect(line.getCodePoint(3), 0);
      expect(line.getBackground(2), 9);
      expect(line.getBackground(3), 9);
    });

    test('clamps the end to the line length', () {
      final line = asciiLine('ABC', 5);

      // end is past the line length; must not throw.
      line.eraseRange(1, 100, CursorStyle.empty);

      expect(line.getText(0, 5), 'A');
    });

    test('erases a wide char whose second cell is at the start', () {
      final line = BufferLine(10);
      line.setCodePoint(0, 'A'.codeUnitAt(0));
      line.setCodePoint(1, 0x4E16); // 世 occupies cells 1-2
      line.setCodePoint(3, 'B'.codeUnitAt(0));

      // Erasing starts at the second cell of the wide char: the first cell
      // must be erased too, otherwise a dangling wide char would remain.
      line.eraseRange(2, 4, CursorStyle.empty);

      expect(line.getWidth(1), 0);
      expect(line.getCodePoint(1), 0);
      expect(line.getText(0, 4), 'A');
    });

    test('erases a wide char whose first cell is right before the end', () {
      final line = BufferLine(10);
      line.setCodePoint(0, 'A'.codeUnitAt(0));
      line.setCodePoint(1, 0x4E16); // 世 occupies cells 1-2
      line.setCodePoint(3, 'B'.codeUnitAt(0));

      // end - 1 == 1 is the first cell of the wide char.
      line.eraseRange(1, 2, CursorStyle.empty);

      expect(line.getWidth(1), 0);
      expect(line.getText(0, 4), 'AB');
    });
  });

  group('BufferLine.removeCells()', () {
    test('shifts cells left and erases the tail with the given style', () {
      final line = asciiLine('ABCDEF');
      final style = CursorStyle(background: 9);

      line.removeCells(2, 2, style);

      expect(line.getText(0, 10), 'ABEF');
      expect(line.getCodePoint(4), 0);
      // The two freed tail cells are filled with the style.
      expect(line.getBackground(8), 9);
      expect(line.getBackground(9), 9);
    });

    test('removing the whole line erases all cells without shifting', () {
      final line = asciiLine('ABCDEF');

      line.removeCells(0, 10);

      expect(line.getText(0, 10), '');
    });

    test('uses CursorStyle.empty when no style is given', () {
      final line = asciiLine('ABCDEF');
      line.setBackground(3, 42);

      line.removeCells(2, 2);

      expect(line.getText(0, 10), 'ABEF');
      expect(line.getBackground(8), 0);
      expect(line.getBackground(9), 0);
    });

    test('erases a wide char immediately before the removed range', () {
      final line = BufferLine(10);
      line.setCodePoint(0, 'A'.codeUnitAt(0));
      line.setCodePoint(1, 0x4E16); // 世 occupies cells 1-2
      line.setCodePoint(3, 'B'.codeUnitAt(0));

      line.removeCells(2, 1);

      expect(line.getWidth(1), 0);
      expect(line.getCodePoint(1), 0);
      expect(line.getCodePoint(2), 'B'.codeUnitAt(0));
    });

    test('anchor before the removed range is untouched', () {
      final line = asciiLine('ABCDEF');
      final anchor = line.createAnchor(1);

      line.removeCells(2, 2);

      expect(anchor.x, 1);
      expect(anchor.line, same(line));
    });

    test('anchor inside the removed range is disposed', () {
      final line = asciiLine('ABCDEF');
      final anchor = line.createAnchor(3);

      line.removeCells(2, 2);

      expect(anchor.line, isNull);
      expect(line.anchors, isNot(contains(anchor)));
    });

    test('anchor after the removed range is moved left', () {
      final line = asciiLine('ABCDEF');
      final anchor = line.createAnchor(6);

      line.removeCells(2, 2);

      expect(anchor.x, 4);
      expect(anchor.line, same(line));
    });

    test('multiple anchors inside the removed range are all disposed', () {
      final line = asciiLine('ABCDEF');
      final anchorA = line.createAnchor(2);
      final anchorB = line.createAnchor(3);

      line.removeCells(2, 2);

      expect(anchorA.line, isNull);
      expect(anchorB.line, isNull);
      expect(line.anchors, isEmpty);
    });

    test('anchors after the range move even when an earlier anchor is disposed',
        () {
      final line = asciiLine('ABCDEF');
      final disposedAnchor = line.createAnchor(2);
      final movedAnchor = line.createAnchor(6);

      line.removeCells(2, 2);

      expect(disposedAnchor.line, isNull);
      expect(movedAnchor.x, 4);
      expect(movedAnchor.line, same(line));
    });
  });

  group('BufferLine.insertCells()', () {
    test('shifts cells right and fills the gap with the given style', () {
      final line = asciiLine('ABCDEF');
      final style = CursorStyle(background: 9);

      line.insertCells(2, 2, style);

      expect(line.getCodePoint(0), 'A'.codeUnitAt(0));
      expect(line.getCodePoint(1), 'B'.codeUnitAt(0));
      expect(line.getCodePoint(2), 0);
      expect(line.getCodePoint(3), 0);
      expect(line.getCodePoint(4), 'C'.codeUnitAt(0));
      expect(line.getCodePoint(5), 'D'.codeUnitAt(0));
      expect(line.getBackground(2), 9);
      expect(line.getBackground(3), 9);
      // Cells shifted past the end are dropped.
      expect(line.getTrimmedLength(), 8);
    });

    test('inserting the whole line width erases everything', () {
      final line = asciiLine('ABCDEF');

      line.insertCells(0, 10);

      expect(line.getText(0, 10), '');
    });

    test('erases a wide char immediately before the insertion point', () {
      final line = BufferLine(10);
      line.setCodePoint(0, 'A'.codeUnitAt(0));
      line.setCodePoint(1, 0x4E16); // 世 occupies cells 1-2
      line.setCodePoint(3, 'B'.codeUnitAt(0));

      line.insertCells(2, 1);

      expect(line.getWidth(1), 0);
      expect(line.getCodePoint(1), 0);
      // 'B' moved one cell to the right.
      expect(line.getCodePoint(4), 'B'.codeUnitAt(0));
    });

    test('erases a wide char that would overflow the end of the line', () {
      final line = asciiLine('AB');
      line.setCodePoint(8, 0x4E16); // 世 occupies cells 8-9

      // Shifting right pushes the first cell of the wide char to the last
      // column where its second cell no longer fits.
      line.insertCells(0, 1);

      expect(line.getCodePoint(9), 0);
      expect(line.getWidth(9), 0);
    });

    test('anchor before the insertion point is untouched', () {
      final line = asciiLine('ABCDEF');
      final anchor = line.createAnchor(1);

      line.insertCells(2, 2);

      expect(anchor.x, 1);
      expect(anchor.line, same(line));
    });

    test('anchor inside the inserted range keeps its position', () {
      final line = asciiLine('ABCDEF');
      final anchor = line.createAnchor(3);

      line.insertCells(2, 2);

      // Only anchors at or after start + count are moved.
      expect(anchor.x, 3);
      expect(anchor.line, same(line));
    });

    test('anchor at or after the end of the inserted range is moved right', () {
      final line = asciiLine('ABCDEF');
      final anchor = line.createAnchor(4);

      line.insertCells(2, 2);

      expect(anchor.x, 6);
      expect(anchor.line, same(line));
    });

    test('anchor pushed past the end of the line is disposed', () {
      final line = asciiLine('ABCDEF');
      final anchor = line.createAnchor(9);

      line.insertCells(0, 2);

      expect(anchor.line, isNull);
      expect(line.anchors, isNot(contains(anchor)));
    });

    test('all anchors pushed past the end of the line are disposed', () {
      final line = asciiLine('ABCDEF');
      final anchorA = line.createAnchor(8);
      final anchorB = line.createAnchor(9);

      line.insertCells(0, 2);

      expect(anchorA.line, isNull);
      expect(anchorB.line, isNull);
      expect(line.anchors, isEmpty);
    });
  });

  group('BufferLine.resize()', () {
    test('growing keeps content and zero-fills the new cells', () {
      final line = asciiLine('ABCDEF', 6);

      line.resize(10);

      expect(line.length, 10);
      expect(line.getText(0, 10), 'ABCDEF');
      expect(line.getCodePoint(9), 0);
    });

    test('growing within capacity keeps the same backing store', () {
      final line = asciiLine('ABCDEF', 6);
      final before = line.data;

      line.resize(10);

      expect(identical(before, line.data), isTrue);
    });

    test('growing beyond capacity reallocates the backing store', () {
      final line = asciiLine('ABCDEF', 6);
      // Default capacity is 64 cells.
      expect(line.data.length, 64 * 4);

      line.resize(100);

      // Capacity doubles while below 256 cells: 64 -> 128.
      expect(line.data.length, 128 * 4);
      expect(line.getText(0, 100), 'ABCDEF');
    });

    test('growing past 256 cells grows capacity in steps of 32', () {
      final line = BufferLine(10);

      line.resize(300);

      // 256 -> 288 -> 320.
      expect(line.data.length, 320 * 4);
      expect(line.length, 300);
    });

    test('shrinking reduces the visible length', () {
      final line = asciiLine('ABCDEF');

      line.resize(4);

      expect(line.length, 4);
      expect(line.getText(), 'ABCD');
    });

    test('resizing to the same length is a no-op', () {
      final line = asciiLine('ABCDEF');
      final before = line.data;

      line.resize(10);

      expect(line.length, 10);
      expect(identical(before, line.data), isTrue);
      expect(line.getText(), 'ABCDEF');
    });

    test('anchors beyond the new length are clamped to the new length', () {
      final line = asciiLine('ABCDEF');
      final anchor = line.createAnchor(8);

      line.resize(5);

      expect(anchor.x, 5);
      expect(anchor.line, same(line));
    });
  });

  group('BufferLine.getTrimmedLength()', () {
    test('an empty line has trimmed length 0', () {
      expect(BufferLine(10).getTrimmedLength(), 0);
    });

    test('trailing blank cells are not counted', () {
      final line = asciiLine('ABC');

      expect(line.getTrimmedLength(), 3);
    });

    test('a wide char at the end counts for two cells', () {
      final line = BufferLine(10);
      line.setCodePoint(0, 'A'.codeUnitAt(0));
      line.setCodePoint(1, 0x4E16); // 世 occupies cells 1-2

      expect(line.getTrimmedLength(), 3);
    });

    test('respects the cols limit', () {
      final line = asciiLine('ABCDEF');

      expect(line.getTrimmedLength(4), 4);
    });
  });

  group('BufferLine.copyFrom()', () {
    test('copies cells and grows the line when needed', () {
      final src = asciiLine('ABCDEF');
      final dst = BufferLine(4);
      dst.setCodePoint(0, 'x'.codeUnitAt(0));

      dst.copyFrom(src, 1, 3, 2);

      expect(dst.length, 5);
      expect(dst.getCodePoint(0), 'x'.codeUnitAt(0));
      expect(dst.getCodePoint(3), 'B'.codeUnitAt(0));
      expect(dst.getCodePoint(4), 'C'.codeUnitAt(0));
    });
  });

  group('BufferLine.getText()', () {
    test('excludes a wide char that crosses the end of the range', () {
      final line = BufferLine(10);
      line.setCodePoint(0, 'A'.codeUnitAt(0));
      line.setCodePoint(1, 0x4E16); // 世 occupies cells 1-2
      line.setCodePoint(3, 'B'.codeUnitAt(0));

      expect(line.getText(0, 2), 'A');
      expect(line.getText(0, 3), 'A世');
      expect(line.getText(0, 4), 'A世B');
    });
  });

  group('BufferLine anchors', () {
    test('createAnchor registers the anchor with the line', () {
      final line = BufferLine(10);

      final anchor = line.createAnchor(4);

      expect(anchor.x, 4);
      expect(anchor.line, same(line));
      expect(line.anchors, contains(anchor));
    });

    test('reposition moves the anchor', () {
      final line = BufferLine(10);
      final anchor = line.createAnchor(4);

      anchor.reposition(7);

      expect(anchor.x, 7);
    });

    test('dispose detaches the anchor from the line', () {
      final line = BufferLine(10);
      final anchor = line.createAnchor(4);

      anchor.dispose();

      expect(anchor.line, isNull);
      expect(line.anchors, isEmpty);
    });

    test('reparent moves the anchor to another line', () {
      final lineA = BufferLine(10);
      final lineB = BufferLine(10);
      final anchor = lineA.createAnchor(4);

      anchor.reparent(lineB, 7);

      expect(anchor.x, 7);
      expect(anchor.line, same(lineB));
      expect(lineA.anchors, isEmpty);
      expect(lineB.anchors, contains(anchor));
    });

    test('an anchor on a detached line is not attached', () {
      final line = BufferLine(10);
      final anchor = line.createAnchor(4);

      // The line itself is not part of a buffer.
      expect(anchor.attached, isFalse);
    });

    test('attached anchors expose y and offset', () {
      final terminal = Terminal();
      final line = terminal.buffer.lines[3];

      final anchor = line.createAnchor(5);

      expect(anchor.attached, isTrue);
      expect(anchor.y, 3);
      expect(anchor.offset, CellOffset(5, 3));
    });

    test('toString reflects the attachment state', () {
      final terminal = Terminal();
      final anchor = terminal.buffer.lines[3].createAnchor(5);

      expect(anchor.toString(), 'CellAnchor(5, 3)');

      anchor.dispose();

      expect(anchor.toString(), 'CellAnchor(5, detached)');
    });
  });

  group('BufferLine.reset()', () {
    test('clears content, wrap flag and anchors', () {
      final line = asciiLine('ABCDEF');
      line.isWrapped = true;
      final anchor = line.createAnchor(3);

      line.reset();

      expect(line.getText(), '');
      expect(line.getTrimmedLength(), 0);
      expect(line.isWrapped, isFalse);
      expect(line.anchors, isEmpty);
      expect(anchor.line, isNull);
    });
  });

  group('BufferLine.dispose()', () {
    test('succeeds when the line has no anchors', () {
      final line = asciiLine('ABCDEF');

      line.dispose();

      expect(line.anchors, isEmpty);
    });

    test('detaches all anchors without throwing', () {
      final line = asciiLine('ABCDEF');
      final anchorA = line.createAnchor(2);
      final anchorB = line.createAnchor(5);

      expect(line.dispose, returnsNormally);

      expect(line.anchors, isEmpty);
      expect(anchorA.line, isNull);
      expect(anchorB.line, isNull);
    });
  });

  group('BufferLine.toString()', () {
    test('returns the line text', () {
      expect(asciiLine('ABCDEF').toString(), 'ABCDEF');
      expect(BufferLine(10).toString(), '');
    });
  });
}
