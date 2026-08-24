import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yoxterm/core.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// Feeds [data] to [terminal] in two chunks split at [split].
void writeBytesSplit(Terminal terminal, Uint8List data, int split) {
  terminal.writeBytes(Uint8List.sublistView(data, 0, split));
  terminal.writeBytes(Uint8List.sublistView(data, split));
}

void main() {
  group('Terminal.writeBytes', () {
    test('writes plain ASCII bytes to the buffer', () {
      final terminal = Terminal();
      terminal.writeBytes(bytes('Hello World'));

      expect(terminal.buffer.lines[0].toString(), 'Hello World');
      expect(terminal.buffer.cursorX, 11);
      expect(terminal.buffer.cursorY, 0);
    });

    test('matches the String path for mixed plain text', () {
      final chunks = [
        'plain ascii text',
        'unicode: héllo wörld',
        'wide chars: 你好世界',
        'emoji: 😀🎉',
        'mixed é中😀 end',
      ];

      final fromBytes = Terminal();
      final reference = Terminal();
      for (final chunk in chunks) {
        fromBytes.writeBytes(bytes(chunk));
        reference.write(chunk);
      }

      expect(fromBytes.buffer.getText(), reference.buffer.getText());
      expect(fromBytes.buffer.cursorX, reference.buffer.cursorX);
      expect(fromBytes.buffer.cursorY, reference.buffer.cursorY);
    });

    group('multibyte UTF-8 split across chunks', () {
      final cases = {
        'é (2-byte)': 'é',
        '中 (3-byte)': '中',
        '😀 (4-byte)': '😀',
      };

      cases.forEach((label, char) {
        final encoded = bytes('a${char}b');
        // Split at every boundary that lands inside the multibyte sequence.
        for (var split = 2; split < 1 + utf8.encode(char).length; split++) {
          test('$label split after byte $split', () {
            final terminal = Terminal();
            writeBytesSplit(terminal, encoded, split);
            expect(terminal.buffer.lines[0].toString(), 'a${char}b');
          });
        }
      });

      test('a CJK flood split byte-by-byte matches the String path', () {
        const text = '你好世界，这是一个测试。';
        final encoded = bytes(text);

        final fromBytes = Terminal();
        for (var i = 0; i < encoded.length; i++) {
          fromBytes.writeBytes(Uint8List.sublistView(encoded, i, i + 1));
        }

        final reference = Terminal()..write(text);
        expect(fromBytes.buffer.getText(), reference.buffer.getText());
      });
    });

    group('malformed bytes', () {
      test('decode to U+FFFD like utf8.decode(allowMalformed: true)', () {
        final terminal = Terminal();
        terminal.writeBytes(Uint8List.fromList([0x61, 0xC3, 0x28, 0x62]));
        expect(terminal.buffer.lines[0].toString(), 'a\uFFFD(b');
      });

      test('surrogate-encoding bytes are replaced per byte', () {
        final terminal = Terminal();
        terminal.writeBytes(Uint8List.fromList([0xED, 0xA0, 0x80]));
        expect(
          terminal.buffer.lines[0].toString(),
          '\uFFFD\uFFFD\uFFFD',
        );
      });

      test('a pending prefix interrupted by plain text yields one U+FFFD', () {
        final terminal = Terminal();
        terminal.writeBytes(Uint8List.fromList([0xF0, 0x9F]));
        terminal.writeBytes(bytes('ab'));
        expect(terminal.buffer.lines[0].toString(), '\uFFFDab');
      });
    });

    group('escape sequences split across chunks', () {
      test('CSI split at every byte boundary', () {
        final encoded = bytes('\x1b[31;1mRED\x1b[0m');
        for (var split = 1; split < encoded.length; split++) {
          final fromBytes = Terminal();
          writeBytesSplit(fromBytes, encoded, split);

          final reference = Terminal()..write('\x1b[31;1mRED\x1b[0m');
          expect(
            fromBytes.buffer.lines[0].toString(),
            reference.buffer.lines[0].toString(),
            reason: 'split at $split',
          );
          expect(fromBytes.buffer.cursorX, reference.buffer.cursorX,
              reason: 'split at $split');
          expect(fromBytes.buffer.lines[0].toString(), 'RED',
              reason: 'split at $split');
        }
      });

      test('CSI params accumulated across three chunks parse once', () {
        final terminal = Terminal();
        terminal.writeBytes(bytes('\x1b['));
        terminal.writeBytes(bytes('3'));
        terminal.writeBytes(bytes(';4H'));
        expect(terminal.buffer.cursorX, 3);
        expect(terminal.buffer.cursorY, 2);
      });

      test('OSC split at every byte boundary sets the title', () {
        final encoded = bytes('\x1b]0;my title\x07');
        for (var split = 1; split < encoded.length; split++) {
          String? title;
          final terminal = Terminal(onTitleChange: (t) => title = t);
          writeBytesSplit(terminal, encoded, split);
          expect(title, 'my title', reason: 'split at $split');
        }
      });

      test('OSC with ST split between ESC and backslash', () {
        String? title;
        final terminal = Terminal(onTitleChange: (t) => title = t);
        terminal.writeBytes(bytes('\x1b]2;window\x1b'));
        expect(title, isNull);
        terminal.writeBytes(bytes('\\'));
        expect(title, 'window');
      });

      test('lone ESC is held back until the next chunk', () {
        final terminal = Terminal();
        terminal.writeBytes(bytes('\x1b'));
        expect(terminal.buffer.cursorX, 0);
        terminal.writeBytes(bytes('[5C'));
        expect(terminal.buffer.cursorX, 5);
      });

      test('charset designation split byte-by-byte', () {
        final terminal = Terminal();
        for (final chunk in ['\x1b', '(', '0', 'lqk']) {
          terminal.writeBytes(bytes(chunk));
        }
        expect(terminal.buffer.lines[0].toString(), '┌─┐');
      });

      test('a sequence split mid-way does not leak into the fast path', () {
        final terminal = Terminal();
        terminal.writeBytes(bytes('\x1b[31')); // incomplete CSI, held back
        terminal.writeBytes(bytes('mRED'));

        // If the second chunk had bypassed the parser, the buffer would
        // contain the literal text 'mRED'.
        expect(terminal.buffer.lines[0].toString(), 'RED');
      });
    });

    group('control characters', () {
      test('BEL, BS, TAB, LF, CR behave like the String path', () {
        var bells = 0;
        final fromBytes = Terminal(onBell: () => bells++);
        final reference = Terminal();
        const text = 'abcdef\x07\x08\x09xy\x0d\x0a';

        fromBytes.writeBytes(bytes(text));
        reference.write(text);

        expect(bells, 1);
        expect(fromBytes.buffer.getText(), reference.buffer.getText());
        expect(fromBytes.buffer.cursorX, reference.buffer.cursorX);
        expect(fromBytes.buffer.cursorY, reference.buffer.cursorY);
      });

      test('DEL is written as a regular character', () {
        final fromBytes = Terminal();
        fromBytes.writeBytes(Uint8List.fromList([0x61, 0x7F, 0x62]));

        final reference = Terminal()..write('a\x7Fb');
        expect(fromBytes.buffer.getText(), reference.buffer.getText());
      });
    });

    group('synchronized output (DEC mode 2026)', () {
      test('BSU/ESU gate notifications on the byte path', () {
        final terminal = Terminal();
        var notifications = 0;
        terminal.addListener(() => notifications++);

        terminal.writeBytes(bytes('\x1b[?2026h'));
        expect(terminal.syncOutputMode, isTrue);
        expect(notifications, 0);

        terminal.writeBytes(bytes('frame'));
        expect(notifications, 0);
        expect(terminal.buffer.lines[0].toString(), 'frame');

        terminal.writeBytes(bytes('\x1b[?2026l'));
        expect(terminal.syncOutputMode, isFalse);
        expect(notifications, 1);
      });

      test('a split ESU still flushes the frame once', () {
        final terminal = Terminal();
        var notifications = 0;
        terminal.addListener(() => notifications++);

        terminal.writeBytes(bytes('\x1b[?2026h'));
        terminal.writeBytes(bytes('frame'));
        terminal.writeBytes(bytes('\x1b[?202'));
        terminal.writeBytes(bytes('6l'));
        expect(terminal.syncOutputMode, isFalse);
        expect(notifications, 1);
      });
    });

    group('interaction with the buffer hot paths', () {
      test('REP repeats the last character after a fast-path byte write', () {
        final terminal = Terminal();
        terminal.writeBytes(bytes('ab'));
        terminal.writeBytes(bytes('\x1b[3b'));
        expect(terminal.buffer.lines[0].toString(), 'abbbb');
      });

      test('REP repeats an emoji written via the byte fast path', () {
        final terminal = Terminal();
        terminal.writeBytes(bytes('x😀'));
        terminal.writeBytes(bytes('\x1b[2b'));
        expect(terminal.buffer.lines[0].toString(), 'x😀😀😀');
      });

      test('empty chunk is a no-op', () {
        final terminal = Terminal();
        terminal.writeBytes(Uint8List(0));
        expect(terminal.buffer.lines[0].toString(), '');
        expect(terminal.buffer.cursorX, 0);
      });
    });

    group('interleaving with write(String)', () {
      test('a String write flushes a pending byte sequence as U+FFFD', () {
        final terminal = Terminal();
        terminal.writeBytes(Uint8List.fromList([0xF0, 0x9F]));
        terminal.write('ab');
        expect(terminal.buffer.lines[0].toString(), '\uFFFDab');
      });
    });
  });
}
