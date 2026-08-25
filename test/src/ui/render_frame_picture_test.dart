import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/src/ui/render.dart';
import 'package:yoxterm/xterm.dart';

/// Two-phase paint (ghostty beginUpdate/endUpdate port): the static text
/// layer of the viewport is cached in a single ui.Picture and replayed with
/// one drawPicture call; only the dynamic overlay (cursor, selection,
/// highlights, composing) is re-drawn per repaint.
void main() {
  Future<RenderTerminal> pumpTerminal(
    WidgetTester tester,
    Terminal terminal, {
    TerminalController? controller,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            height: 400,
            child: TerminalView(
              terminal,
              controller: controller,
              autoResize: false,
              textStyle: const TerminalStyle(fontSize: 13),
            ),
          ),
        ),
      ),
    ));
    return tester
        .state<TerminalViewState>(find.byType(TerminalView))
        .renderTerminal;
  }

  testWidgets('first paint builds the frame picture once', (tester) async {
    final terminal = Terminal();
    terminal.write('hello frame picture\nworld');
    final ro = await pumpTerminal(tester, terminal);

    expect(ro.debugFramePictureRebuilds, 1,
        reason: 'the initial paint must record the static layer once');
    expect(ro.debugFramePictureHits, 0);
  });

  testWidgets('idle repaint replays the frame picture without rebuilding',
      (tester) async {
    final terminal = Terminal();
    terminal.write('hello frame picture\nworld');
    final ro = await pumpTerminal(tester, terminal);
    final rebuildsAfterFirstPaint = ro.debugFramePictureRebuilds;

    // A repaint with no buffer change (the cursor-blink / overlay case):
    // the static layer must be replayed with a single drawPicture, not
    // re-recorded.
    ro.markNeedsPaint();
    await tester.pump();

    expect(ro.debugFramePictureRebuilds, rebuildsAfterFirstPaint,
        reason: 'no line changed, so the frame picture must stay valid');
    expect(ro.debugFramePictureHits, 1);
  });

  testWidgets('a buffer change rebuilds the frame picture exactly once',
      (tester) async {
    final terminal = Terminal();
    terminal.write('hello frame picture\nworld');
    final ro = await pumpTerminal(tester, terminal);
    final rebuildsAfterFirstPaint = ro.debugFramePictureRebuilds;

    terminal.write('!');
    await tester.pump();
    expect(ro.debugFramePictureRebuilds, rebuildsAfterFirstPaint + 1,
        reason: 'one changed line re-records the static layer once');

    // And the next idle repaint is a hit again.
    ro.markNeedsPaint();
    await tester.pump();
    expect(ro.debugFramePictureHits, 1);
    expect(ro.debugFramePictureRebuilds, rebuildsAfterFirstPaint + 1);
  });

  testWidgets('a scroll offset change invalidates the frame picture',
      (tester) async {
    final terminal = Terminal();
    // Enough lines to scroll.
    for (var i = 0; i < 60; i++) {
      terminal.write('line $i\r\n');
    }
    final ro = await pumpTerminal(tester, terminal);
    final rebuildsAfterFirstPaint = ro.debugFramePictureRebuilds;

    final pos = tester.state<ScrollableState>(find.byType(Scrollable))
        .position;
    pos.jumpTo(32);
    await tester.pump();
    await tester.pump();
    expect(ro.debugFramePictureRebuilds, greaterThan(rebuildsAfterFirstPaint),
        reason: 'a different scroll offset must re-record the static layer');
  });

  testWidgets('selection repaint keeps the frame picture valid',
      (tester) async {
    final terminal = Terminal();
    terminal.write('hello frame picture\nworld');
    final controller = TerminalController();
    final ro = await pumpTerminal(tester, terminal, controller: controller);
    final rebuildsAfterFirstPaint = ro.debugFramePictureRebuilds;

    // Selecting is a pure overlay change: the text layer must not be
    // re-recorded.
    controller.setSelection(
      terminal.buffer.createAnchorFromOffset(const CellOffset(0, 0)),
      terminal.buffer.createAnchorFromOffset(const CellOffset(5, 0)),
    );
    await tester.pump();

    expect(ro.debugFramePictureRebuilds, rebuildsAfterFirstPaint,
        reason: 'selection is overlay-only and must not invalidate the text');
    expect(ro.debugFramePictureHits, 1);
  });
}
