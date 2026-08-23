import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

Terminal createTerminal({
  int width = 10,
  int height = 5,
  bool reflowEnabled = true,
  int maxLines = 1000,
}) {
  final terminal = Terminal(
    reflowEnabled: reflowEnabled,
    maxLines: maxLines,
  );
  terminal.resize(width, height);
  return terminal;
}

void main() {
  group('Buffer construction', () {
    test('is pre-filled with empty lines matching the view height', () {
      final terminal = createTerminal(width: 7, height: 4);
      final buffer = terminal.buffer;

      expect(buffer.height, 4);
      expect(buffer.viewWidth, 7);
      expect(buffer.viewHeight, 4);
      expect(buffer.scrollBack, 0);
      for (var i = 0; i < buffer.height; i++) {
        expect(buffer.lines[i].getText(), '');
      }
    });

    test('exposes whether it is the alt buffer', () {
      final terminal = createTerminal();

      expect(terminal.mainBuffer.isAltBuffer, isFalse);
      expect(terminal.altBuffer.isAltBuffer, isTrue);
    });

    test('has full-width vertical margins by default', () {
      final terminal = createTerminal(width: 10, height: 5);

      expect(terminal.buffer.marginTop, 0);
      expect(terminal.buffer.marginBottom, 4);
      expect(terminal.buffer.absoluteMarginTop, 0);
      expect(terminal.buffer.absoluteMarginBottom, 4);
    });
  });

  group('Buffer.write()', () {
    test('writes text and advances the cursor', () {
      final terminal = createTerminal();

      terminal.buffer.write('abc');

      expect(terminal.buffer.lines[0].getText(), 'abc');
      expect(terminal.buffer.cursorX, 3);
      expect(terminal.buffer.cursorY, 0);
    });

    test('combines UTF-16 surrogate pairs into a single code point', () {
      final terminal = createTerminal();

      terminal.buffer.write('😀');

      expect(terminal.buffer.lines[0].getCodePoint(0), 0x1F600);
      expect(terminal.buffer.lines[0].getWidth(0), 2);
      expect(terminal.buffer.cursorX, 2);
    });

    test('writes a lone high surrogate at the end of the string as-is', () {
      final terminal = createTerminal();

      terminal.buffer.write('a\uD800');

      expect(terminal.buffer.lines[0].getCodePoint(0), 'a'.codeUnitAt(0));
      expect(terminal.buffer.lines[0].getCodePoint(1), 0xD800);
    });

    test('writes a high surrogate not followed by a low surrogate as-is', () {
      final terminal = createTerminal();

      terminal.buffer.write('\uD800b');

      expect(terminal.buffer.lines[0].getCodePoint(0), 0xD800);
      expect(terminal.buffer.lines[0].getCodePoint(1), 'b'.codeUnitAt(0));
    });

    test('writeChar applies the active charset translation', () {
      final terminal = createTerminal();
      terminal.buffer.charset.designate(0, '0'.codeUnitAt(0));
      terminal.buffer.charset.use(0);

      // 'q' maps to BOX DRAWINGS LIGHT HORIZONTAL in DEC special graphics.
      terminal.buffer.writeChar(0x71);

      expect(terminal.buffer.lines[0].getCodePoint(0), 0x2500);
    });

    test('marks the continuation line as wrapped when auto-wrap is on', () {
      final terminal = createTerminal(width: 4);

      terminal.buffer.write('ABCDE');

      expect(terminal.buffer.lines[0].getText(), 'ABCD');
      expect(terminal.buffer.lines[0].isWrapped, isFalse);
      expect(terminal.buffer.lines[1].getText(), 'E');
      expect(terminal.buffer.lines[1].isWrapped, isTrue);
      expect(terminal.buffer.cursorY, 1);
    });

    test('with auto-wrap off the cursor stays at the last column and overwrites',
        () {
      final terminal = createTerminal(width: 4);
      terminal.setAutoWrapMode(false);

      terminal.buffer.write('ABCDE');

      // 'E' overwrites the last cell instead of flowing to the next line.
      expect(terminal.buffer.lines[0].getText(), 'ABCE');
      expect(terminal.buffer.lines[1].getText(), '');
      expect(terminal.buffer.lines[1].isWrapped, isFalse);
    });

    test('cursor stays at the last column while a wrap is pending', () {
      final terminal = createTerminal(width: 4);

      terminal.buffer.write('ABCD');

      expect(terminal.buffer.cursorX, 3);
      expect(terminal.buffer.cursorY, 0);
    });

    test('a wide char at the last column wraps its continuation cell', () {
      final terminal = createTerminal(width: 5);

      // 世 is written at the last column (width 2); the cell holding the
      // second half overflows to the next line.
      terminal.buffer.write('ABCD世');

      final line0 = terminal.buffer.lines[0];
      expect(line0.getWidth(4), 2);
      // getText excludes wide chars that cross the line end.
      expect(line0.getText(), 'ABCD');
      expect(terminal.buffer.lines[1].isWrapped, isTrue);
      expect(terminal.buffer.cursorY, 1);
    });
  });

  group('Buffer.currentLine', () {
    test('returns the line under the cursor', () {
      final terminal = createTerminal();
      terminal.buffer.write('abc');

      expect(
        identical(
          terminal.buffer.currentLine,
          terminal.buffer.lines[terminal.buffer.absoluteCursorY],
        ),
        isTrue,
      );
      expect(terminal.buffer.currentLine.getText(), 'abc');
    });
  });

  group('Buffer.backspace()', () {
    test('moves the cursor one cell left', () {
      final terminal = createTerminal();
      terminal.buffer.write('abc');

      terminal.buffer.backspace();

      expect(terminal.buffer.cursorX, 2);
    });

    test('moves two cells left when a wrap is pending', () {
      final terminal = createTerminal(width: 4);
      terminal.buffer.write('ABCD');

      terminal.buffer.backspace();

      expect(terminal.buffer.cursorX, 2);
      expect(terminal.buffer.cursorY, 0);
    });

    test('at column 0 of a wrapped line unwraps and moves to the line above',
        () {
      final terminal = createTerminal(width: 4);
      terminal.buffer.write('ABCDE');
      expect(terminal.buffer.lines[1].isWrapped, isTrue);

      terminal.buffer.setCursorX(0);
      terminal.buffer.backspace();

      expect(terminal.buffer.lines[1].isWrapped, isFalse);
      expect(terminal.buffer.cursorX, 3);
      expect(terminal.buffer.cursorY, 0);
    });

    test('at column 0 of a non-wrapped line stays at the line start', () {
      final terminal = createTerminal();
      terminal.buffer.setCursor(0, 2);

      terminal.buffer.backspace();

      expect(terminal.buffer.cursorX, 0);
      expect(terminal.buffer.cursorY, 2);
    });
  });

  group('Buffer erase operations', () {
    test('eraseDisplayToCursor erases everything above and before the cursor',
        () {
      final terminal = createTerminal(width: 3, height: 3);
      terminal.write('123\r\n456\r\n789');

      terminal.setCursor(1, 1);
      terminal.buffer.eraseDisplayToCursor();

      expect(terminal.buffer.lines[0].getText(), '');
      // eraseLineToCursor erases [0, cursorX], so the cell under the cursor
      // is erased too.
      expect(terminal.buffer.lines[1].getText(), '6');
      expect(terminal.buffer.lines[1].getCodePoint(0), 0);
      expect(terminal.buffer.lines[1].getCodePoint(1), 0);
      expect(terminal.buffer.lines[2].getText(), '789');
    });

    test('eraseDisplay erases the whole viewport', () {
      final terminal = createTerminal(width: 3, height: 3);
      terminal.write('123\r\n456\r\n789');

      terminal.buffer.eraseDisplay();

      for (var i = 0; i < 3; i++) {
        expect(terminal.buffer.lines[i].getText(), '');
        expect(terminal.buffer.lines[i].isWrapped, isFalse);
      }
    });

    test('eraseLineFromCursor erases from the cursor to the line end', () {
      final terminal = createTerminal();
      terminal.buffer.write('ABCDEF');

      terminal.buffer.setCursorX(2);
      terminal.buffer.eraseLineFromCursor();

      expect(terminal.buffer.lines[0].getText(), 'AB');
    });

    test('eraseLineToCursor erases from the line start through the cursor',
        () {
      final terminal = createTerminal();
      terminal.buffer.write('ABCDEF');

      terminal.buffer.setCursorX(3);
      terminal.buffer.eraseLineToCursor();

      expect(terminal.buffer.lines[0].getText(), 'EF');
    });

    test('eraseLine erases the whole line and clears the wrap flag', () {
      final terminal = createTerminal(width: 4);
      terminal.buffer.write('ABCDE');
      expect(terminal.buffer.lines[1].isWrapped, isTrue);

      terminal.buffer.setCursor(0, 1);
      terminal.buffer.eraseLine();

      expect(terminal.buffer.lines[1].getText(), '');
      expect(terminal.buffer.lines[1].isWrapped, isFalse);
      expect(terminal.buffer.lines[0].getText(), 'ABCD');
    });

    test('eraseChars erases count cells from the cursor without shifting', () {
      final terminal = createTerminal();
      terminal.buffer.write('ABCDEFGH');

      terminal.buffer.setCursorX(2);
      terminal.buffer.eraseChars(3);

      final line = terminal.buffer.lines[0];
      expect(line.getText(), 'ABFGH');
      expect(line.getCodePoint(2), 0);
      expect(line.getCodePoint(5), 'F'.codeUnitAt(0));
    });

    test('eraseChars clamps to the line width', () {
      final terminal = createTerminal();
      terminal.buffer.write('ABCDEFGHIJ');

      terminal.buffer.setCursorX(8);
      terminal.buffer.eraseChars(100);

      expect(terminal.buffer.lines[0].getText(), 'ABCDEFGH');
    });
  });

  group('Buffer scrolling', () {
    test('scrollUp shifts lines up inside the scroll region only', () {
      final terminal = createTerminal(width: 10, height: 5);
      terminal.write('l0\r\nl1\r\nl2\r\nl3\r\nl4');
      terminal.setMargins(1, 3);

      terminal.buffer.scrollUp(1);

      expect(terminal.buffer.lines[0].getText(), 'l0');
      expect(terminal.buffer.lines[1].getText(), 'l2');
      expect(terminal.buffer.lines[2].getText(), 'l3');
      expect(terminal.buffer.lines[3].getText(), '');
      expect(terminal.buffer.lines[4].getText(), 'l4');
    });

    test('scrollDown shifts lines down inside the scroll region only', () {
      final terminal = createTerminal(width: 10, height: 5);
      terminal.write('l0\r\nl1\r\nl2\r\nl3\r\nl4');
      terminal.setMargins(1, 3);

      terminal.buffer.scrollDown(1);

      expect(terminal.buffer.lines[0].getText(), 'l0');
      expect(terminal.buffer.lines[1].getText(), '');
      expect(terminal.buffer.lines[2].getText(), 'l1');
      expect(terminal.buffer.lines[3].getText(), 'l2');
      expect(terminal.buffer.lines[4].getText(), 'l4');
    });
  });

  group('Buffer.index()', () {
    test('moves the cursor down when not at the bottom margin', () {
      final terminal = createTerminal(width: 10, height: 3);

      terminal.buffer.index();

      expect(terminal.buffer.cursorY, 1);
      expect(terminal.buffer.height, 3);
    });

    test('at the bottom margin pushes a new line into the scrollback', () {
      final terminal = createTerminal(width: 10, height: 3);
      terminal.write('a\r\nb\r\nc');

      terminal.buffer.index();

      expect(terminal.buffer.height, 4);
      expect(terminal.buffer.scrollBack, 1);
      expect(terminal.buffer.lines[0].getText(), 'a');
      expect(terminal.buffer.lines[3].getText(), '');
      expect(terminal.buffer.absoluteCursorY, 3);
      expect(terminal.buffer.currentLine.getText(), '');
    });

    test('on the alt buffer scrolls without growing the buffer', () {
      final terminal = createTerminal(width: 10, height: 3);
      terminal.useAltBuffer();
      terminal.write('a\r\nb\r\nc');

      terminal.buffer.index();

      expect(terminal.buffer.height, 3);
      expect(terminal.buffer.lines[0].getText(), 'b');
      expect(terminal.buffer.lines[1].getText(), 'c');
      expect(terminal.buffer.lines[2].getText(), '');
    });

    test('outside the scroll region at the bottom pushes a new line', () {
      final terminal = createTerminal(width: 10, height: 3);
      terminal.write('a\r\nb\r\nc');
      terminal.setMargins(0, 0);
      terminal.setCursor(0, 2);

      terminal.buffer.index();

      expect(terminal.buffer.height, 4);
      expect(terminal.buffer.lines[3].getText(), '');
    });

    test('outside the scroll region not at the bottom just moves the cursor',
        () {
      final terminal = createTerminal(width: 10, height: 5);
      terminal.setMargins(2, 4);
      terminal.setCursor(0, 0);

      terminal.buffer.index();

      expect(terminal.buffer.cursorY, 1);
      expect(terminal.buffer.height, 5);
    });
  });

  group('Buffer.reverseIndex()', () {
    test('at the top margin scrolls the region down', () {
      final terminal = createTerminal(width: 10, height: 3);
      terminal.write('a\r\nb\r\nc');
      terminal.setCursor(0, 0);

      terminal.buffer.reverseIndex();

      expect(terminal.buffer.cursorY, 0);
      expect(terminal.buffer.lines[0].getText(), '');
      expect(terminal.buffer.lines[1].getText(), 'a');
      expect(terminal.buffer.lines[2].getText(), 'b');
    });

    test('inside the region moves the cursor up', () {
      final terminal = createTerminal(width: 10, height: 3);
      terminal.setCursor(0, 2);

      terminal.buffer.reverseIndex();

      expect(terminal.buffer.cursorY, 1);
    });

    test('outside the scroll region just moves the cursor up', () {
      final terminal = createTerminal(width: 10, height: 5);
      terminal.write('a\r\nb\r\nc');
      terminal.setMargins(2, 4);
      terminal.setCursor(0, 1);

      terminal.buffer.reverseIndex();

      expect(terminal.buffer.cursorY, 0);
      expect(terminal.buffer.lines[0].getText(), 'a');
      expect(terminal.buffer.lines[1].getText(), 'b');
    });

    test('at the very top does not scroll when outside the scroll region', () {
      final terminal = createTerminal(width: 10, height: 5);
      terminal.write('a');
      terminal.setMargins(2, 4);
      terminal.setCursor(0, 0);

      terminal.buffer.reverseIndex();

      expect(terminal.buffer.cursorY, 0);
      expect(terminal.buffer.lines[0].getText(), 'a');
    });
  });

  group('Buffer.lineFeed()', () {
    test('keeps the column when line feed mode is off', () {
      final terminal = createTerminal();
      terminal.setCursor(3, 0);

      terminal.buffer.lineFeed();

      expect(terminal.buffer.cursorX, 3);
      expect(terminal.buffer.cursorY, 1);
    });

    test('resets the column when line feed mode is on', () {
      final terminal = createTerminal();
      terminal.setLineFeedMode(true);
      terminal.setCursor(3, 0);

      terminal.buffer.lineFeed();

      expect(terminal.buffer.cursorX, 0);
      expect(terminal.buffer.cursorY, 1);
    });
  });

  group('Buffer cursor movement clamping', () {
    test('setCursorX clamps to the viewport', () {
      final terminal = createTerminal(width: 10);

      terminal.buffer.setCursorX(-3);
      expect(terminal.buffer.cursorX, 0);

      terminal.buffer.setCursorX(999);
      expect(terminal.buffer.cursorX, 9);
    });

    test('setCursorY clamps to the viewport', () {
      final terminal = createTerminal(height: 5);

      terminal.buffer.setCursorY(-3);
      expect(terminal.buffer.cursorY, 0);

      terminal.buffer.setCursorY(999);
      expect(terminal.buffer.cursorY, 4);
    });

    test('setCursor clamps both axes to the viewport', () {
      final terminal = createTerminal(width: 10, height: 5);

      terminal.buffer.setCursor(-1, -1);
      expect(terminal.buffer.cursorX, 0);
      expect(terminal.buffer.cursorY, 0);

      terminal.buffer.setCursor(999, 999);
      expect(terminal.buffer.cursorX, 9);
      expect(terminal.buffer.cursorY, 4);
    });

    test('cursorGoForward does not move past the last column', () {
      final terminal = createTerminal(width: 10);
      terminal.buffer.setCursorX(8);

      terminal.buffer.cursorGoForward();
      expect(terminal.buffer.cursorX, 9);

      terminal.buffer.cursorGoForward();
      expect(terminal.buffer.cursorX, 9);
    });

    test('moveCursor moves relative and clamps', () {
      final terminal = createTerminal(width: 10, height: 5);
      terminal.buffer.setCursor(5, 2);

      terminal.buffer.moveCursor(2, 1);
      expect(terminal.buffer.cursorX, 7);
      expect(terminal.buffer.cursorY, 3);

      terminal.buffer.moveCursor(-99, -99);
      expect(terminal.buffer.cursorX, 0);
      expect(terminal.buffer.cursorY, 0);
    });

    test('setCursor is relative to the margins in origin mode', () {
      final terminal = createTerminal(width: 10, height: 5);
      terminal.setMargins(1, 3);
      terminal.setOriginMode(true);

      terminal.buffer.setCursor(0, 0);
      expect(terminal.buffer.cursorY, 1);

      // Clamped to the bottom margin instead of the viewport bottom.
      terminal.buffer.setCursor(0, 100);
      expect(terminal.buffer.cursorY, 3);

      terminal.setOriginMode(false);
      terminal.buffer.setCursor(0, 100);
      expect(terminal.buffer.cursorY, 4);
    });
  });

  group('Buffer.saveCursor() / restoreCursor()', () {
    test('saves and restores the cursor position and style', () {
      final terminal = createTerminal();
      terminal.setCursor(5, 3);
      terminal.setCursorBold();
      terminal.setForegroundColor16(3);

      terminal.buffer.saveCursor();

      terminal.setCursor(0, 0);
      terminal.cursor.reset();
      expect(terminal.cursor.isBold, isFalse);

      terminal.buffer.restoreCursor();

      expect(terminal.buffer.cursorX, 5);
      expect(terminal.buffer.cursorY, 3);
      expect(terminal.cursor.isBold, isTrue);
      expect(terminal.cursor.foreground, 3 | CellColor.named);
    });

    test('saves and restores the charset state', () {
      final terminal = createTerminal();

      terminal.buffer.saveCursor();

      terminal.buffer.charset.designate(0, '0'.codeUnitAt(0));
      terminal.buffer.charset.use(0);
      expect(terminal.buffer.charset.translate(0x71), 0x2500);

      terminal.buffer.restoreCursor();

      expect(terminal.buffer.charset.translate(0x71), 0x71);
    });
  });

  group('Buffer vertical margins', () {
    test('top greater than bottom swaps the margins', () {
      final terminal = createTerminal(height: 5);

      terminal.setMargins(3, 1);

      // The margins are normalized by swapping them, so setMargins(3, 1)
      // results in the scroll region (1, 3).
      expect(terminal.buffer.marginTop, 1);
      expect(terminal.buffer.marginBottom, 3);
    });

    test('clamps margins to the viewport', () {
      final terminal = createTerminal(height: 5);

      terminal.setMargins(-5, 100);

      expect(terminal.buffer.marginTop, 0);
      expect(terminal.buffer.marginBottom, 4);
    });

    test('resetVerticalMargins restores full-height margins', () {
      final terminal = createTerminal(height: 5);
      terminal.setMargins(1, 2);

      terminal.buffer.resetVerticalMargins();

      expect(terminal.buffer.marginTop, 0);
      expect(terminal.buffer.marginBottom, 4);
    });

    test('isInVerticalMargin reflects the cursor position', () {
      final terminal = createTerminal(height: 5);
      terminal.setMargins(1, 3);

      terminal.buffer.setCursorY(0);
      expect(terminal.buffer.isInVerticalMargin, isFalse);

      terminal.buffer.setCursorY(1);
      expect(terminal.buffer.isInVerticalMargin, isTrue);

      terminal.buffer.setCursorY(3);
      expect(terminal.buffer.isInVerticalMargin, isTrue);

      terminal.buffer.setCursorY(4);
      expect(terminal.buffer.isInVerticalMargin, isFalse);
    });

    test('absolute margins include the scrollback offset', () {
      final terminal = createTerminal(width: 10, height: 3);
      terminal.write('l0\r\nl1\r\nl2\r\nl3\r\nl4');

      expect(terminal.buffer.scrollBack, 2);
      expect(terminal.buffer.marginTop, 0);
      expect(terminal.buffer.marginBottom, 2);
      expect(terminal.buffer.absoluteMarginTop, 2);
      expect(terminal.buffer.absoluteMarginBottom, 4);
    });
  });

  group('Buffer.deleteChars()', () {
    test('removes cells at the cursor and shifts the rest left', () {
      final terminal = createTerminal();
      terminal.buffer.write('ABCDEFGH');

      terminal.buffer.setCursorX(2);
      terminal.buffer.deleteChars(3);

      final line = terminal.buffer.lines[0];
      expect(line.getText(), 'ABFGH');
      expect(line.getCodePoint(4), 'H'.codeUnitAt(0));
      expect(line.getCodePoint(5), 0);
    });

    test('clamps the count to the remaining line width', () {
      final terminal = createTerminal();
      terminal.buffer.write('ABCDEFGHIJ');

      terminal.buffer.setCursorX(8);
      terminal.buffer.deleteChars(100);

      expect(terminal.buffer.lines[0].getText(), 'ABCDEFGH');
    });
  });

  group('Buffer.insertBlankChars()', () {
    test('inserts blank cells at the cursor', () {
      final terminal = createTerminal();
      terminal.buffer.write('ABCD');

      terminal.buffer.setCursorX(1);
      terminal.buffer.insertBlankChars(2);

      final line = terminal.buffer.lines[0];
      expect(line.getCodePoint(0), 'A'.codeUnitAt(0));
      expect(line.getCodePoint(1), 0);
      expect(line.getCodePoint(2), 0);
      expect(line.getCodePoint(3), 'B'.codeUnitAt(0));
      expect(line.getText(), 'ABCD');
    });
  });

  group('Buffer.insertLines()', () {
    test('clamps the count to the remaining lines of the scroll region', () {
      final terminal = Terminal();
      for (var i = 0; i < 10; i++) {
        terminal.write('line$i\r\n');
      }
      terminal.setMargins(2, 6);
      terminal.setCursor(0, 4);

      terminal.buffer.insertLines(100);

      expect(terminal.buffer.lines[3].getText(), 'line3');
      expect(terminal.buffer.lines[4].getText(), '');
      expect(terminal.buffer.lines[5].getText(), '');
      expect(terminal.buffer.lines[6].getText(), '');
      expect(terminal.buffer.lines[7].getText(), 'line7');
    });
  });

  group('Buffer.deleteLines()', () {
    test('has no effect if the cursor is out of the scroll region', () {
      final terminal = Terminal();
      for (var i = 0; i < 10; i++) {
        terminal.write('line$i\r\n');
      }
      terminal.setMargins(2, 6);
      terminal.setCursor(0, 1);

      terminal.buffer.deleteLines(2);

      expect(terminal.buffer.lines[2].getText(), 'line2');
      expect(terminal.buffer.lines[6].getText(), 'line6');
    });
  });

  group('Buffer.clearScrollback()', () {
    test('drops all lines above the viewport', () {
      final terminal = createTerminal(width: 10, height: 3);
      terminal.write('l0\r\nl1\r\nl2\r\nl3\r\nl4');
      expect(terminal.buffer.scrollBack, 2);

      terminal.buffer.clearScrollback();

      expect(terminal.buffer.height, 3);
      expect(terminal.buffer.scrollBack, 0);
      expect(terminal.buffer.lines[0].getText(), 'l2');
      expect(terminal.buffer.lines[2].getText(), 'l4');
    });

    test('does nothing when there is no scrollback', () {
      final terminal = createTerminal(width: 10, height: 3);
      terminal.write('a');

      terminal.buffer.clearScrollback();

      expect(terminal.buffer.height, 3);
      expect(terminal.buffer.lines[0].getText(), 'a');
    });
  });

  group('Buffer.clear()', () {
    test('drops scrollback and fills the viewport with empty lines', () {
      final terminal = createTerminal(width: 10, height: 3);
      terminal.write('l0\r\nl1\r\nl2\r\nl3\r\nl4');

      terminal.buffer.clear();

      expect(terminal.buffer.height, 3);
      for (var i = 0; i < 3; i++) {
        expect(terminal.buffer.lines[i].getText(), '');
      }
    });
  });

  group('Buffer.resize()', () {
    test('growing the height pulls lines back from the scrollback', () {
      final terminal = createTerminal(width: 10, height: 3);
      terminal.write('l0\r\nl1\r\nl2\r\nl3\r\nl4');
      expect(terminal.buffer.scrollBack, 2);

      terminal.resize(10, 5);

      expect(terminal.buffer.height, 5);
      expect(terminal.buffer.scrollBack, 0);
      expect(terminal.buffer.cursorY, 4);
      expect(terminal.buffer.lines[0].getText(), 'l0');
      expect(terminal.buffer.lines[4].getText(), 'l4');
    });

    test('growing the height without scrollback appends empty lines', () {
      final terminal = createTerminal(width: 10, height: 3);
      terminal.write('a');

      terminal.resize(10, 5);

      expect(terminal.buffer.height, 5);
      expect(terminal.buffer.cursorY, 0);
      expect(terminal.buffer.lines[0].getText(), 'a');
      expect(terminal.buffer.lines[4].getText(), '');
    });

    test('shrinking the height moves the cursor up when it is below', () {
      final terminal = createTerminal(width: 10, height: 5);
      terminal.write('a\r\nb\r\nc\r\nd\r\ne');

      terminal.resize(10, 3);

      // The cursor was on the last line; the excess lines become scrollback.
      expect(terminal.buffer.cursorY, 2);
      expect(terminal.buffer.height, 5);
      expect(terminal.buffer.scrollBack, 2);
    });

    test('shrinking the height pops lines when the cursor is above', () {
      final terminal = createTerminal(width: 10, height: 5);
      terminal.write('a\r\nb');
      terminal.setCursor(0, 0);

      terminal.resize(10, 3);

      expect(terminal.buffer.height, 3);
      expect(terminal.buffer.cursorY, 0);
      expect(terminal.buffer.lines[0].getText(), 'a');
    });

    test('clamps the cursor into the new viewport', () {
      final terminal = createTerminal(width: 10, height: 10);
      terminal.setCursor(9, 9);

      terminal.resize(5, 5);

      expect(terminal.buffer.cursorX, 4);
      expect(terminal.buffer.cursorY, 4);
    });

    test('width change reflows wrapped lines when reflow is enabled', () {
      final terminal = createTerminal(width: 10, height: 24);
      const text = 'ABCDEFGHIJKLMNOPQRSTUVWXY'; // 25 chars -> 10+10+5
      terminal.write(text);
      expect(terminal.buffer.lines[1].isWrapped, isTrue);
      expect(terminal.buffer.lines[2].isWrapped, isTrue);

      terminal.resize(20, 24);

      expect(terminal.buffer.lines[0].getTrimmedLength(), 20);
      expect(terminal.buffer.lines[0].isWrapped, isFalse);
      expect(terminal.buffer.lines[1].getTrimmedLength(), 5);
      expect(terminal.buffer.lines[1].isWrapped, isTrue);
      expect(terminal.buffer.getText(), startsWith(text));
    });

    test('width change truncates lines when reflow is disabled', () {
      final terminal = createTerminal(width: 10, height: 24, reflowEnabled: false);
      terminal.write('ABCDEFGHIJKLMNOPQRSTUVWXY'); // 25 chars -> 10+10+5

      terminal.resize(20, 24);

      // Lines are resized in place; wrapped structure is preserved.
      expect(terminal.buffer.lines[0].length, 20);
      expect(terminal.buffer.lines[0].getTrimmedLength(), 10);
      expect(terminal.buffer.lines[1].getTrimmedLength(), 10);
      expect(terminal.buffer.lines[2].getTrimmedLength(), 5);
    });

    test('width change never reflows the alt buffer', () {
      final terminal = createTerminal(width: 10, height: 24);
      terminal.useAltBuffer();
      terminal.write('ABCDEFGHIJKLMNO'); // 15 chars -> 10+5

      terminal.resize(20, 24);

      expect(terminal.altBuffer.lines[0].length, 20);
      expect(terminal.altBuffer.lines[0].getTrimmedLength(), 10);
      expect(terminal.altBuffer.lines[1].getTrimmedLength(), 5);
    });
  });

  group('Buffer anchors', () {
    test('createAnchor creates an anchor at the given position', () {
      final terminal = createTerminal();

      final anchor = terminal.buffer.createAnchor(2, 1);

      expect(anchor.offset, CellOffset(2, 1));
      expect(anchor.attached, isTrue);
    });

    test('createAnchorFromOffset creates an anchor at the given offset', () {
      final terminal = createTerminal();

      final anchor = terminal.buffer.createAnchorFromOffset(CellOffset(3, 2));

      expect(anchor.offset, CellOffset(3, 2));
      expect(anchor.attached, isTrue);
    });

    test('createAnchorFromCursor tracks the absolute cursor position', () {
      final terminal = createTerminal(width: 10, height: 3);
      terminal.write('l0\r\nl1\r\nl2\r\nl3\r\nl4');
      terminal.buffer.setCursorX(4);

      final anchor = terminal.buffer.createAnchorFromCursor();

      expect(anchor.offset, CellOffset(4, 4));
      expect(anchor.offset.y, terminal.buffer.absoluteCursorY);
    });
  });

  group('Buffer.getWordBoundary()', () {
    test('returns null when the position is below the buffer', () {
      final terminal = createTerminal(height: 5);

      expect(
        terminal.buffer.getWordBoundary(CellOffset(0, 100)),
        isNull,
      );
    });

    test('returns null for an empty line', () {
      final terminal = createTerminal();

      expect(terminal.buffer.getWordBoundary(CellOffset(0, 3)), isNull);
    });

    test('finds a word with the default separators', () {
      final terminal = createTerminal();
      terminal.buffer.write('foo bar');

      expect(
        terminal.buffer.getWordBoundary(CellOffset(1, 0)),
        BufferRangeLine(CellOffset(0, 0), CellOffset(3, 0)),
      );

      expect(
        terminal.buffer.getWordBoundary(CellOffset(5, 0)),
        BufferRangeLine(CellOffset(4, 0), CellOffset(7, 0)),
      );
    });

    test('a position on a separator resolves to the word on its left', () {
      final terminal = createTerminal();
      terminal.buffer.write('foo bar');

      expect(
        terminal.buffer.getWordBoundary(CellOffset(3, 0)),
        BufferRangeLine(CellOffset(0, 0), CellOffset(3, 0)),
      );
    });

    test('finds a single character word between separators', () {
      final terminal = createTerminal();
      terminal.buffer.write('a b');

      expect(
        terminal.buffer.getWordBoundary(CellOffset(2, 0)),
        BufferRangeLine(CellOffset(2, 0), CellOffset(3, 0)),
      );
    });
  });

  group('Buffer.getText()', () {
    test('joins unwrapped lines with newlines', () {
      final terminal = createTerminal();

      terminal.write('ab\r\ncd');

      expect(terminal.buffer.getText(), startsWith('ab\ncd'));
    });

    test('joins wrapped lines without a newline', () {
      final terminal = createTerminal(width: 4);

      terminal.write('abcdXY');

      expect(terminal.buffer.getText(), startsWith('abcdXY'));
    });

    test('supports an explicit line range', () {
      final terminal = createTerminal();
      terminal.write('ab\r\ncd\r\nef');

      expect(
        terminal.buffer.getText(
          BufferRangeLine(CellOffset(0, 1), CellOffset(10, 1)),
        ),
        'cd',
      );
    });
  });

  group('Buffer.toString()', () {
    test('renders numbered lines with their content', () {
      final terminal = createTerminal(width: 10, height: 3);
      terminal.write('ab');

      final text = terminal.buffer.toString();

      expect(text, contains('0: |ab|'));
      expect(text, contains('1: ||'));
    });
  });
}
