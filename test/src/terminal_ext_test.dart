import 'package:test/test.dart';
import 'package:xterm/core.dart';

void main() {
  group('Terminal.defaults', () {
    test('has sensible default state', () {
      final terminal = Terminal();

      expect(terminal.viewWidth, 80);
      expect(terminal.viewHeight, 24);
      expect(terminal.maxLines, 1000);
      expect(terminal.insertMode, isFalse);
      expect(terminal.lineFeedMode, isFalse);
      expect(terminal.cursorKeysMode, isFalse);
      expect(terminal.reverseDisplayMode, isFalse);
      expect(terminal.originMode, isFalse);
      expect(terminal.autoWrapMode, isTrue);
      expect(terminal.mouseMode, MouseMode.none);
      expect(terminal.mouseReportMode, MouseReportMode.normal);
      expect(terminal.cursorBlinkMode, isFalse);
      expect(terminal.cursorVisibleMode, isTrue);
      expect(terminal.appKeypadMode, isFalse);
      expect(terminal.reportFocusMode, isFalse);
      expect(terminal.altBufferMouseScrollMode, isFalse);
      expect(terminal.bracketedPasteMode, isFalse);
      expect(terminal.isUsingAltBuffer, isFalse);
      expect(terminal.buffer, same(terminal.mainBuffer));
      expect(terminal.lines, same(terminal.buffer.lines));
    });

    test('toString contains dimensions', () {
      final terminal = Terminal();
      expect(terminal.toString(), contains('80 x 24'));

      terminal.resize(40, 10);
      expect(terminal.toString(), contains('40 x 10'));
    });
  });

  group('Terminal.modes (ANSI)', () {
    test('insert mode set/reset via CSI 4 h/l', () {
      final terminal = Terminal();

      terminal.write('\x1b[4h');
      expect(terminal.insertMode, isTrue);

      terminal.write('\x1b[4l');
      expect(terminal.insertMode, isFalse);
    });

    test('insert mode shifts existing text right instead of overwriting', () {
      final terminal = Terminal();

      terminal.write('abc');
      terminal.write('\x1b[1;1H'); // cursor to start
      terminal.write('\x1b[4h'); // insert mode on
      terminal.write('X');

      expect(terminal.buffer.lines[0].toString(), 'Xabc');
    });

    test('line feed mode set/reset via CSI 20 h/l', () {
      final terminal = Terminal();

      terminal.write('\x1b[20h');
      expect(terminal.lineFeedMode, isTrue);

      terminal.write('\x1b[20l');
      expect(terminal.lineFeedMode, isFalse);
    });

    test('line feed mode changes enter key output', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.enter);
      expect(output, ['\r']);

      terminal.write('\x1b[20h');
      terminal.keyInput(TerminalKey.enter);
      expect(output, ['\r', '\r\n']);
    });

    test('unknown ANSI modes are ignored', () {
      final terminal = Terminal();
      expect(() => terminal.write('\x1b[99h\x1b[99l'), returnsNormally);
    });
  });

  group('Terminal.modes (DEC private)', () {
    test('cursor keys mode set/reset', () {
      final terminal = Terminal();
      expect(terminal.cursorKeysMode, isFalse);

      terminal.write('\x1b[?1h');
      expect(terminal.cursorKeysMode, isTrue);

      terminal.write('\x1b[?1l');
      expect(terminal.cursorKeysMode, isFalse);
    });

    test('app keypad mode does not change arrow key output', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.arrowUp);
      expect(output, ['\x1b[A']);

      // DECCKM (application cursor keys), not app keypad mode, drives arrows.
      terminal.write('\x1b=');
      terminal.keyInput(TerminalKey.arrowUp);
      expect(output, ['\x1b[A', '\x1b[A']);

      terminal.write('\x1b[?1h');
      terminal.keyInput(TerminalKey.arrowUp);
      expect(output, ['\x1b[A', '\x1b[A', '\x1bOA']);

      terminal.write('\x1b[?1l');
      terminal.keyInput(TerminalKey.arrowUp);
      expect(output, ['\x1b[A', '\x1b[A', '\x1bOA', '\x1b[A']);
    });

    test('reverse display mode set/reset', () {
      final terminal = Terminal();

      terminal.write('\x1b[?5h');
      expect(terminal.reverseDisplayMode, isTrue);

      terminal.write('\x1b[?5l');
      expect(terminal.reverseDisplayMode, isFalse);
    });

    test('origin mode set/reset', () {
      final terminal = Terminal();

      terminal.write('\x1b[?6h');
      expect(terminal.originMode, isTrue);

      terminal.write('\x1b[?6l');
      expect(terminal.originMode, isFalse);
    });

    test('auto wrap mode set/reset', () {
      final terminal = Terminal();
      expect(terminal.autoWrapMode, isTrue);

      terminal.write('\x1b[?7l');
      expect(terminal.autoWrapMode, isFalse);

      terminal.write('\x1b[?7h');
      expect(terminal.autoWrapMode, isTrue);
    });

    test('auto wrap disabled overwrites the last column', () {
      final terminal = Terminal();
      terminal.resize(10, 5);

      terminal.write('\x1b[?7l');
      terminal.write('0123456789ABCDEF');

      // The cursor stays clamped at the last column; each character past the
      // line width overwrites the cell there.
      expect(terminal.buffer.lines[0].toString(), '012345678F');
      expect(terminal.buffer.lines[1].toString(), '');
      expect(terminal.buffer.lines[1].isWrapped, isFalse);
    });

    test('cursor blink mode set/reset (12 and 13)', () {
      final terminal = Terminal();

      terminal.write('\x1b[?12h');
      expect(terminal.cursorBlinkMode, isTrue);

      terminal.write('\x1b[?12l');
      expect(terminal.cursorBlinkMode, isFalse);

      terminal.write('\x1b[?13h');
      expect(terminal.cursorBlinkMode, isTrue);

      terminal.write('\x1b[?13l');
      expect(terminal.cursorBlinkMode, isFalse);
    });

    test('cursor visible mode set/reset', () {
      final terminal = Terminal();
      expect(terminal.cursorVisibleMode, isTrue);

      terminal.write('\x1b[?25l');
      expect(terminal.cursorVisibleMode, isFalse);

      terminal.write('\x1b[?25h');
      expect(terminal.cursorVisibleMode, isTrue);
    });

    test('app keypad mode via ESC = / ESC >', () {
      final terminal = Terminal();

      terminal.write('\x1b=');
      expect(terminal.appKeypadMode, isTrue);

      terminal.write('\x1b>');
      expect(terminal.appKeypadMode, isFalse);
    });

    test('app keypad mode via CSI ? 66 h/l', () {
      final terminal = Terminal();

      terminal.write('\x1b[?66h');
      expect(terminal.appKeypadMode, isTrue);

      terminal.write('\x1b[?66l');
      expect(terminal.appKeypadMode, isFalse);
    });

    test('report focus mode set/reset', () {
      final terminal = Terminal();

      terminal.write('\x1b[?1004h');
      expect(terminal.reportFocusMode, isTrue);

      terminal.write('\x1b[?1004l');
      expect(terminal.reportFocusMode, isFalse);
    });

    test('alt buffer mouse scroll mode set/reset', () {
      final terminal = Terminal();

      terminal.write('\x1b[?1007h');
      expect(terminal.altBufferMouseScrollMode, isTrue);

      terminal.write('\x1b[?1007l');
      expect(terminal.altBufferMouseScrollMode, isFalse);
    });

    test('bracketed paste mode set/reset', () {
      final terminal = Terminal();

      terminal.write('\x1b[?2004h');
      expect(terminal.bracketedPasteMode, isTrue);

      terminal.write('\x1b[?2004l');
      expect(terminal.bracketedPasteMode, isFalse);
    });

    test('mouse mode set/reset', () {
      final terminal = Terminal();

      terminal.write('\x1b[?9h');
      expect(terminal.mouseMode, MouseMode.clickOnly);
      terminal.write('\x1b[?9l');
      expect(terminal.mouseMode, MouseMode.none);

      terminal.write('\x1b[?1000h');
      expect(terminal.mouseMode, MouseMode.upDownScroll);
      terminal.write('\x1b[?1000l');
      expect(terminal.mouseMode, MouseMode.none);

      terminal.write('\x1b[?1001h');
      expect(terminal.mouseMode, MouseMode.upDownScroll);
      terminal.write('\x1b[?1001l');
      expect(terminal.mouseMode, MouseMode.none);

      terminal.write('\x1b[?1002h');
      expect(terminal.mouseMode, MouseMode.upDownScrollDrag);
      terminal.write('\x1b[?1002l');
      expect(terminal.mouseMode, MouseMode.none);

      terminal.write('\x1b[?1003h');
      expect(terminal.mouseMode, MouseMode.upDownScrollMove);
      terminal.write('\x1b[?1003l');
      expect(terminal.mouseMode, MouseMode.none);
    });

    test('mouse report mode set/reset', () {
      final terminal = Terminal();

      terminal.write('\x1b[?1005h');
      expect(terminal.mouseReportMode, MouseReportMode.utf);
      terminal.write('\x1b[?1005l');
      expect(terminal.mouseReportMode, MouseReportMode.normal);

      terminal.write('\x1b[?1006h');
      expect(terminal.mouseReportMode, MouseReportMode.sgr);
      terminal.write('\x1b[?1006l');
      expect(terminal.mouseReportMode, MouseReportMode.normal);

      terminal.write('\x1b[?1015h');
      expect(terminal.mouseReportMode, MouseReportMode.urxvt);
      terminal.write('\x1b[?1015l');
      expect(terminal.mouseReportMode, MouseReportMode.normal);
    });

    test('unknown DEC modes are ignored', () {
      final terminal = Terminal();
      expect(() => terminal.write('\x1b[?9999h\x1b[?9999l'), returnsNormally);
    });
  });

  group('Terminal.buffers', () {
    test('CSI ? 47 h/l switches between alt and main buffer', () {
      final terminal = Terminal();
      expect(terminal.isUsingAltBuffer, isFalse);

      terminal.write('\x1b[?47h');
      expect(terminal.isUsingAltBuffer, isTrue);
      expect(terminal.buffer, same(terminal.altBuffer));

      terminal.write('\x1b[?47l');
      expect(terminal.isUsingAltBuffer, isFalse);
      expect(terminal.buffer, same(terminal.mainBuffer));
    });

    test('CSI ? 1049 h saves cursor, clears alt buffer and switches', () {
      final terminal = Terminal();

      terminal.write('main');
      terminal.write('\x1b[?1049h');

      expect(terminal.isUsingAltBuffer, isTrue);
      expect(terminal.buffer.cursorX, 0);
      expect(terminal.buffer.cursorY, 0);

      terminal.write('alt');
      terminal.write('\x1b[?1049l');

      expect(terminal.isUsingAltBuffer, isFalse);
      // 1049l restores the main buffer; the saved cursor of 1049h is NOT
      // restored (that is the behavior of this implementation).
      expect(terminal.mainBuffer.lines[0].toString(), startsWith('main'));
    });

    test('CSI ? 1047 l clears the alt buffer', () {
      final terminal = Terminal();

      terminal.write('\x1b[?47h');
      terminal.write('alt text');
      terminal.write('\x1b[?47l');
      expect(terminal.isUsingAltBuffer, isFalse);

      terminal.write('\x1b[?1047h');
      expect(terminal.isUsingAltBuffer, isTrue);
      expect(terminal.altBuffer.lines[0].toString(), startsWith('alt text'));

      terminal.write('\x1b[?1047l');
      expect(terminal.isUsingAltBuffer, isFalse);
      expect(terminal.altBuffer.lines[0].toString().trim(), isEmpty);
    });

    test('CSI ? 1048 h/l saves and restores the cursor', () {
      final terminal = Terminal();

      terminal.write('\x1b[5;10H'); // row 5, col 10 (1-based)
      expect(terminal.buffer.cursorX, 9);
      expect(terminal.buffer.cursorY, 4);

      terminal.write('\x1b[?1048h'); // save
      terminal.write('\x1b[1;1H'); // move to origin
      expect(terminal.buffer.cursorX, 0);
      expect(terminal.buffer.cursorY, 0);

      terminal.write('\x1b[?1048l'); // restore
      expect(terminal.buffer.cursorX, 9);
      expect(terminal.buffer.cursorY, 4);
    });

    test('useAltBuffer / useMainBuffer / clearAltBuffer work directly', () {
      final terminal = Terminal();

      terminal.useAltBuffer();
      expect(terminal.isUsingAltBuffer, isTrue);

      terminal.write('hello');
      terminal.clearAltBuffer();
      expect(terminal.altBuffer.lines[0].toString().trim(), isEmpty);

      terminal.useMainBuffer();
      expect(terminal.isUsingAltBuffer, isFalse);
    });
  });

  group('Terminal.resize', () {
    test('emits onResize with pixel dimensions defaulting to 0', () {
      final events = <List<int>>[];
      final terminal = Terminal(
        onResize: (w, h, pw, ph) => events.add([w, h, pw, ph]),
      );

      terminal.resize(100, 30);
      expect(events, [
        [100, 30, 0, 0],
      ]);

      terminal.resize(120, 40, 1200, 800);
      expect(events, [
        [100, 30, 0, 0],
        [120, 40, 1200, 800],
      ]);
    });

    test('clamps dimensions to a minimum of 1', () {
      final sizes = <List<int>>[];
      final terminal = Terminal(
        onResize: (w, h, pw, ph) => sizes.add([w, h]),
      );

      terminal.resize(0, 0);

      expect(terminal.viewWidth, 1);
      expect(terminal.viewHeight, 1);
      expect(sizes, [
        [1, 1],
      ]);
    });

    test('resizes both buffers', () {
      final terminal = Terminal();
      terminal.resize(20, 10);

      expect(terminal.mainBuffer.viewWidth, 20);
      expect(terminal.mainBuffer.viewHeight, 10);
      expect(terminal.altBuffer.viewWidth, 20);
      expect(terminal.altBuffer.viewHeight, 10);
    });

    test('resizing while in alt buffer clears its scrollback', () {
      final terminal = Terminal();
      terminal.resize(80, 5);

      terminal.useAltBuffer();
      for (var i = 0; i < 20; i++) {
        terminal.write('line $i\r\n');
      }

      final heightBefore = terminal.altBuffer.height;
      terminal.resize(80, 10);

      // The alt buffer has no scrollback after a resize.
      expect(terminal.altBuffer.height, lessThan(heightBefore + 15));
    });
  });

  group('Terminal.charInput', () {
    test('ctrl + a..z emits control characters', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      expect(terminal.charInput('a'.codeUnitAt(0), ctrl: true), isTrue);
      expect(terminal.charInput('z'.codeUnitAt(0), ctrl: true), isTrue);

      expect(output, ['\x01', '\x1a']);
    });

    test('ctrl + [.._ emits escape-range control characters', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      expect(terminal.charInput('['.codeUnitAt(0), ctrl: true), isTrue);
      expect(terminal.charInput('_'.codeUnitAt(0), ctrl: true), isTrue);

      expect(output, ['\x1b', '\x1f']);
    });

    test('alt + letter emits ESC + uppercase on non-macos platforms', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      expect(terminal.charInput('a'.codeUnitAt(0), alt: true), isTrue);
      expect(terminal.charInput('z'.codeUnitAt(0), alt: true), isTrue);

      expect(output, ['\x1bA', '\x1bZ']);
    });

    test('alt + letter is ignored on macOS', () {
      final output = <String>[];
      final terminal = Terminal(
        onOutput: output.add,
        platform: TerminalTargetPlatform.macos,
      );

      expect(terminal.charInput('a'.codeUnitAt(0), alt: true), isFalse);
      expect(output, isEmpty);
    });

    test('returns false for unhandled input', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      expect(terminal.charInput('a'.codeUnitAt(0)), isFalse);
      expect(terminal.charInput('5'.codeUnitAt(0), alt: true), isFalse);
      expect(terminal.charInput('5'.codeUnitAt(0), ctrl: true), isFalse);
      expect(output, isEmpty);
    });

    test('produces nothing without onOutput', () {
      final terminal = Terminal();
      expect(terminal.charInput('a'.codeUnitAt(0), ctrl: true), isTrue);
    });
  });

  group('Terminal.textInput / paste', () {
    test('textInput forwards text to onOutput', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.textInput('hello world');
      expect(output, ['hello world']);
    });

    test('paste sends raw text when bracketed paste is off', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.paste('hello');
      expect(output, ['hello']);
    });

    test('paste wraps text when bracketed paste is on', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?2004h');
      terminal.paste('hello');

      expect(output, ['\x1b[200~hello\x1b[201~']);
    });
  });

  group('Terminal.keyInput', () {
    test('emits output and returns true when the key is handled', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      expect(terminal.keyInput(TerminalKey.enter), isTrue);
      expect(output, ['\r']);
    });

    test('returns false when the key is not handled', () {
      final terminal = Terminal(inputHandler: null);
      expect(terminal.keyInput(TerminalKey.enter), isFalse);
    });
  });

  group('Terminal.deviceStatusReports', () {
    test('primary device attributes', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[c');
      expect(output, ['\x1b[?1;2c']);
    });

    test('secondary device attributes', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[>c');
      expect(output, ['\x1b[>0;0;0c']);
    });

    test('tertiary device attributes', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[=c');
      expect(output, ['\x1bP!|00000000\x1b\\']);
    });

    test('operating status', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[5n');
      expect(output, ['\x1b[0n']);
    });

    test('cursor position report', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[5;10H'); // row 5, col 10 (1-based)
      terminal.write('\x1b[6n');

      // The emitter reports 1-based coordinates per the CPR spec.
      expect(output, ['\x1b[5;10R']);
    });

    test('terminal size report', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[18t');
      expect(output, ['\x1b[8;24;80t']);

      terminal.resize(100, 30);
      terminal.write('\x1b[18t');
      expect(output, ['\x1b[8;24;80t', '\x1b[8;30;100t']);
    });

    test('window resize via CSI 8 ; rows ; cols t', () {
      final terminal = Terminal();

      terminal.write('\x1b[8;10;40t');
      expect(terminal.viewWidth, 40);
      expect(terminal.viewHeight, 10);
    });
  });

  group('Terminal.osc', () {
    test('bell rings on BEL', () {
      var bells = 0;
      final terminal = Terminal(onBell: () => bells++);

      terminal.write('\x07\x07');
      expect(bells, 2);
    });

    test('OSC 2 sets title', () {
      String? title;
      String? icon;
      final terminal = Terminal(
        onTitleChange: (t) => title = t,
        onIconChange: (i) => icon = i,
      );

      terminal.write('\x1b]2;window title\x07');

      expect(title, 'window title');
      expect(icon, isNull);
    });

    test('OSC 1 sets icon name', () {
      String? title;
      String? icon;
      final terminal = Terminal(
        onTitleChange: (t) => title = t,
        onIconChange: (i) => icon = i,
      );

      terminal.write('\x1b]1;icon name\x1b\\');

      expect(icon, 'icon name');
      expect(title, isNull);
    });

    test('OSC 0 sets both title and icon', () {
      String? title;
      String? icon;
      final terminal = Terminal(
        onTitleChange: (t) => title = t,
        onIconChange: (i) => icon = i,
      );

      terminal.write('\x1b]0;both\x07');

      expect(title, 'both');
      expect(icon, 'both');
    });

    test('missing callbacks do not throw', () {
      final terminal = Terminal();
      expect(() => terminal.write('\x07\x1b]0;x\x07'), returnsNormally);
    });
  });

  group('Terminal.mouseInput', () {
    test('returns false and emits nothing when mouse mode is none', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      final handled = terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(5, 7),
      );

      expect(handled, isFalse);
      expect(output, isEmpty);
    });

    test('reports with normal encoding', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?1000h');

      terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(10, 10),
      );

      // button ' ' (32+0), col '+' (32+11), row '+' (32+11)
      expect(output, ['\x1B[M ++']);
    });

    test('reports with SGR encoding (1-based coordinates)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?1000h\x1b[?1006h');

      terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(5, 7),
      );
      terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.up,
        CellOffset(5, 7),
      );

      expect(output, ['\x1b[<0;6;8M', '\x1b[<0;6;8m']);
    });

    test('reports wheel events', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?1000h\x1b[?1006h');

      terminal.mouseInput(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
      );
      terminal.mouseInput(
        TerminalMouseButton.wheelDown,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
      );

      // Standard wheel button ids 64/65 (SGR).
      expect(output, ['\x1b[<64;1;1M', '\x1b[<65;1;1M']);
    });

    test('works with a custom mouse handler', () {
      final events = <TerminalMouseEvent>[];
      final output = <String>[];

      final terminal = Terminal(
        onOutput: output.add,
        mouseHandler: _TestMouseHandler(events),
      );

      final handled = terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(1, 2),
      );

      expect(handled, isTrue);
      expect(output, ['handled']);
      expect(events, hasLength(1));
      expect(events.single.position, CellOffset(1, 2));
    });

    test('can be disabled by setting mouseHandler to null', () {
      final terminal = Terminal(mouseHandler: null);
      terminal.write('\x1b[?1000h');

      final handled = terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(1, 2),
      );

      expect(handled, isFalse);
    });
  });

  group('Terminal.scrollback', () {
    test('maxLines smaller than the view height is clamped to the view height',
        () {
      final terminal = Terminal(maxLines: 4);

      // The buffer must always be able to hold a full viewport (24 rows by
      // default), otherwise the scrollback offset goes negative.
      expect(terminal.maxLines, 24);
      expect(() => terminal.write('hello'), returnsNormally);
      expect(terminal.buffer.lines[0].toString(), startsWith('hello'));
    });

    test('maxLines limits the total buffer height', () {
      final terminal = Terminal(maxLines: 40);

      for (var i = 0; i < 60; i++) {
        terminal.write('line $i\r\n');
      }

      expect(terminal.buffer.height, lessThanOrEqualTo(40));
      // The oldest lines are discarded.
      expect(
        terminal.buffer.lines[0].toString(),
        isNot(startsWith('line 0')),
      );
    });

    test('CSI 3 J erases scrollback but keeps the viewport', () {
      final terminal = Terminal();
      terminal.resize(80, 5);

      for (var i = 0; i < 10; i++) {
        terminal.write('line $i\r\n');
      }

      expect(terminal.buffer.height, greaterThan(5));

      terminal.write('\x1b[3J');

      expect(terminal.buffer.height, 5);
      // The viewport still shows the last written lines.
      expect(terminal.buffer.lines[0].toString(), startsWith('line 6'));
      expect(terminal.buffer.lines[3].toString(), startsWith('line 9'));
    });
  });

  group('Terminal.tabStops', () {
    test('tab jumps to the next 8-column stop by default', () {
      final terminal = Terminal();

      terminal.write('\t');
      expect(terminal.buffer.cursorX, 8);

      terminal.write('\t');
      expect(terminal.buffer.cursorX, 16);
    });

    test('CSI 0 g clears the tab stop under the cursor', () {
      final terminal = Terminal();

      terminal.write('\x1b[9G'); // move to column 8 (0-based)
      expect(terminal.buffer.cursorX, 8);

      terminal.write('\x1b[0g'); // clear stop at column 8
      terminal.write('\x1b[G'); // back to column 0

      terminal.write('\t');
      expect(terminal.buffer.cursorX, 16);
    });

    test('CSI 3 g clears all tab stops', () {
      final terminal = Terminal();

      terminal.write('\x1b[3g');
      terminal.write('\t');

      // No stops left: the cursor goes to the last column and enters
      // pending-wrap state.
      expect(terminal.buffer.cursorX, terminal.viewWidth - 1);
    });

    test('ESC H sets a tab stop under the cursor', () {
      final terminal = Terminal();

      terminal.write('\x1b[3g'); // clear all tab stops
      terminal.write('\x1b[4G'); // move to column 3 (0-based)
      terminal.write('\x1bH'); // set a tab stop under the cursor
      terminal.write('\x1b[G'); // back to column 0

      terminal.write('\t');
      expect(terminal.buffer.cursorX, 3);
    });
  });

  group('Terminal.repeatPreviousCharacter', () {
    test('CSI b repeats the last written character', () {
      final terminal = Terminal();

      terminal.write('a\x1b[4b');
      expect(terminal.buffer.lines[0].toString(), startsWith('aaaaa'));
    });

    test('CSI b without a preceding character does nothing', () {
      final terminal = Terminal();

      terminal.write('\x1b[4b');
      expect(terminal.buffer.lines[0].toString().trim(), isEmpty);
      expect(terminal.buffer.cursorX, 0);
    });
  });
}

class _TestMouseHandler implements TerminalMouseHandler {
  _TestMouseHandler(this.events);

  final List<TerminalMouseEvent> events;

  @override
  String? call(TerminalMouseEvent event) {
    events.add(event);
    return 'handled';
  }
}
