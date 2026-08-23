import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

import 'recording_escape_handler.dart';

void main() {
  late RecordingEscapeHandler handler;
  late EscapeParser parser;

  setUp(() {
    handler = RecordingEscapeHandler();
    parser = EscapeParser(handler);
  });

  group('single byte controls', () {
    test('BEL rings the bell', () {
      parser.write('\x07');
      expect(handler.calls, ['bell()']);
    });

    test('BS triggers backspaceReturn', () {
      parser.write('\x08');
      expect(handler.calls, ['backspaceReturn()']);
    });

    test('HT triggers tab', () {
      parser.write('\x09');
      expect(handler.calls, ['tab()']);
    });

    test('LF, VT and FF all trigger lineFeed', () {
      parser.write('\x0a\x0b\x0c');
      expect(handler.calls, ['lineFeed()', 'lineFeed()', 'lineFeed()']);
    });

    test('CR triggers carriageReturn', () {
      parser.write('\x0d');
      expect(handler.calls, ['carriageReturn()']);
    });

    test('SO and SI trigger shiftOut/shiftIn', () {
      parser.write('\x0e\x0f');
      expect(handler.calls, ['shiftOut()', 'shiftIn()']);
    });

    test('unmapped control character is reported via unkownEscape', () {
      parser.write('\x01');
      expect(handler.calls, ['unkownEscape(1)']);
    });

    test('NUL is reported via unkownEscape', () {
      parser.write('\x00');
      expect(handler.calls, ['unkownEscape(0)']);
    });
  });

  group('plain characters', () {
    test('printable ASCII is written char by char', () {
      parser.write('ab');
      expect(handler.calls, ['writeChar(97)', 'writeChar(98)']);
    });

    test('DEL (0x7f) is written as a regular char', () {
      parser.write('\x7f');
      expect(handler.calls, ['writeChar(127)']);
    });

    test('non-ASCII BMP char is written as a single char', () {
      parser.write('é');
      expect(handler.calls, ['writeChar(233)']);
    });

    test('surrogate pair in one chunk is combined into a single code point', () {
      parser.write('😀');
      expect(handler.calls, ['writeChar(128512)']);
    });

    test('surrogate pair split across chunks is NOT recombined', () {
      // ByteConsumer.add() processes each chunk independently, so a pair
      // split across two writes reaches the handler as two lone surrogates.
      parser.write('\ud83d');
      parser.write('\ude00');
      expect(handler.calls, ['writeChar(55357)', 'writeChar(56832)']);
    });
  });

  group('ESC sequences', () {
    test('ESC 7 saves cursor', () {
      parser.write('\x1b7');
      expect(handler.calls, ['saveCursor()']);
    });

    test('ESC 8 restores cursor', () {
      parser.write('\x1b8');
      expect(handler.calls, ['restoreCursor()']);
    });

    test('ESC D triggers index', () {
      parser.write('\x1bD');
      expect(handler.calls, ['index()']);
    });

    test('ESC E triggers nextLine', () {
      parser.write('\x1bE');
      expect(handler.calls, ['nextLine()']);
    });

    test('ESC H sets a tab stop', () {
      parser.write('\x1bH');
      expect(handler.calls, ['setTapStop()']);
    });

    test('ESC M triggers reverseIndex', () {
      parser.write('\x1bM');
      expect(handler.calls, ['reverseIndex()']);
    });

    test('ESC = enables application keypad mode', () {
      parser.write('\x1b=');
      expect(handler.calls, ['setAppKeypadMode(true)']);
    });

    test('ESC > disables application keypad mode', () {
      parser.write('\x1b>');
      expect(handler.calls, ['setAppKeypadMode(false)']);
    });

    test('unknown escape char is reported and swallowed', () {
      parser.write('\x1bz');
      expect(handler.calls, ['unkownEscape(122)']);
    });

    test('unknown escape char beyond the lookup table is reported', () {
      // 0x7e is above the highest registered escape handler index.
      parser.write('\x1b~');
      expect(handler.calls, ['unkownEscape(126)']);
    });
  });

  group('CSI cursor movement', () {
    test('CUU defaults to 1 and clamps 0 to 1', () {
      parser.write('\x1b[A');
      parser.write('\x1b[0A');
      parser.write('\x1b[5A');
      expect(handler.calls, [
        'moveCursorY(-1)',
        'moveCursorY(-1)',
        'moveCursorY(-5)',
      ]);
    });

    test('CUD moves cursor down', () {
      parser.write('\x1b[B');
      parser.write('\x1b[3B');
      expect(handler.calls, ['moveCursorY(1)', 'moveCursorY(3)']);
    });

    test('CUF moves cursor forward', () {
      parser.write('\x1b[C');
      parser.write('\x1b[7C');
      expect(handler.calls, ['moveCursorX(1)', 'moveCursorX(7)']);
    });

    test('CUB moves cursor backward', () {
      parser.write('\x1b[D');
      parser.write('\x1b[2D');
      expect(handler.calls, ['moveCursorX(-1)', 'moveCursorX(-2)']);
    });

    test('CNL moves cursor to next line', () {
      parser.write('\x1b[E');
      parser.write('\x1b[4E');
      expect(handler.calls, ['cursorNextLine(1)', 'cursorNextLine(4)']);
    });

    test('CPL moves cursor to preceding line', () {
      parser.write('\x1b[F');
      parser.write('\x1b[4F');
      expect(handler.calls, [
        'cursorPrecedingLine(1)',
        'cursorPrecedingLine(4)',
      ]);
    });

    test('CHA sets absolute column, clamping 0 to 1', () {
      parser.write('\x1b[G');
      parser.write('\x1b[0G');
      parser.write('\x1b[10G');
      expect(handler.calls, [
        'setCursorX(0)',
        'setCursorX(0)',
        'setCursorX(9)',
      ]);
    });

    test('VPA sets absolute row (1-based input)', () {
      parser.write('\x1b[d');
      parser.write('\x1b[5d');
      expect(handler.calls, ['setCursorY(0)', 'setCursorY(4)']);
    });

    test('VPA does NOT clamp 0 (inconsistent with CHA)', () {
      // Documents current behavior: CSI 0 d yields setCursorY(-1).
      parser.write('\x1b[0d');
      expect(handler.calls, ['setCursorY(-1)']);
    });

    test('CUP sets cursor position (1-based input)', () {
      parser.write('\x1b[5;10H');
      expect(handler.calls, ['setCursor(9, 4)']);
    });

    test('CUP without params moves to origin', () {
      parser.write('\x1b[H');
      expect(handler.calls, ['setCursor(0, 0)']);
    });

    test('HVP is an alias of CUP', () {
      parser.write('\x1b[2;3f');
      expect(handler.calls, ['setCursor(2, 1)']);
    });

    test('CUP with a single param ignores it and moves to origin', () {
      // Documents current behavior: params.length != 2 resets both to 1.
      parser.write('\x1b[5H');
      expect(handler.calls, ['setCursor(0, 0)']);
    });

    test('REP repeats the previous character, clamping 0 to 1', () {
      parser.write('\x1b[b');
      parser.write('\x1b[0b');
      parser.write('\x1b[3b');
      expect(handler.calls, [
        'repeatPreviousCharacter(1)',
        'repeatPreviousCharacter(1)',
        'repeatPreviousCharacter(3)',
      ]);
    });
  });

  group('CSI erase', () {
    test('ED dispatches on param 0-3', () {
      parser.write('\x1b[0J\x1b[1J\x1b[2J\x1b[3J');
      expect(handler.calls, [
        'eraseDisplayBelow()',
        'eraseDisplayAbove()',
        'eraseDisplay()',
        'eraseScrollbackOnly()',
      ]);
    });

    test('ED without param defaults to erase below', () {
      parser.write('\x1b[J');
      expect(handler.calls, ['eraseDisplayBelow()']);
    });

    test('ED with unknown param does nothing', () {
      parser.write('\x1b[4J');
      expect(handler.calls, isEmpty);
    });

    test('EL dispatches on param 0-2', () {
      parser.write('\x1b[0K\x1b[1K\x1b[2K');
      expect(handler.calls, [
        'eraseLineRight()',
        'eraseLineLeft()',
        'eraseLine()',
      ]);
    });

    test('EL without param defaults to erase right', () {
      parser.write('\x1b[K');
      expect(handler.calls, ['eraseLineRight()']);
    });

    test('EL with unknown param does nothing', () {
      parser.write('\x1b[3K');
      expect(handler.calls, isEmpty);
    });

    test('ECH erases characters, default 1', () {
      parser.write('\x1b[X');
      parser.write('\x1b[6X');
      expect(handler.calls, ['eraseChars(1)', 'eraseChars(6)']);
    });
  });

  group('CSI insert/delete/scroll', () {
    test('IL inserts lines, default 1', () {
      parser.write('\x1b[L');
      parser.write('\x1b[2L');
      expect(handler.calls, ['insertLines(1)', 'insertLines(2)']);
    });

    test('IL does NOT clamp 0 (inconsistent with cursor movement)', () {
      // Documents current behavior: CSI 0 L yields insertLines(0).
      parser.write('\x1b[0L');
      expect(handler.calls, ['insertLines(0)']);
    });

    test('DL deletes lines, default 1', () {
      parser.write('\x1b[M');
      parser.write('\x1b[2M');
      expect(handler.calls, ['deleteLines(1)', 'deleteLines(2)']);
    });

    test('DCH deletes characters, default 1', () {
      parser.write('\x1b[P');
      parser.write('\x1b[2P');
      expect(handler.calls, ['deleteChars(1)', 'deleteChars(2)']);
    });

    test('SU scrolls up, default 1', () {
      parser.write('\x1b[S');
      parser.write('\x1b[2S');
      expect(handler.calls, ['scrollUp(1)', 'scrollUp(2)']);
    });

    test('SD scrolls down, default 1', () {
      parser.write('\x1b[T');
      parser.write('\x1b[2T');
      expect(handler.calls, ['scrollDown(1)', 'scrollDown(2)']);
    });

    test('ICH inserts blank characters, default 1', () {
      parser.write('\x1b[@');
      parser.write('\x1b[2@');
      expect(handler.calls, ['insertBlankChars(1)', 'insertBlankChars(2)']);
    });
  });

  group('CSI set margins', () {
    test('no params resets top margin to 0 with open bottom', () {
      parser.write('\x1b[r');
      expect(handler.calls, ['setMargins(0, null)']);
    });

    test('single param sets top margin only', () {
      parser.write('\x1b[5r');
      expect(handler.calls, ['setMargins(4, null)']);
    });

    test('two params set top and bottom (1-based input)', () {
      parser.write('\x1b[2;8r');
      expect(handler.calls, ['setMargins(1, 7)']);
    });

    test('more than two params are ignored entirely', () {
      parser.write('\x1b[1;2;3r');
      expect(handler.calls, isEmpty);
    });
  });

  group('CSI tab stops', () {
    test('TBC param 0 clears the tab stop under the cursor', () {
      parser.write('\x1b[0g');
      expect(handler.calls, ['clearTabStopUnderCursor()']);
    });

    test('TBC without param defaults to clearing under the cursor', () {
      parser.write('\x1b[g');
      expect(handler.calls, ['clearTabStopUnderCursor()']);
    });

    test('TBC param 3 clears all tab stops', () {
      parser.write('\x1b[3g');
      expect(handler.calls, ['clearAllTabStops()']);
    });

    test('TBC with any other param clears all tab stops', () {
      parser.write('\x1b[5g');
      expect(handler.calls, ['clearAllTabStops()']);
    });
  });

  group('CSI device attributes', () {
    test('CSI c requests primary device attributes', () {
      parser.write('\x1b[c');
      expect(handler.calls, ['sendPrimaryDeviceAttributes()']);
    });

    test('CSI 0 c requests primary device attributes', () {
      parser.write('\x1b[0c');
      expect(handler.calls, ['sendPrimaryDeviceAttributes()']);
    });

    test('CSI > c requests secondary device attributes', () {
      parser.write('\x1b[>c');
      expect(handler.calls, ['sendSecondaryDeviceAttributes()']);
    });

    test('CSI > 0 c requests secondary device attributes', () {
      parser.write('\x1b[>0c');
      expect(handler.calls, ['sendSecondaryDeviceAttributes()']);
    });

    test('CSI = c requests tertiary device attributes', () {
      parser.write('\x1b[=c');
      expect(handler.calls, ['sendTertiaryDeviceAttributes()']);
    });
  });

  group('CSI device status report', () {
    test('DSR 5 sends operating status', () {
      parser.write('\x1b[5n');
      expect(handler.calls, ['sendOperatingStatus()']);
    });

    test('DSR 6 sends cursor position', () {
      parser.write('\x1b[6n');
      expect(handler.calls, ['sendCursorPosition()']);
    });

    test('DSR without params does nothing', () {
      parser.write('\x1b[n');
      expect(handler.calls, isEmpty);
    });

    test('DSR with unknown param does nothing', () {
      parser.write('\x1b[7n');
      expect(handler.calls, isEmpty);
    });
  });

  group('CSI window manipulation', () {
    test('resize requires exactly 3 params', () {
      parser.write('\x1b[8;24;80t');
      expect(handler.calls, ['resize(80, 24)']);
    });

    test('resize with wrong arity is ignored', () {
      parser.write('\x1b[8;24t');
      parser.write('\x1b[8;24;80;1t');
      expect(handler.calls, isEmpty);
    });

    test('report terminal size sends size', () {
      parser.write('\x1b[18t');
      expect(handler.calls, ['sendSize()']);
    });

    test('out-of-scope window operations are ignored', () {
      for (final op in [1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 13, 14, 15, 16, 19]) {
        parser.write('\x1b[${op}t');
      }
      expect(handler.calls, isEmpty);
    });

    test('title push/pop and title reporting are ignored', () {
      for (final op in [20, 21, 22, 23]) {
        parser.write('\x1b[${op}t');
      }
      expect(handler.calls, isEmpty);
    });

    test('window manipulation without params does nothing', () {
      parser.write('\x1b[t');
      expect(handler.calls, isEmpty);
    });

    test('unknown window operation does nothing', () {
      parser.write('\x1b[99t');
      expect(handler.calls, isEmpty);
    });
  });

  group('CSI modes (SM/RM)', () {
    test('CSI 4 h/l toggles insert mode', () {
      parser.write('\x1b[4h');
      parser.write('\x1b[4l');
      expect(handler.calls, ['setInsertMode(true)', 'setInsertMode(false)']);
    });

    test('CSI 20 h/l toggles line feed mode', () {
      parser.write('\x1b[20h');
      parser.write('\x1b[20l');
      expect(handler.calls, ['setLineFeedMode(true)', 'setLineFeedMode(false)']);
    });

    test('unknown ANSI mode is forwarded to setUnknownMode', () {
      parser.write('\x1b[2h');
      parser.write('\x1b[2l');
      expect(handler.calls, [
        'setUnknownMode(2, true)',
        'setUnknownMode(2, false)',
      ]);
    });

    test('multiple modes in one sequence are all applied', () {
      parser.write('\x1b[4;20h');
      expect(handler.calls, ['setInsertMode(true)', 'setLineFeedMode(true)']);
    });

    test('mode sequence without params does nothing', () {
      parser.write('\x1b[h');
      parser.write('\x1b[?h');
      expect(handler.calls, isEmpty);
    });
  });

  group('CSI DEC private modes', () {
    test('DECCKM cursor keys mode (1)', () {
      parser.write('\x1b[?1h\x1b[?1l');
      expect(handler.calls, [
        'setCursorKeysMode(true)',
        'setCursorKeysMode(false)',
      ]);
    });

    test('DECCOLM column mode (3)', () {
      parser.write('\x1b[?3h\x1b[?3l');
      expect(handler.calls, ['setColumnMode(true)', 'setColumnMode(false)']);
    });

    test('DECSCNM reverse display mode (5)', () {
      parser.write('\x1b[?5h\x1b[?5l');
      expect(handler.calls, [
        'setReverseDisplayMode(true)',
        'setReverseDisplayMode(false)',
      ]);
    });

    test('DECOM origin mode (6)', () {
      parser.write('\x1b[?6h\x1b[?6l');
      expect(handler.calls, ['setOriginMode(true)', 'setOriginMode(false)']);
    });

    test('DECAWM auto wrap mode (7)', () {
      parser.write('\x1b[?7h\x1b[?7l');
      expect(handler.calls, [
        'setAutoWrapMode(true)',
        'setAutoWrapMode(false)',
      ]);
    });

    test('mouse mode 9 maps to clickOnly/none', () {
      parser.write('\x1b[?9h\x1b[?9l');
      expect(handler.calls, [
        'setMouseMode(clickOnly)',
        'setMouseMode(none)',
      ]);
    });

    test('cursor blink modes 12 and 13', () {
      parser.write('\x1b[?12h\x1b[?13l');
      expect(handler.calls, [
        'setCursorBlinkMode(true)',
        'setCursorBlinkMode(false)',
      ]);
    });

    test('DECTCEM cursor visible mode (25)', () {
      parser.write('\x1b[?25h\x1b[?25l');
      expect(handler.calls, [
        'setCursorVisibleMode(true)',
        'setCursorVisibleMode(false)',
      ]);
    });

    test('mode 47 switches between alt and main buffer', () {
      parser.write('\x1b[?47h\x1b[?47l');
      expect(handler.calls, ['useAltBuffer()', 'useMainBuffer()']);
    });

    test('mode 66 maps to app keypad mode', () {
      parser.write('\x1b[?66h\x1b[?66l');
      expect(handler.calls, [
        'setAppKeypadMode(true)',
        'setAppKeypadMode(false)',
      ]);
    });

    test('mouse modes 1000-1003 and the 10061000 quirk', () {
      parser.write('\x1b[?1000h');
      parser.write('\x1b[?1001h');
      parser.write('\x1b[?1002h');
      parser.write('\x1b[?1003h');
      parser.write('\x1b[?10061000h');
      parser.write('\x1b[?1000l');
      parser.write('\x1b[?1001l');
      parser.write('\x1b[?1002l');
      parser.write('\x1b[?1003l');
      expect(handler.calls, [
        'setMouseMode(upDownScroll)',
        'setMouseMode(upDownScroll)',
        'setMouseMode(upDownScrollDrag)',
        'setMouseMode(upDownScrollMove)',
        'setMouseMode(upDownScroll)',
        'setMouseMode(none)',
        'setMouseMode(none)',
        'setMouseMode(none)',
        'setMouseMode(none)',
      ]);
    });

    test('mode 1004 toggles report focus', () {
      parser.write('\x1b[?1004h\x1b[?1004l');
      expect(handler.calls, [
        'setReportFocusMode(true)',
        'setReportFocusMode(false)',
      ]);
    });

    test('mouse report modes 1005/1006/1015', () {
      parser.write('\x1b[?1005h');
      parser.write('\x1b[?1006h');
      parser.write('\x1b[?1015h');
      parser.write('\x1b[?1005l');
      parser.write('\x1b[?1006l');
      parser.write('\x1b[?1015l');
      expect(handler.calls, [
        'setMouseReportMode(utf)',
        'setMouseReportMode(sgr)',
        'setMouseReportMode(urxvt)',
        'setMouseReportMode(normal)',
        'setMouseReportMode(normal)',
        'setMouseReportMode(normal)',
      ]);
    });

    test('mode 1007 toggles alt buffer mouse scroll', () {
      parser.write('\x1b[?1007h\x1b[?1007l');
      expect(handler.calls, [
        'setAltBufferMouseScrollMode(true)',
        'setAltBufferMouseScrollMode(false)',
      ]);
    });

    test('mode 1047 enable uses alt buffer, disable clears then uses main', () {
      parser.write('\x1b[?1047h\x1b[?1047l');
      expect(handler.calls, [
        'useAltBuffer()',
        'clearAltBuffer()',
        'useMainBuffer()',
      ]);
    });

    test('mode 1048 saves/restores cursor', () {
      parser.write('\x1b[?1048h\x1b[?1048l');
      expect(handler.calls, ['saveCursor()', 'restoreCursor()']);
    });

    test('mode 1049 enable saves cursor, clears and uses alt buffer', () {
      parser.write('\x1b[?1049h');
      expect(handler.calls, [
        'saveCursor()',
        'clearAltBuffer()',
        'useAltBuffer()',
      ]);
    });

    test('mode 1049 disable returns to main buffer', () {
      parser.write('\x1b[?1049l');
      expect(handler.calls, ['useMainBuffer()']);
    });

    test('mode 2004 toggles bracketed paste', () {
      parser.write('\x1b[?2004h\x1b[?2004l');
      expect(handler.calls, [
        'setBracketedPasteMode(true)',
        'setBracketedPasteMode(false)',
      ]);
    });

    test('unknown DEC mode is forwarded to setUnknownDecMode', () {
      parser.write('\x1b[?9001h\x1b[?9001l');
      expect(handler.calls, [
        'setUnknownDecMode(9001, true)',
        'setUnknownDecMode(9001, false)',
      ]);
    });

    test('multiple DEC modes in one sequence are all applied', () {
      parser.write('\x1b[?1;7h');
      expect(handler.calls, [
        'setCursorKeysMode(true)',
        'setAutoWrapMode(true)',
      ]);
    });
  });

  group('SGR', () {
    test('CSI m without params resets the style', () {
      parser.write('\x1b[m');
      expect(handler.calls, ['resetCursorStyle()']);
    });

    test('param 0 resets the style', () {
      parser.write('\x1b[0m');
      expect(handler.calls, ['resetCursorStyle()']);
    });

    test('attribute params 1-9 set styles', () {
      parser.write('\x1b[1;2;3;4;5;7;8;9m');
      expect(handler.calls, [
        'setCursorBold()',
        'setCursorFaint()',
        'setCursorItalic()',
        'setCursorUnderline()',
        'setCursorBlink()',
        'setCursorInverse()',
        'setCursorInvisible()',
        'setCursorStrikethrough()',
      ]);
    });

    test('attribute params 21-29 unset styles', () {
      parser.write('\x1b[21;22;23;24;25;27;28;29m');
      expect(handler.calls, [
        'unsetCursorBold()',
        'unsetCursorFaint()',
        'unsetCursorItalic()',
        'unsetCursorUnderline()',
        'unsetCursorBlink()',
        'unsetCursorInverse()',
        'unsetCursorInvisible()',
        'unsetCursorStrikethrough()',
      ]);
    });

    test('standard foreground colors 30-37', () {
      parser.write('\x1b[30;31;32;33;34;35;36;37m');
      expect(handler.calls, [
        'setForegroundColor16(0)',
        'setForegroundColor16(1)',
        'setForegroundColor16(2)',
        'setForegroundColor16(3)',
        'setForegroundColor16(4)',
        'setForegroundColor16(5)',
        'setForegroundColor16(6)',
        'setForegroundColor16(7)',
      ]);
    });

    test('standard background colors 40-47', () {
      parser.write('\x1b[40;41;42;43;44;45;46;47m');
      expect(handler.calls, [
        'setBackgroundColor16(0)',
        'setBackgroundColor16(1)',
        'setBackgroundColor16(2)',
        'setBackgroundColor16(3)',
        'setBackgroundColor16(4)',
        'setBackgroundColor16(5)',
        'setBackgroundColor16(6)',
        'setBackgroundColor16(7)',
      ]);
    });

    test('bright foreground colors 90-97', () {
      parser.write('\x1b[90;91;92;93;94;95;96;97m');
      expect(handler.calls, [
        'setForegroundColor16(8)',
        'setForegroundColor16(9)',
        'setForegroundColor16(10)',
        'setForegroundColor16(11)',
        'setForegroundColor16(12)',
        'setForegroundColor16(13)',
        'setForegroundColor16(14)',
        'setForegroundColor16(15)',
      ]);
    });

    test('bright background colors 100-107', () {
      parser.write('\x1b[100;101;102;103;104;105;106;107m');
      expect(handler.calls, [
        'setBackgroundColor16(8)',
        'setBackgroundColor16(9)',
        'setBackgroundColor16(10)',
        'setBackgroundColor16(11)',
        'setBackgroundColor16(12)',
        'setBackgroundColor16(13)',
        'setBackgroundColor16(14)',
        'setBackgroundColor16(15)',
      ]);
    });

    test('38;5 selects a 256-color foreground', () {
      parser.write('\x1b[38;5;196m');
      expect(handler.calls, ['setForegroundColor256(196)']);
    });

    test('48;5 selects a 256-color background', () {
      parser.write('\x1b[48;5;21m');
      expect(handler.calls, ['setBackgroundColor256(21)']);
    });

    test('38;2 selects an RGB foreground', () {
      parser.write('\x1b[38;2;10;20;30m');
      expect(handler.calls, ['setForegroundColorRgb(10, 20, 30)']);
    });

    test('48;2 selects an RGB background', () {
      parser.write('\x1b[48;2;255;128;0m');
      expect(handler.calls, ['setBackgroundColorRgb(255, 128, 0)']);
    });

    test('39 and 49 reset foreground and background', () {
      parser.write('\x1b[39;49m');
      expect(handler.calls, ['resetForeground()', 'resetBackground()']);
    });

    test('color sequence followed by more params continues parsing', () {
      parser.write('\x1b[38;5;196;1m');
      expect(handler.calls, ['setForegroundColor256(196)', 'setCursorBold()']);
    });

    test('unknown color mode falls through and parses remaining params', () {
      // 38;1 is not a valid color mode: the parser consumes nothing extra
      // and treats the following params as regular SGR params.
      parser.write('\x1b[38;1;5m');
      expect(handler.calls, ['setCursorBold()', 'setCursorBlink()']);
    });

    test('truncated 38;5 foreground throws a RangeError', () {
      // Documents a bug: missing color index crashes with RangeError.
      expect(() => parser.write('\x1b[38;5m'), throwsRangeError);
    });

    test('truncated 38;2 foreground throws a RangeError', () {
      // Documents a bug: missing RGB components crash with RangeError.
      expect(() => parser.write('\x1b[38;2;10;20m'), throwsRangeError);
    });

    test('truncated 48 background throws a RangeError', () {
      expect(() => parser.write('\x1b[48m'), throwsRangeError);
    });

    test('unsupported params are reported individually', () {
      parser.write('\x1b[6;10;53m');
      expect(handler.calls, [
        'unsupportedStyle(6)',
        'unsupportedStyle(10)',
        'unsupportedStyle(53)',
      ]);
    });

    test('reset in the middle of a sequence applies in order', () {
      parser.write('\x1b[31;0;1m');
      expect(handler.calls, [
        'setForegroundColor16(1)',
        'resetCursorStyle()',
        'setCursorBold()',
      ]);
    });
  });

  group('OSC', () {
    test('OSC 0 sets both title and icon name (BEL terminated)', () {
      parser.write('\x1b]0;title\x07');
      expect(handler.calls, ['setTitle(title)', 'setIconName(title)']);
    });

    test('OSC 1 sets icon name only', () {
      parser.write('\x1b]1;icon\x07');
      expect(handler.calls, ['setIconName(icon)']);
    });

    test('OSC 2 sets title only (ST terminated)', () {
      parser.write('\x1b]2;title\x1b\\');
      expect(handler.calls, ['setTitle(title)']);
    });

    test('OSC 0 with empty title still dispatches', () {
      parser.write('\x1b]0;\x07');
      expect(handler.calls, ['setTitle()', 'setIconName()']);
    });

    test('unknown OSC is forwarded with code and args', () {
      parser.write('\x1b]4;1;red\x07');
      expect(handler.calls, ['unknownOSC(4, 1|red)']);
    });

    test('unknown OSC with empty arg preserves it', () {
      parser.write('\x1b]8;;http://example.com\x07');
      expect(handler.calls, ['unknownOSC(8, |http://example.com)']);
    });

    test('empty OSC is forwarded as unknownOSC with empty code', () {
      parser.write('\x1b]\x07');
      expect(handler.calls, ['unknownOSC(, )']);
    });

    test('OSC terminated by ESC not followed by backslash drops last param', () {
      // Documents current behavior: the dangling param is discarded and the
      // char after ESC is swallowed.
      parser.write('\x1b]0;ab\x1bX');
      expect(handler.calls, ['unknownOSC(0, )']);
    });
  });

  group('chunked writes and incomplete sequences', () {
    test('lone ESC is held back until the next chunk', () {
      parser.write('\x1b');
      expect(handler.calls, isEmpty);
      parser.write('7');
      expect(handler.calls, ['saveCursor()']);
    });

    test('CSI split across chunks is buffered and completed', () {
      parser.write('\x1b[8;24');
      expect(handler.calls, isEmpty);
      parser.write(';80t');
      expect(handler.calls, ['resize(80, 24)']);
    });

    test('CSI split after the final byte prefix', () {
      parser.write('\x1b[');
      parser.write('?25');
      expect(handler.calls, isEmpty);
      parser.write('h');
      expect(handler.calls, ['setCursorVisibleMode(true)']);
    });

    test('text before an incomplete CSI is still processed', () {
      parser.write('ab\x1b[5');
      expect(handler.calls, ['writeChar(97)', 'writeChar(98)']);
      parser.write('C');
      expect(handler.calls, ['writeChar(97)', 'writeChar(98)', 'moveCursorX(5)']);
    });

    test('OSC split across chunks', () {
      parser.write('\x1b]0;ti');
      expect(handler.calls, isEmpty);
      parser.write('tle\x07');
      expect(handler.calls, ['setTitle(title)', 'setIconName(title)']);
    });

    test('OSC ST split between ESC and backslash', () {
      parser.write('\x1b]2;title\x1b');
      expect(handler.calls, isEmpty);
      parser.write('\\');
      expect(handler.calls, ['setTitle(title)']);
    });

    test('charset designator split across chunks', () {
      parser.write('\x1b)');
      expect(handler.calls, isEmpty);
      parser.write('0');
      expect(handler.calls, ['designateCharset(1, 48)']);
    });

    test('multiple sequences in a single chunk are all dispatched', () {
      parser.write('\x1b[1mX\x1b[0m');
      expect(handler.calls, [
        'setCursorBold()',
        'writeChar(88)',
        'resetCursorStyle()',
      ]);
    });
  });

  group('malformed sequences', () {
    test('unknown CSI final byte is reported', () {
      parser.write('\x1b[q');
      expect(handler.calls, ['unknownCSI(113)']);
    });

    test('unknown CSI with params reports only the final byte', () {
      parser.write('\x1b[1;2q');
      expect(handler.calls, ['unknownCSI(113)']);
    });

    test('intermediate bytes inside a CSI are skipped', () {
      parser.write('\x1b[1 q');
      expect(handler.calls, ['unknownCSI(113)']);
    });

    test('NUL bytes inside a CSI are skipped', () {
      parser.write('\x1b[\x005m');
      expect(handler.calls, ['setCursorBlink()']);
    });

    test('leading semicolon is parsed as a CSI prefix', () {
      // ';' (59) lies in the parser prefix range ':'..'?'. CSI ; 5 m is
      // therefore treated as prefixed, leaving 5 as the only param.
      parser.write('\x1b[;5m');
      expect(handler.calls, ['setCursorBlink()']);
    });

    test('colon prefix is accepted and reaches the DA fallback', () {
      parser.write('\x1b[:c');
      expect(handler.calls, ['sendPrimaryDeviceAttributes()']);
    });

    test('trailing semicolon produces an implicit 0 param', () {
      // The parser never resets its hasParam flag, so a trailing ';' leaves
      // a pending param that is flushed as 0 when the final byte arrives.
      parser.write('\x1b[5;m');
      expect(handler.calls, ['setCursorBlink()', 'resetCursorStyle()']);
    });

    test('empty param between semicolons becomes 0', () {
      // Same hasParam quirk: CSI 5;;1m is parsed as [5, 0, 1] which matches
      // the ECMA-48 rule that an empty param means the default (0).
      parser.write('\x1b[5;;1m');
      expect(handler.calls, [
        'setCursorBlink()',
        'resetCursorStyle()',
        'setCursorBold()',
      ]);
    });
  });

  group('token tracking', () {
    test('tokenBegin/tokenEnd track the last processed character', () {
      parser.write('ab');
      expect(parser.tokenBegin, 1);
      expect(parser.tokenEnd, 2);
    });

    test('tokenEnd accumulates across writes', () {
      parser.write('a');
      parser.write('bc');
      expect(parser.tokenEnd, 3);
    });

    test('held-back escape does not advance tokenEnd', () {
      parser.write('a\x1b');
      expect(parser.tokenEnd, 1);
      parser.write('7');
      expect(parser.tokenBegin, 1);
      expect(parser.tokenEnd, 3);
    });
  });
}
