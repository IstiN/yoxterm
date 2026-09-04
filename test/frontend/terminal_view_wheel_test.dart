import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/xterm.dart';

/// Regression: TerminalScrollGestureHandler hands PointerEvent.position
/// (GLOBAL coordinates) to TerminalView's getCellOffset. The wiring must
/// convert them to the terminal's local space before encoding SGR mouse
/// reports — otherwise the reported cell is shifted by the window origin
/// and mouse-reporting TUIs (claude code, copilot) ignore the wheel, so
/// scrolling feels dead.
void main() {
  Future<String> wheelReport(WidgetTester tester, {required bool padded}) async {
    final terminal = Terminal(maxLines: 100);
    terminal.useAltBuffer();
    // Button-event tracking + SGR encoding, what copilot-style TUIs enable.
    terminal.write('\x1b[?1002h\x1b[?1006h');

    final body = TerminalView(terminal);
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: padded
              ? Padding(
                  padding: const EdgeInsets.only(left: 40, top: 30),
                  child: body,
                )
              : body,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final reports = <String>[];
    terminal.onOutput = reports.add;

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    // Hover the SAME cell relative to the terminal's top-left in both
    // layouts, so the encoded cell must match if (and only if) the global
    // position is converted to the terminal's local space.
    final viewOrigin = tester.getTopLeft(find.byType(TerminalView));
    await tester.sendEventToBinding(
      pointer.hover(viewOrigin + const Offset(80, 60)),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
    await tester.pump();

    return reports.join();
  }

  testWidgets(
    'SGR wheel report is invariant to the view offset on screen',
    (tester) async {
      final plain = await wheelReport(tester, padded: false);
      final padded = await wheelReport(tester, padded: true);

      // The wheel must encode the same cell regardless of where the view
      // sits on the screen, and it must actually be a wheel-up report.
      expect(plain, startsWith('\x1b[<64;'));
      expect(padded, plain);
    },
  );
}
