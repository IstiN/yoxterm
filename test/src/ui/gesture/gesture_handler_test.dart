import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  Future<TerminalViewState> pumpTerminalView(
    WidgetTester tester,
    Terminal terminal, {
    TerminalController? controller,
    void Function(TapUpDetails, CellOffset)? onTapUp,
    void Function(TapDownDetails, CellOffset)? onSecondaryTapDown,
    void Function(TapUpDetails, CellOffset)? onSecondaryTapUp,
    bool readOnly = false,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TerminalView(
          terminal,
          controller: controller,
          onTapUp: onTapUp,
          onSecondaryTapDown: onSecondaryTapDown,
          onSecondaryTapUp: onSecondaryTapUp,
          readOnly: readOnly,
        ),
      ),
    ));
    return tester.state<TerminalViewState>(find.byType(TerminalView));
  }

  group('TerminalGestureHandler.tap', () {
    testWidgets('tap is sent to the terminal when mouse reporting is on',
        (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.write('\x1b[?1000h');

      await pumpTerminalView(tester, terminal);

      await tester.tap(find.byType(TerminalView));
      await tester.pump();

      // Mouse down and up reports for the left button.
      expect(output, isNotEmpty);
      expect(output.join(), contains('\x1B[M'));

      // Flush the internal double tap timer.
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    });

    testWidgets('tap is not sent to the terminal in readOnly mode',
        (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.write('\x1b[?1000h');

      await pumpTerminalView(tester, terminal, readOnly: true);

      await tester.tap(find.byType(TerminalView));
      await tester.pump();

      expect(output, isEmpty);

      // Flush the internal double tap timer.
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    });

    testWidgets('tap down clears the active selection', (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();

      await pumpTerminalView(tester, terminal, controller: controller);

      controller.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(2, 2),
      );
      await tester.pump();
      expect(controller.selection, isNotNull);

      await tester.tap(find.byType(TerminalView));
      await tester.pump();

      expect(controller.selection, isNull);

      // Flush the internal double tap timer.
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    });

    testWidgets('secondary tap callbacks receive cell offsets', (tester) async {
      final terminal = Terminal();
      TapDownDetails? downDetails;
      CellOffset? downOffset;
      CellOffset? upOffset;

      await pumpTerminalView(
        tester,
        terminal,
        onSecondaryTapDown: (details, offset) {
          downDetails = details;
          downOffset = offset;
        },
        onSecondaryTapUp: (_, offset) => upOffset = offset,
      );

      await tester.tap(
        find.byType(TerminalView),
        buttons: kSecondaryButton,
      );
      await tester.pump();

      expect(downDetails, isNotNull);
      expect(downOffset, isNotNull);
      expect(upOffset, isNotNull);
    });
  });

  group('TerminalGestureHandler.selection', () {
    testWidgets('double tap down selects the word under the pointer',
        (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();

      terminal.write('hello world');

      await pumpTerminalView(tester, terminal, controller: controller);
      await tester.pump();

      expect(controller.selection, isNull);

      final origin = tester.getTopLeft(find.byType(TerminalView));

      await tester.tapAt(origin + const Offset(4, 4));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(origin + const Offset(4, 4));
      await tester.pump();

      expect(controller.selection, isNotNull);
      expect(terminal.buffer.getText(controller.selection!), 'hello');
    });

    testWidgets('mouse drag selects characters', (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();

      terminal.write('hello world');

      await pumpTerminalView(tester, terminal, controller: controller);
      await tester.pump();

      final origin = tester.getTopLeft(find.byType(TerminalView));

      final gesture = await tester.startGesture(
        origin + const Offset(4, 4),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();

      expect(controller.selection, isNotNull);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('long press selects the word under the pointer',
        (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();

      terminal.write('hello world');

      await pumpTerminalView(tester, terminal, controller: controller);
      await tester.pump();

      final origin = tester.getTopLeft(find.byType(TerminalView));

      await tester.longPressAt(origin + const Offset(4, 4));
      await tester.pump();

      expect(controller.selection, isNotNull);
      expect(terminal.buffer.getText(controller.selection!), 'hello');
    });
  });
}
