import 'package:test/test.dart';
import 'package:yoxterm/src/utils/debugger.dart';

/// Renders a sequence in a form suitable for test names.
String visualize(String sequence) {
  return sequence
      .replaceAll('\x1b', 'ESC')
      .replaceAll('\x07', 'BEL')
      .replaceAll('\x0e', 'SO')
      .replaceAll('\x0f', 'SI')
      .replaceAll('\x0b', 'VT')
      .replaceAll('\x0c', 'FF');
}

void main() {
  group('TerminalDebugger', () {
    test('records every written character', () {
      final debugger = TerminalDebugger()..write('abc');

      expect(debugger.recorded, 'abc'.codeUnits);
    });

    test('plain text produces one writeChar command per character', () {
      final debugger = TerminalDebugger()..write('ab');

      expect(debugger.commands, hasLength(2));
      expect(debugger.commands[0].chars, 'a');
      expect(debugger.commands[0].explanation, ['writeChar(a)']);
      expect(debugger.commands[0].error, isFalse);
      expect(debugger.commands[0].start, 0);
      expect(debugger.commands[0].end, 1);
      expect(debugger.commands[1].explanation, ['writeChar(b)']);
    });

    test('control characters produce their named commands', () {
      final debugger = TerminalDebugger()..write('\x07\x08\x09\x0a\x0d');

      expect(
        debugger.commands.map((c) => c.explanation.single),
        ['bell', 'backspaceReturn', 'tab', 'lineFeed', 'carriageReturn'],
      );
    });

    test('escape sequences become a single command', () {
      final debugger = TerminalDebugger()..write('\x1b[2;3H');

      expect(debugger.commands, hasLength(1));
      final command = debugger.commands.single;
      expect(command.chars, '\x1b[2;3H');
      expect(command.escapedChars, 'ESC[2;3H');
      expect(command.explanation, ['setCursor(2, 1)']);
      expect(command.start, 0);
      expect(command.end, 6);
    });

    test('multi-parameter sequences merge explanations into one command', () {
      final debugger = TerminalDebugger()..write('\x1b[1;31m');

      expect(debugger.commands, hasLength(1));
      final command = debugger.commands.single;
      expect(command.explanation, [
        'setCursorBold',
        'setForegroundColor16(1)',
      ]);
    });

    test('text around a sequence keeps correct offsets', () {
      final debugger = TerminalDebugger()..write('a\x1b[2Jb');

      expect(debugger.commands, hasLength(3));
      expect(debugger.commands[0].chars, 'a');
      expect(debugger.commands[1].chars, '\x1b[2J');
      expect(debugger.commands[1].start, 1);
      expect(debugger.commands[1].end, 5);
      expect(debugger.commands[1].explanation, ['eraseDisplay']);
      expect(debugger.commands[2].chars, 'b');
    });

    test('OSC sequences are recorded', () {
      final debugger = TerminalDebugger()..write('\x1b]0;window title\x07');

      expect(debugger.commands, hasLength(1));
      // OSC 0 sets both the title and the icon name.
      expect(debugger.commands.single.explanation,
          ['setTitle(window title)', 'setIconName(window title)']);
    });

    test('unknown escape sequences are flagged as errors', () {
      final debugger = TerminalDebugger()..write('\x1b#');

      expect(debugger.commands, hasLength(1));
      final command = debugger.commands.single;
      expect(command.error, isTrue);
      expect(command.explanation.single, 'unkownEscape(#)');
    });

    test('unknown control characters are flagged as errors', () {
      final debugger = TerminalDebugger()..write('\x01');

      final command = debugger.commands.single;
      expect(command.error, isTrue);
      expect(command.explanation.single, startsWith('unkownEscape('));
    });

    test('unsupported SGR styles are flagged as errors', () {
      final debugger = TerminalDebugger()..write('\x1b[999m');

      final command = debugger.commands.single;
      expect(command.error, isTrue);
      expect(command.explanation.single, 'unsupportedStyle(999)');
    });

    test('an incomplete escape sequence produces no command', () {
      final debugger = TerminalDebugger()..write('\x1b[');
      expect(debugger.commands, isEmpty);

      // The sequence is completed by a later write.
      debugger.write('2J');
      expect(debugger.commands.single.explanation, ['eraseDisplay']);
    });
  });

  group('TerminalDebugger protocol coverage', () {
    // Every supported escape sequence is translated into a human-readable
    // explanation. Multi-callback sequences merge into one command, so the
    // value is the full explanation list of the single recorded command.
    final cases = <String, List<String>>{
      // Single byte controls
      '\x0b': ['lineFeed'],
      '\x0c': ['lineFeed'],
      '\x0e': ['shiftOut'],
      '\x0f': ['shiftIn'],

      // ESC sequences
      '\x1b7': ['saveCursor'],
      '\x1b8': ['restoreCursor'],
      '\x1bD': ['index'],
      '\x1bE': ['nextLine'],
      '\x1bH': ['setTapStop'],
      '\x1bM': ['reverseIndex'],
      '\x1b(0': ['designateCharset(0, 48)'],
      '\x1b)B': ['designateCharset(1, 66)'],
      '\x1b=': ['setAppKeypadMode(true)'],
      '\x1b>': ['setAppKeypadMode(false)'],

      // CSI: cursor movement and editing
      '\x1b[3b': ['repeatPreviousCharacter(3)'],
      '\x1b[2A': ['moveCursorY(-2)'],
      '\x1b[2B': ['moveCursorY(2)'],
      '\x1b[5C': ['moveCursorX(5)'],
      '\x1b[5D': ['moveCursorX(-5)'],
      '\x1b[2E': ['cursorNextLine(2)'],
      '\x1b[2F': ['cursorPrecedingLine(2)'],
      '\x1b[5G': ['setCursorX(4)'],
      '\x1b[5d': ['setCursorY(4)'],
      '\x1b[3;4f': ['setCursor(3, 2)'],
      '\x1b[3L': ['insertLines(3)'],
      '\x1b[3M': ['deleteLines(3)'],
      '\x1b[4P': ['deleteChars(4)'],
      '\x1b[2S': ['scrollUp(2)'],
      '\x1b[2T': ['scrollDown(2)'],
      '\x1b[2X': ['eraseChars(2)'],
      '\x1b[2@': ['insertBlankChars(2)'],

      // CSI: erasing
      '\x1b[0J': ['eraseDisplayBelow'],
      '\x1b[1J': ['eraseDisplayAbove'],
      '\x1b[3J': ['eraseScrollbackOnly'],
      '\x1b[0K': ['eraseLineRight'],
      '\x1b[1K': ['eraseLineLeft'],
      '\x1b[2K': ['eraseLine'],

      // CSI: device attributes and status
      '\x1b[c': ['sendPrimaryDeviceAttributes'],
      '\x1b[>c': ['sendSecondaryDeviceAttributes'],
      '\x1b[=c': ['sendTertiaryDeviceAttributes'],
      '\x1b[5n': ['sendOperatingStatus'],
      '\x1b[6n': ['sendCursorPosition'],

      // CSI: tabs, margins and window manipulation
      '\x1b[0g': ['clearTabStopUnderCursor'],
      '\x1b[3g': ['clearAllTabStops'],
      '\x1b[2;5r': ['setMargins(1, 4)'],
      '\x1b[r': ['setMargins(0, null)'],
      '\x1b[8;24;80t': ['resize(80, 24)'],
      '\x1b[18t': ['sendSize'],

      // ANSI modes
      '\x1b[4h': ['setInsertMode(true)'],
      '\x1b[4l': ['setInsertMode(false)'],
      '\x1b[20h': ['setLineFeedMode(true)'],

      // DEC private modes
      '\x1b[?1h': ['setCursorKeysMode(true)'],
      '\x1b[?1l': ['setCursorKeysMode(false)'],
      '\x1b[?3h': ['setColumnMode(true)'],
      '\x1b[?5h': ['setReverseDisplayMode(true)'],
      '\x1b[?6h': ['setOriginMode(true)'],
      '\x1b[?7h': ['setAutoWrapMode(true)'],
      '\x1b[?9h': ['setMouseMode(MouseMode.clickOnly)'],
      '\x1b[?9l': ['setMouseMode(MouseMode.none)'],
      '\x1b[?12h': ['setCursorBlinkMode(true)'],
      '\x1b[?25l': ['setCursorVisibleMode(false)'],
      '\x1b[?47h': ['useAltBuffer'],
      '\x1b[?47l': ['useMainBuffer'],
      '\x1b[?66h': ['setAppKeypadMode(true)'],
      '\x1b[?1000h': ['setMouseMode(MouseMode.upDownScroll)'],
      '\x1b[?1001h': ['setMouseMode(MouseMode.upDownScroll)'],
      '\x1b[?1002h': ['setMouseMode(MouseMode.upDownScrollDrag)'],
      '\x1b[?1003h': ['setMouseMode(MouseMode.upDownScrollMove)'],
      '\x1b[?1000l': ['setMouseMode(MouseMode.none)'],
      '\x1b[?1004h': ['setReportFocusMode(true)'],
      '\x1b[?1005h': ['setMouseReportMode(MouseReportMode.utf)'],
      '\x1b[?1006h': ['setMouseReportMode(MouseReportMode.sgr)'],
      '\x1b[?1006l': ['setMouseReportMode(MouseReportMode.normal)'],
      '\x1b[?1007h': ['setAltBufferMouseScrollMode(true)'],
      '\x1b[?1015h': ['setMouseReportMode(MouseReportMode.urxvt)'],
      '\x1b[?1047l': ['clearAltBuffer', 'useMainBuffer'],
      '\x1b[?1048h': ['saveCursor'],
      '\x1b[?1048l': ['restoreCursor'],
      '\x1b[?1049h': ['saveCursor', 'clearAltBuffer', 'useAltBuffer'],
      '\x1b[?1049l': ['useMainBuffer'],
      '\x1b[?2004h': ['setBracketedPasteMode(true)'],
      '\x1b[?2004l': ['setBracketedPasteMode(false)'],

      // SGR styles
      '\x1b[m': ['resetCursorStyle'],
      '\x1b[0m': ['resetCursorStyle'],
      '\x1b[2m': ['setCursorFaint'],
      '\x1b[3m': ['setCursorItalic'],
      '\x1b[4m': ['setCursorUnderline'],
      '\x1b[5m': ['setCursorBlink'],
      '\x1b[7m': ['setCursorInverse'],
      '\x1b[8m': ['setCursorInvisible'],
      '\x1b[9m': ['setCursorStrikethrough'],
      '\x1b[21m': ['unsetCursorBold'],
      '\x1b[22m': ['unsetCursorFaint'],
      '\x1b[23m': ['unsetCursorItalic'],
      '\x1b[24m': ['unsetCursorUnderline'],
      '\x1b[25m': ['unsetCursorBlink'],
      '\x1b[27m': ['unsetCursorInverse'],
      '\x1b[28m': ['unsetCursorInvisible'],
      '\x1b[29m': ['unsetCursorStrikethrough'],
      '\x1b[30m': ['setForegroundColor16(0)'],
      '\x1b[37m': ['setForegroundColor16(7)'],
      '\x1b[39m': ['resetForeground'],
      '\x1b[38;5;196m': ['setForegroundColor256(196)'],
      '\x1b[38;2;1;2;3m': ['setForegroundColorRgb(1, 2, 3)'],
      '\x1b[40m': ['setBackgroundColor16(0)'],
      '\x1b[47m': ['setBackgroundColor16(7)'],
      '\x1b[49m': ['resetBackground'],
      '\x1b[48;5;20m': ['setBackgroundColor256(20)'],
      '\x1b[48;2;4;5;6m': ['setBackgroundColorRgb(4, 5, 6)'],

      // OSC
      '\x1b]1;icon\x07': ['setIconName(icon)'],
      '\x1b]2;window title\x07': ['setTitle(window title)'],
    };

    cases.forEach((sequence, expected) {
      test('${visualize(sequence)} -> ${expected.join(' | ')}', () {
        final debugger = TerminalDebugger()..write(sequence);

        expect(debugger.commands, hasLength(1));
        expect(debugger.commands.single.explanation, expected);
        expect(debugger.commands.single.error, isFalse);
      });
    });

    final errorCases = <String, List<String>>{
      '\x1b[1z': ['unkownCSI(z)'],
      '\x1b[99h': ['setUnknownMode(99, true)'],
      '\x1b[?9999h': ['setUnknownDecMode(9999, true)'],
      '\x1b]99;x;y\x07': ['unknownOSC(99, [x, y])'],
    };

    errorCases.forEach((sequence, expected) {
      test('${visualize(sequence)} -> ${expected.join(' | ')} (error)', () {
        final debugger = TerminalDebugger()..write(sequence);

        expect(debugger.commands, hasLength(1));
        expect(debugger.commands.single.explanation, expected);
        expect(debugger.commands.single.error, isTrue);
      });
    });
  });

  group('TerminalDebugger escaping', () {
    String escape(String input) {
      final debugger = TerminalDebugger()..write(input);
      return debugger.commands.map((c) => c.escapedChars).join();
    }

    test('ESC is rendered as ESC', () {
      expect(escape('\x1b[2J'), 'ESC[2J');
    });

    test('control characters are rendered as hex codes', () {
      expect(escape('\x07'), '^0x7');
      expect(escape('\x01'), '^0x1');
    });

    test('DEL is rendered as ^?', () {
      expect(escape('\x7f'), '^?');
    });

    test('printable characters are kept as-is', () {
      expect(escape('hello'), 'hello');
    });
  });

  group('TerminalDebugger.getRecord()', () {
    test('returns the recorded input up to the end of the command', () {
      final debugger = TerminalDebugger()..write('ab\x1b[2Jcd');

      expect(debugger.getRecord(debugger.commands[0]), 'a');
      expect(debugger.getRecord(debugger.commands[2]), 'ab\x1b[2J');
      expect(debugger.getRecord(debugger.commands.last), 'ab\x1b[2Jcd');
    });
  });

  group('TerminalDebugger listeners', () {
    test('listeners are notified on write', () {
      final debugger = TerminalDebugger();
      var notified = 0;
      void listener() => notified++;

      debugger.addListener(listener);
      debugger.write('a');
      debugger.write('b');

      expect(notified, 2);

      debugger.removeListener(listener);
      debugger.write('c');
      expect(notified, 2);
    });
  });
}
