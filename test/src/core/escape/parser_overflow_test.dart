import 'package:test/test.dart';
import 'package:yoxterm/xterm.dart';

import 'recording_escape_handler.dart';

void main() {
  late RecordingEscapeHandler handler;
  late EscapeParser parser;

  setUp(() {
    handler = RecordingEscapeHandler();
    parser = EscapeParser(handler);
  });

  group('CSI length limit', () {
    test('well-formed CSI under the limit is dispatched unchanged', () {
      parser.write('\x1b[5A');
      parser.write('\x1b[?25h');
      expect(handler.calls, ['moveCursorY(-5)', 'setCursorVisibleMode(true)']);
    });

    test('CSI split across chunks under the limit is dispatched unchanged',
        () {
      parser.write('\x1b[5');
      expect(handler.calls, isEmpty);
      parser.write('A');
      expect(handler.calls, ['moveCursorY(-5)']);
    });

    test('CSI with exactly maxCsiLength bytes is still dispatched', () {
      // 512 repetitions of "1;" is exactly 1024 accumulated bytes.
      final body = '1;' * (EscapeParser.maxCsiLength ~/ 2);
      parser.write('\x1b[$body' 'A');
      expect(handler.calls, ['moveCursorY(-1)']);
    });

    test('unterminated CSI beyond the limit is discarded silently', () {
      parser.write('\x1b[${'9' * (EscapeParser.maxCsiLength + 100)}');
      expect(handler.calls, isEmpty);
      // Still no payload when the final byte eventually arrives.
      parser.write('A');
      expect(handler.calls, isEmpty);
    });

    test('overflowing CSI payload is never emitted as printable text', () {
      parser.write('\x1b[${'9' * (EscapeParser.maxCsiLength + 100)}m');
      parser.write('ok');
      expect(handler.calls, ['writeChar(111)', 'writeChar(107)']);
    });

    test('overflow is detected across chunk boundaries', () {
      parser.write('\x1b[${'9' * (EscapeParser.maxCsiLength - 10)}');
      expect(handler.calls, isEmpty);
      parser.write('${'9' * 100}m');
      parser.write('ok');
      expect(handler.calls, ['writeChar(111)', 'writeChar(107)']);
    });

    test('parser recovers: well-formed CSI parses after an overflow', () {
      parser.write('\x1b[${'9' * (EscapeParser.maxCsiLength + 100)}A');
      expect(handler.calls, isEmpty);
      parser.write('\x1b[5A');
      expect(handler.calls, ['moveCursorY(-5)']);
    });

    test('unterminated prefix-only CSI beyond the limit is discarded', () {
      // The prefix byte counts towards the budget as well.
      parser.write('\x1b[?${'9' * EscapeParser.maxCsiLength}A');
      expect(handler.calls, isEmpty);
    });
  });

  group('OSC length limit', () {
    test('well-formed OSC under the limit is dispatched unchanged', () {
      parser.write('\x1b]2;title\x07');
      expect(handler.calls, ['setTitle(title)']);

      handler.calls.clear();
      parser.write('\x1b]2;title\x1b\\');
      expect(handler.calls, ['setTitle(title)']);
    });

    test('OSC split across chunks under the limit is dispatched unchanged',
        () {
      parser.write('\x1b]2;ti');
      expect(handler.calls, isEmpty);
      parser.write('tle\x07');
      expect(handler.calls, ['setTitle(title)']);
    });

    test('OSC with exactly maxOscLength bytes is still dispatched', () {
      // '2' + ';' + title must total exactly maxOscLength accumulated bytes.
      final title = 'a' * (EscapeParser.maxOscLength - 2);
      parser.write('\x1b]2;$title\x07');
      expect(handler.calls, ['setTitle($title)']);
    });

    test('unterminated OSC beyond the limit is discarded silently', () {
      parser.write('\x1b]2;${'a' * (EscapeParser.maxOscLength + 100)}');
      expect(handler.calls, isEmpty);
      // BEL still ends the (discarded) sequence without dispatching it.
      parser.write('\x07');
      expect(handler.calls, isEmpty);
    });

    test('overflowing OSC payload is never emitted as printable text', () {
      parser.write('\x1b]2;${'a' * (EscapeParser.maxOscLength + 100)}\x07');
      parser.write('ok');
      expect(handler.calls, ['writeChar(111)', 'writeChar(107)']);
    });

    test('overflowing OSC is discarded when terminated by ST', () {
      parser.write('\x1b]2;${'a' * (EscapeParser.maxOscLength + 100)}\x1b\\');
      parser.write('ok');
      expect(handler.calls, ['writeChar(111)', 'writeChar(107)']);
    });

    test('overflow is detected across chunk boundaries', () {
      parser.write('\x1b]2;${'a' * (EscapeParser.maxOscLength - 10)}');
      expect(handler.calls, isEmpty);
      parser.write('${'a' * 100}\x07');
      parser.write('ok');
      expect(handler.calls, ['writeChar(111)', 'writeChar(107)']);
    });

    test('parser recovers: well-formed OSC parses after an overflow', () {
      parser.write('\x1b]2;${'a' * (EscapeParser.maxOscLength + 100)}\x07');
      parser.write('\x1b]2;ok\x07');
      expect(handler.calls, ['setTitle(ok)']);
    });

    test('unterminated OSC of only separators beyond the limit is discarded',
        () {
      // A stream of separators would grow the parameter list, not the
      // param buffer; the byte budget covers it too.
      parser.write('\x1b]${';' * (EscapeParser.maxOscLength + 100)}\x07');
      expect(handler.calls, isEmpty);
    });
  });
}
