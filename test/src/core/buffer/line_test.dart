import 'package:test/test.dart';
import 'package:yoxterm/xterm.dart';

/// Writes [text] (ASCII only) into [line] starting at cell 0.
void writeAscii(BufferLine line, String text) {
  for (var i = 0; i < text.length; i++) {
    line.setCodePoint(i, text.codeUnitAt(i));
  }
}

void main() {
  group('BufferLine.getText()', () {
    test('should return the text', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(), 'Hello World');
    });

    test('getText() should support wide characters', () {
      final text = '😀😁😂🤣😃';
      final terminal = Terminal();
      terminal.write(text);
      expect(terminal.buffer.lines[0].getText(), equals(text));
    });

    test('can specify a range', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(0, 5), 'Hello');
    });

    test('can handle invalid ranges', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(0, 100), 'Hello World');
    });

    test('can handle negative ranges', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(-100, 100), 'Hello World');
    });

    test('can handle reversed ranges', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(5, 0), '');
    });
  });

  group('BufferLine.getTrimmedLength()', () {
    test('can get trimmed length', () {
      final line = BufferLine(10);

      final text = 'ABCDEF';

      for (var i = 0; i < text.length; i++) {
        line.setCodePoint(i, text.codeUnitAt(i));
      }

      expect(line.getTrimmedLength(), equals(text.length));
    });

    test('can get trimmed length with wide characters', () {
      final terminal = Terminal();
      final text = '😀😁😂🤣😃';

      terminal.write(text);

      expect(terminal.buffer.lines[0].getTrimmedLength(), equals(text.length));
    });

    test('can handle length larger than the line', () {
      final line = BufferLine(10);

      final text = 'ABCDEF';

      for (var i = 0; i < text.length; i++) {
        line.setCodePoint(i, text.codeUnitAt(i));
      }

      expect(line.getTrimmedLength(1000), equals(text.length));
    });

    test('can handle negative start', () {
      final line = BufferLine(10);

      final text = 'ABCDEF';

      for (var i = 0; i < text.length; i++) {
        line.setCodePoint(i, text.codeUnitAt(i));
      }

      expect(line.getTrimmedLength(-1000), equals(0));
    });
  });

  group('BufferLine.resize', () {
    test('can resize', () {
      final line = BufferLine(10);

      final text = 'ABCDEF';

      for (var i = 0; i < text.length; i++) {
        line.setCodePoint(i, text.codeUnitAt(i));
      }

      line.resize(20);

      expect(line.length, equals(20));
    });

    test('growth reallocates the backing store', () {
      final line = BufferLine(80);
      final initialCapacity = line.data.length;

      line.resize(300);

      expect(line.data.length, greaterThan(initialCapacity));
      expect(line.length, 300);
    });

    test('shrink releases the high-water allocation when it greatly exceeds the new requirement', () {
      // _calcCapacity(1000) == 1024 cells.
      final line = BufferLine(1000);
      writeAscii(line, 'ABCDEF');
      final highWaterCapacity = line.data.length;

      // _calcCapacity(80) == 128 cells; 1024 > 2 * 128, so the store shrinks.
      line.resize(80);

      expect(line.length, 80);
      expect(line.data.length, lessThan(highWaterCapacity));
      // Content survives the reallocation.
      expect(line.getText(), 'ABCDEF');
    });

    test('shrink keeps the allocation within the hysteresis band', () {
      // _calcCapacity(300) == 320 cells.
      final line = BufferLine(300);
      writeAscii(line, 'ABCDEF');
      final capacity = line.data.length;

      // _calcCapacity(280) == 320 cells; capacity does not exceed 2x the new
      // requirement, so no reallocation happens (avoids churn during
      // interactive resizes).
      line.resize(280);

      expect(line.length, 280);
      expect(line.data.length, capacity);
      expect(line.getText(), 'ABCDEF');
    });
  });

  group('Buffer.createAnchor', () {
    test('works', () {
      final terminal = Terminal();
      final line = terminal.buffer.lines[3];
      final anchor = line.createAnchor(5);

      terminal.insertLines(5);
      expect(anchor.x, 5);
      expect(anchor.y, 8);

      terminal.buffer.clear();
      expect(line.attached, false);
      expect(anchor.attached, false);
    });
  });
}
