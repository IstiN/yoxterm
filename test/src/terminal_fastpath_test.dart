import 'package:test/test.dart';
import 'package:xterm/core.dart';

/// Tests for the parser-bypass fast path in [Terminal.write]: chunks without
/// ESC, C0 control characters or a dangling surrogate half are written to the
/// buffer directly. [writeViaParser] drives a terminal through the parser
/// unconditionally and serves as the reference implementation the fast path
/// must match exactly.
void main() {
  group('Terminal.write fast path', () {
    test('writes plain ASCII chunks to the buffer', () {
      final terminal = Terminal();
      terminal.write('Hello World');

      expect(terminal.buffer.lines[0].toString(), 'Hello World');
      expect(terminal.buffer.cursorX, 11);
      expect(terminal.buffer.cursorY, 0);
    });

    test('matches the parser path for plain text', () {
      final chunks = [
        'plain ascii text',
        'multiple writes ',
        'with unicode: héllo wörld',
        'wide chars: 你好世界',
        'emoji: 😀🎉',
        'combining: é',
      ];

      final fast = Terminal();
      final reference = Terminal();
      final referenceParser = EscapeParser(reference);

      for (final chunk in chunks) {
        fast.write(chunk);
        referenceParser.write(chunk);
      }

      expect(fast.buffer.getText(), reference.buffer.getText());
      expect(fast.buffer.cursorX, reference.buffer.cursorX);
      expect(fast.buffer.cursorY, reference.buffer.cursorY);
    });

    test('sends every C0 control character through the parser', () {
      for (var c = 0x00; c <= 0x1f; c++) {
        final chunk = 'ab${String.fromCharCode(c)}cd';

        final fast = Terminal();
        fast.write(chunk);

        final reference = Terminal();
        EscapeParser(reference).write(chunk);

        expect(
          fast.buffer.getText(),
          reference.buffer.getText(),
          reason: 'mismatch for control 0x${c.toRadixString(16)}',
        );
        expect(fast.buffer.cursorX, reference.buffer.cursorX);
        expect(fast.buffer.cursorY, reference.buffer.cursorY);
      }
    });

    test('sends DEL through the parser', () {
      final fast = Terminal();
      fast.write('ab\x7fcd');

      final reference = Terminal();
      EscapeParser(reference).write('ab\x7fcd');

      expect(fast.buffer.getText(), reference.buffer.getText());
      expect(fast.buffer.cursorX, reference.buffer.cursorX);
    });

    test('rings the bell for BEL', () {
      var bells = 0;
      final terminal = Terminal(onBell: () => bells++);
      terminal.write('a\x07b');

      expect(bells, 1);
      expect(terminal.buffer.lines[0].toString(), 'ab');
    });

    test('moves the cursor for BS, TAB, LF and CR', () {
      final terminal = Terminal();
      terminal.write('abcdef');
      terminal.write('\x08');
      expect(terminal.buffer.cursorX, 5);
      terminal.write('\x09');
      expect(terminal.buffer.cursorX, 8);
      terminal.write('xy');
      terminal.write('\x0d');
      expect(terminal.buffer.cursorX, 0);
      terminal.write('\x0a');
      expect(terminal.buffer.cursorY, 1);
    });

    test('honors SO/SI charset shifts', () {
      final terminal = Terminal();
      // Designate DEC special graphics into G1, then shift in and out.
      terminal.write('\x1b)0');
      terminal.write('\x0eq\x0fq');

      // 0x71 maps to U+2500 only while G1 is shifted in.
      expect(terminal.buffer.lines[0].toString(), '─q');
    });

    test('handles ESC in the middle of a chunk', () {
      final terminal = Terminal();
      terminal.write('ab\x1b[2Dcd');

      expect(terminal.buffer.lines[0].toString(), 'cd');
      expect(terminal.buffer.cursorX, 2);
    });

    test('stitches a surrogate pair split across chunk boundaries', () {
      final terminal = Terminal();
      // The trailing lone high surrogate must be held back and combined with
      // the low half from the next chunk instead of being written as-is.
      terminal.write('abc\uD83D');
      terminal.write('\uDE00def');

      expect(terminal.buffer.lines[0].toString(), 'abc😀def');
    });

    test('combines with a pending surrogate even when the next chunk is plain',
        () {
      final terminal = Terminal();
      terminal.write('\x1b[1m\uD83D'); // slow path leaves a pending surrogate
      terminal.write('\uDE00!');

      expect(terminal.buffer.lines[0].toString(), '😀!');
    });

    test('applies the designated charset on the fast path', () {
      final fast = Terminal();
      fast.write('\x1b(0'); // designate DEC special graphics into G0
      fast.write('lqk');

      final reference = Terminal();
      final referenceParser = EscapeParser(reference);
      referenceParser.write('\x1b(0');
      referenceParser.write('lqk');

      expect(fast.buffer.lines[0].toString(), '┌─┐');
      expect(fast.buffer.getText(), reference.buffer.getText());
    });

    test('repeats the last character after a fast-path write (REP)', () {
      final terminal = Terminal();
      terminal.write('ab');
      terminal.write('\x1b[3b');

      expect(terminal.buffer.lines[0].toString(), 'abbbb');
    });

    test('repeats an emoji written via the fast path (REP)', () {
      final terminal = Terminal();
      terminal.write('x😀');
      terminal.write('\x1b[2b');

      expect(terminal.buffer.lines[0].toString(), 'x😀😀😀');
    });

    test('does not bypass the parser while a sequence is incomplete', () {
      final terminal = Terminal();
      terminal.write('\x1b[31'); // incomplete CSI, held back by the parser
      terminal.write('mRED');

      // If the second chunk had bypassed the parser, the buffer would
      // contain the literal text 'mRED'.
      expect(terminal.buffer.lines[0].toString(), 'RED');
      expect(terminal.buffer.cursorX, 3);
    });
  });
}
