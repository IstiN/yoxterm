import 'dart:typed_data' show Float64List;
import 'dart:ui' show Picture;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ContainerLayer;
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

  testWidgets(
      'repaint at a shifted position translates the frame picture, not bakes '
      'a stale one', (tester) async {
    final terminal = Terminal();
    terminal.write('hello frame picture\nworld');
    final ro = await pumpTerminal(tester, terminal);
    final rebuildsAfterFirstPaint = ro.debugFramePictureRebuilds;

    // Paint manually at two different offsets — the render object's
    // position within its parent changes across board switches without
    // any layout/scroll/terminal change. The replayed static layer must
    // follow the new offset (translate before drawPicture), otherwise it
    // renders at the stale position and the newly exposed region stays
    // blank until a manual resize.
    final first = _CallLogCanvas();
    ro.paint(_MockPaintingContext(first), Offset.zero);

    final second = _CallLogCanvas();
    ro.paint(_MockPaintingContext(second), const Offset(0, 50));

    expect(ro.debugFramePictureRebuilds, rebuildsAfterFirstPaint,
        reason: 'a pure position shift must re-use the recorded picture');
    final translateIndex = second.calls.indexWhere((c) => c.startsWith('translate'));
    final pictureIndex = second.calls.indexWhere((c) => c == 'drawPicture');
    expect(translateIndex, greaterThanOrEqualTo(0),
        reason: 'the replay must be translated to the current offset');
    expect(pictureIndex, greaterThan(translateIndex),
        reason: 'drawPicture must happen after the translation');
  });
}

/// A [PaintingContext] whose canvas is the mock, so direct `ro.paint(...)`
/// calls in tests emit into the call log instead of a real picture layer.
class _MockPaintingContext extends PaintingContext {
  _MockPaintingContext(this.mockCanvas)
      : super(ContainerLayer(), Offset.zero & const Size(4000, 4000));

  final Canvas mockCanvas;

  @override
  Canvas get canvas => mockCanvas;
}

/// Records the sequence of canvas calls by name, for asserting replay order.
class _CallLogCanvas implements Canvas {
  final calls = <String>[];

  @override
  void translate(double dx, double dy) => calls.add('translate($dx,$dy)');

  @override
  void drawPicture(Picture picture) => calls.add('drawPicture');

  @override
  void drawRect(Rect rect, Paint paint) => calls.add('drawRect');

  @override
  void drawRRect(RRect rrect, Paint paint) => calls.add('drawRRect');

  @override
  void save() => calls.add('save');

  @override
  void restore() => calls.add('restore');

  @override
  Float64List getTransform() => Matrix4.identity().storage;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
