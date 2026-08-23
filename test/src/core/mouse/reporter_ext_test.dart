import 'package:test/test.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/core/mouse/mode.dart';
import 'package:xterm/src/core/mouse/reporter.dart';

void main() {
  group('MouseReporter: normal mode', () {
    test('release is reported with button id 3', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.up,
        const CellOffset(0, 0),
        MouseReportMode.normal,
      );

      // Button char is 32 + 3 = '#'.
      expect(output, startsWith('\x1b[M#'));
    });

    test('positions are 1-based and offset by 32', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        const CellOffset(9, 4),
        MouseReportMode.normal,
      );

      // x = 10 -> '*' (42).
      expect(output[4], '*');
    });

    test('columns beyond 223 are reported as a null byte', () {
      final atLimit = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        const CellOffset(222, 0),
        MouseReportMode.normal,
      );
      expect(atLimit[4], String.fromCharCode(32 + 223));

      final beyondLimit = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        const CellOffset(223, 0),
        MouseReportMode.normal,
      );
      expect(beyondLimit[4], '\x00');
    });

    test('row is encoded as 32 + y with 1-based y', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        const CellOffset(0, 0),
        MouseReportMode.normal,
      );

      // y = 1 at the origin -> '!' (33), matching the column encoding.
      expect(output[5], '!');
    });

    test('wheel buttons use their standard ids', () {
      final output = MouseReporter.report(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        const CellOffset(0, 0),
        MouseReportMode.normal,
      );

      // 32 + 64 = 96 = '`'.
      expect(output[3], '`');
    });
  });

  group('MouseReporter: utf mode', () {
    test('matches normal mode for small coordinates', () {
      for (final mode in [MouseReportMode.normal, MouseReportMode.utf]) {
        final output = MouseReporter.report(
          TerminalMouseButton.middle,
          TerminalMouseButtonState.down,
          const CellOffset(2, 3),
          mode,
        );
        expect(output[3], String.fromCharCode(32 + 1), reason: '$mode');
        expect(output[4], String.fromCharCode(32 + 3), reason: '$mode');
      }
    });

    test('columns beyond 2015 are reported as a null byte', () {
      final atLimit = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        const CellOffset(2014, 0),
        MouseReportMode.utf,
      );
      expect(atLimit[4], String.fromCharCode(32 + 2015));

      final beyondLimit = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        const CellOffset(2015, 0),
        MouseReportMode.utf,
      );
      expect(beyondLimit[4], '\x00');
    });

    test('utf mode allows coordinates past the normal limit', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        const CellOffset(300, 0),
        MouseReportMode.utf,
      );
      expect(output[4], String.fromCharCode(32 + 301));
    });

    test('wheel buttons use their standard ids', () {
      final output = MouseReporter.report(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        const CellOffset(0, 0),
        MouseReportMode.utf,
      );

      // 32 + 64 = 96 = '`'.
      expect(output[3], '`');
    });
  });

  group('MouseReporter: sgr mode', () {
    test('press uses M suffix, release uses m suffix', () {
      final down = MouseReporter.report(
        TerminalMouseButton.right,
        TerminalMouseButtonState.down,
        const CellOffset(4, 9),
        MouseReportMode.sgr,
      );
      expect(down, '\x1b[<2;5;10M');

      final up = MouseReporter.report(
        TerminalMouseButton.right,
        TerminalMouseButtonState.up,
        const CellOffset(4, 9),
        MouseReportMode.sgr,
      );
      expect(up, '\x1b[<2;5;10m');
    });

    test('wheel buttons are reported with their raw ids', () {
      expect(
        MouseReporter.report(
          TerminalMouseButton.wheelUp,
          TerminalMouseButtonState.down,
          const CellOffset(0, 0),
          MouseReportMode.sgr,
        ),
        '\x1b[<64;1;1M',
      );
      expect(
        MouseReporter.report(
          TerminalMouseButton.wheelRight,
          TerminalMouseButtonState.down,
          const CellOffset(0, 0),
          MouseReportMode.sgr,
        ),
        '\x1b[<67;1;1M',
      );
    });

    test('large coordinates are supported', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        const CellOffset(4999, 5999),
        MouseReportMode.sgr,
      );
      expect(output, '\x1b[<0;5000;6000M');
    });
  });

  group('MouseReporter: urxvt mode', () {
    test('button id is shifted by 32', () {
      expect(
        MouseReporter.report(
          TerminalMouseButton.left,
          TerminalMouseButtonState.down,
          const CellOffset(0, 0),
          MouseReportMode.urxvt,
        ),
        '\x1b[32;1;1M',
      );
      expect(
        MouseReporter.report(
          TerminalMouseButton.right,
          TerminalMouseButtonState.down,
          const CellOffset(2, 4),
          MouseReportMode.urxvt,
        ),
        '\x1b[34;3;5M',
      );
    });

    test('release uses button id 3 shifted by 32', () {
      expect(
        MouseReporter.report(
          TerminalMouseButton.left,
          TerminalMouseButtonState.up,
          const CellOffset(0, 0),
          MouseReportMode.urxvt,
        ),
        '\x1b[35;1;1M',
      );
    });

    test('wheel buttons use their standard ids shifted by 32', () {
      expect(
        MouseReporter.report(
          TerminalMouseButton.wheelUp,
          TerminalMouseButtonState.down,
          const CellOffset(0, 0),
          MouseReportMode.urxvt,
        ),
        '\x1b[96;1;1M',
      );
    });
  });
}
