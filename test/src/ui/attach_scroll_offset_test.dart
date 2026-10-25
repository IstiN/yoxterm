import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/src/ui/render.dart';
import 'package:yoxterm/xterm.dart';

/// Regression tests for the attach-time scroll position: hosts that restore
/// a persisted scroll offset into the scroll controller (board/panel
/// remounts) must have that offset honored on the very first frame, while
/// the default behavior (follow output from attach) is unchanged.
void main() {
  Future<void> unmount(WidgetTester tester) async {
    // Real remounts (board/panel switches) fully unmount the subtree;
    // pumpWidget with an identical tree shape would silently reuse the
    // TerminalView state and its scroll position instead.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  Future<ScrollPosition> pumpTerminal(
    WidgetTester tester,
    Terminal terminal, {
    required ScrollController scrollController,
    bool snapToBottomOnAttach = true,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            height: 200,
            child: TerminalView(
              terminal,
              autofocus: true,
              hardwareKeyboardOnly: true,
              scrollController: scrollController,
              snapToBottomOnAttach: snapToBottomOnAttach,
            ),
          ),
        ),
      ),
    ));
    return tester.state<ScrollableState>(find.byType(Scrollable)).position;
  }

  Terminal terminalWithScrollback(int lines) {
    final terminal = Terminal();
    for (var i = 0; i < lines; i++) {
      terminal.write('line $i\r\n');
    }
    return terminal;
  }

  testWidgets(
    'default attach still snaps to the bottom and follows output',
    (tester) async {
      final terminal = terminalWithScrollback(100);
      final pos = await pumpTerminal(
        tester,
        terminal,
        scrollController: ScrollController(),
      );

      expect(pos.pixels, pos.maxScrollExtent);
      expect(pos.maxScrollExtent, greaterThan(0));

      for (var i = 100; i < 150; i++) {
        terminal.write('line $i\r\n');
      }
      await tester.pump();
      await tester.pump();
      expect(pos.pixels, pos.maxScrollExtent);
    },
  );

  testWidgets(
    'snapToBottomOnAttach=false honors the initial offset at the top',
    (tester) async {
      final terminal = terminalWithScrollback(100);
      final pos = await pumpTerminal(
        tester,
        terminal,
        scrollController: ScrollController(initialScrollOffset: 0),
        snapToBottomOnAttach: false,
      );

      expect(pos.maxScrollExtent, greaterThan(0));
      expect(pos.pixels, 0);

      // Follow mode is disengaged: streaming output must not move the
      // restored viewport.
      for (var i = 100; i < 150; i++) {
        terminal.write('line $i\r\n');
      }
      await tester.pump();
      await tester.pump();
      expect(pos.pixels, 0);
    },
  );

  testWidgets(
    'snapToBottomOnAttach=false seeds follow mode when the restored '
    'offset is at the bottom',
    (tester) async {
      final terminal = terminalWithScrollback(100);
      // First attach with default snap to learn the live extent.
      final first = await pumpTerminal(
        tester,
        terminal,
        scrollController: ScrollController(),
      );
      final maxExtent = first.maxScrollExtent;
      expect(first.pixels, maxExtent);

      // Remount-like second attach: restored offset sits at the bottom, so
      // follow mode must re-engage and keep the viewport at the live bottom.
      await unmount(tester);
      final second = await pumpTerminal(
        tester,
        terminal,
        scrollController: ScrollController(initialScrollOffset: maxExtent),
        snapToBottomOnAttach: false,
      );
      expect(second.pixels, maxExtent);

      for (var i = 100; i < 150; i++) {
        terminal.write('line $i\r\n');
      }
      await tester.pump();
      await tester.pump();
      expect(second.pixels, second.maxScrollExtent);
      expect(second.pixels, greaterThan(maxExtent));
    },
  );

  testWidgets(
    'snapToBottomOnAttach=false restores a mid-scrollback offset '
    'without a bottom flash',
    (tester) async {
      final terminal = terminalWithScrollback(100);
      final first = await pumpTerminal(
        tester,
        terminal,
        scrollController: ScrollController(),
      );
      final mid = first.maxScrollExtent / 2;

      await unmount(tester);
      final second = await pumpTerminal(
        tester,
        terminal,
        scrollController: ScrollController(initialScrollOffset: mid),
        snapToBottomOnAttach: false,
      );
      // Correct after the very first pump — no intermediate bottom frame
      // that a post-frame restore would produce.
      expect(second.pixels, mid);
    },
  );
}
