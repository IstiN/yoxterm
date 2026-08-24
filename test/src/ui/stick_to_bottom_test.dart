import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/src/ui/render.dart';
import 'package:yoxterm/xterm.dart';

/// Regression tests for stick-to-bottom follow: while output streams in, the
/// framework-cached `ScrollPosition.maxScrollExtent` trails the live buffer
/// by at least a frame (RenderTerminal defers its layout to a post-frame
/// callback), so programmatic "scroll to bottom" jumps must target the live
/// extent and near-bottom landings must keep follow engaged.
void main() {
  Future<RenderTerminal> pumpTerminal(
    WidgetTester tester,
    Terminal terminal,
  ) async {
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
            ),
          ),
        ),
      ),
    ));
    return tester
        .state<TerminalViewState>(find.byType(TerminalView))
        .renderTerminal;
  }

  ScrollPosition position(WidgetTester tester) {
    return tester.state<ScrollableState>(find.byType(Scrollable)).position;
  }

  void writeLines(Terminal terminal, int from, int count) {
    for (var i = from; i < from + count; i++) {
      terminal.write('line $i\r\n');
    }
  }

  testWidgets('sticks to the bottom while output streams in', (tester) async {
    final terminal = Terminal();
    final rt = await pumpTerminal(tester, terminal);

    writeLines(terminal, 0, 100);
    await tester.pump();
    await tester.pump();

    final pos = position(tester);
    expect(pos.maxScrollExtent, greaterThan(0));
    expect(pos.pixels, pos.maxScrollExtent);
    expect(rt.maxScrollExtentLive, pos.maxScrollExtent);

    // Follow survives further output.
    writeLines(terminal, 100, 50);
    await tester.pump();
    await tester.pump();
    expect(pos.pixels, pos.maxScrollExtent);
  });

  testWidgets(
    'programmatic scroll-to-bottom targets the live extent mid-stream',
    (tester) async {
      final terminal = Terminal();
      final rt = await pumpTerminal(tester, terminal);

      writeLines(terminal, 0, 100);
      await tester.pump();
      await tester.pump();
      final pos = position(tester);
      expect(pos.pixels, pos.maxScrollExtent);

      // User scrolls up: follow disengages and output no longer moves the
      // viewport.
      pos.jumpTo(0);
      await tester.pump();
      writeLines(terminal, 100, 10);
      await tester.pump();
      await tester.pump();
      expect(pos.pixels, 0);
      final detachedMax = pos.maxScrollExtent;

      // More output arrives without a layout pass: the live extent runs ahead
      // of the framework-cached max.
      writeLines(terminal, 110, 10);
      final liveMax = rt.maxScrollExtentLive;
      expect(liveMax, greaterThan(detachedMax));

      // A key press triggers TerminalView's scroll-to-bottom. It must land on
      // the live extent, beyond the stale cached max.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      expect(pos.pixels, liveMax);

      // Follow re-engages: further output keeps the viewport at the bottom.
      writeLines(terminal, 120, 10);
      await tester.pump();
      await tester.pump();
      expect(pos.pixels, pos.maxScrollExtent);
      expect(pos.pixels, greaterThan(detachedMax));
    },
  );

  testWidgets(
    'landing within half a line of the bottom keeps follow engaged',
    (tester) async {
      final terminal = Terminal();
      final rt = await pumpTerminal(tester, terminal);

      writeLines(terminal, 0, 100);
      await tester.pump();
      await tester.pump();
      final pos = position(tester);

      // A pixel short of the bottom still counts as sticking, so the next
      // layout snaps back and follow survives.
      pos.jumpTo(pos.maxScrollExtent - 1);
      await tester.pump();
      writeLines(terminal, 100, 10);
      await tester.pump();
      await tester.pump();
      expect(pos.pixels, pos.maxScrollExtent);

      // Beyond the half-line tolerance the user has deliberately scrolled
      // away: follow disengages and the viewport stays parked.
      pos.jumpTo(pos.maxScrollExtent - rt.lineHeight);
      await tester.pump();
      final parked = pos.pixels;
      writeLines(terminal, 110, 10);
      await tester.pump();
      await tester.pump();
      expect(pos.pixels, parked);
      expect(pos.pixels, lessThan(pos.maxScrollExtent));
    },
  );
}
