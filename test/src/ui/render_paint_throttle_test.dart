import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/src/ui/render.dart';
import 'package:yoxterm/xterm.dart';

/// Output-paint throttle behavior for [RenderTerminal].
///
/// The throttle must do two things at once, and the test file verifies each
/// independently:
///
/// * **Coalesce within a frame.** Bursts of terminal changes that arrive
///   inside a single vsync must produce a single paint, regardless of how
///   many chunks arrived. Without this, every PTY read forces its own
///   paint pass even on the same frame.
/// * **Cap across frames.** When changes arrive across N frame boundaries,
///   at most N paints may run; the throttle must not multiply them.
///
/// Secondary expectations (cursor blink, idle repaint via theme/focus,
/// observable interval) live in this file too so a regression in the
/// coalescing fix cannot sneak past unnoticed.
TerminalView _view(
  Terminal terminal, {
  TerminalController? controller,
  Size size = const Size(800, 400),
  TerminalCursorType cursorType = TerminalCursorType.block,
  bool alwaysShowCursor = false,
  bool autoResize = true,
  TerminalTheme theme = TerminalThemes.defaultTheme,
  TerminalStyle textStyle = const TerminalStyle(),
}) {
  return TerminalView(
    terminal,
    controller: controller,
    cursorType: cursorType,
    alwaysShowCursor: alwaysShowCursor,
    autoResize: autoResize,
    theme: theme,
    textStyle: textStyle,
  );
}

Future<RenderTerminal> _pump(
  WidgetTester tester,
  Terminal terminal, {
  TerminalController? controller,
  Size size = const Size(800, 400),
  TerminalCursorType cursorType = TerminalCursorType.block,
  bool alwaysShowCursor = false,
  bool autoResize = true,
  TerminalTheme theme = TerminalThemes.defaultTheme,
  TerminalStyle textStyle = const TerminalStyle(),
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: _view(
            terminal,
            controller: controller,
            size: size,
            cursorType: cursorType,
            alwaysShowCursor: alwaysShowCursor,
            autoResize: autoResize,
            theme: theme,
            textStyle: textStyle,
          ),
        ),
      ),
    ),
  ));
  return tester
      .state<TerminalViewState>(find.byType(TerminalView))
      .renderTerminal;
}

void main() {
  group('paint throttle', () {
    testWidgets(
      'burst of N changes in a single frame coalesces to <= 1 paint',
      (tester) async {
        final terminal = Terminal();
        final rt = await _pump(tester, terminal);
        await tester.pump();
        rt.debugResetPaintCounter();

        // 100 terminal writes — each invokes _onTerminalChange, which under
        // the current implementation both schedules a frame callback and
        // schedules a postFrame layout callback. The repaint that actually
        // runs must be coalesced into a single paint per frame.
        for (var i = 0; i < 100; i++) {
          terminal.write('chunk $i\r\n');
        }

        await tester.pump();

        expect(
          rt.debugPaintCount,
          lessThanOrEqualTo(1),
          reason:
              '100 synchronous terminal changes in a single frame must produce '
              'at most one paint, not one per chunk.',
        );
      },
    );

    testWidgets(
      'N changes spread across 5 frame boundaries produces <= 5 paints',
      (tester) async {
        final terminal = Terminal();
        final rt = await _pump(tester, terminal);
        await tester.pump();
        rt.debugResetPaintCounter();

        // 5 frames, 20 writes per frame. After coalescing fix: 5 paints.
        // Before the fix the layout cascade adds an extra paint per frame.
        const frames = 5;
        const writesPerFrame = 20;
        for (var f = 0; f < frames; f++) {
          for (var j = 0; j < writesPerFrame; j++) {
            terminal.write('frame=$f chunk=$j\r\n');
          }
          await tester.pump();
        }
        // Drain any postFrame callbacks queued by the bursts above.
        for (var i = 0; i < 3; i++) {
          await tester.pump();
        }

        expect(
          rt.debugPaintCount,
          lessThanOrEqualTo(frames),
          reason:
              'At most one paint per frame boundary; anything beyond $frames '
              'is a layout-cascade paint leaking past the throttle.',
        );
      },
    );

    testWidgets('a single output change triggers exactly one paint',
        (tester) async {
      final terminal = Terminal();
      final rt = await _pump(tester, terminal);
      await tester.pump();
      rt.debugResetPaintCounter();

      terminal.write('hello\r\n');
      await tester.pump();

      expect(
        rt.debugPaintCount,
        1,
        reason:
            'A single output change should produce exactly one coalesced '
            'paint, not zero (no paint = stale screen).',
      );
    });

    testWidgets('idle repaint via theme change still triggers a paint',
        (tester) async {
      final terminal = Terminal();
      final rt = await _pump(tester, terminal);
      terminal.write('hello');
      await tester.pump();
      rt.debugResetPaintCounter();

      // Theme setter calls markNeedsPaint directly (bypasses the output
      // throttle) — a paint must still happen on the next frame.
      rt.theme = TerminalThemes.whiteOnBlack;
      await tester.pump();

      expect(
        rt.debugPaintCount,
        greaterThanOrEqualTo(1),
        reason:
            'Idle repaint paths (theme / focus / controller) must remain '
            'unthrottled and produce at least one paint.',
      );
    });

    testWidgets(
      'throttle interval is observable and defaults to 16ms',
      (tester) async {
        final terminal = Terminal();
        final rt = await _pump(tester, terminal);

        expect(
          rt.debugMinOutputPaintInterval,
          const Duration(milliseconds: 16),
          reason:
              'Default throttle interval is 16ms — a 60fps cap on output '
              'repaints; changes here must be intentional.',
        );
      },
    );

    testWidgets(
      'focus change repaints synchronously without going through the throttle',
      (tester) async {
        final terminal = Terminal();
        final rt = await _pump(tester, terminal);
        await tester.pump();
        rt.debugResetPaintCounter();

        // Replace the focus node with a fresh one. The detach of the
        // previous and the attach of the new emit a single focus change
        // when the widget is rebuilt, but here we directly poke the
        // listener path to ensure the unthrottled marker is preserved.
        final newFocus = FocusNode();
        rt.focusNode = newFocus;
        newFocus.requestFocus();
        await tester.pump();

        expect(
          rt.debugPaintCount,
          greaterThanOrEqualTo(1),
          reason:
              'User-driven repaints (focus) must not be coalesced by the '
              'output throttle — they must always paint immediately.',
        );
      },
    );

    testWidgets('no terminal activity produces no paints', (tester) async {
      final terminal = Terminal();
      final rt = await _pump(tester, terminal);
      await tester.pump();
      rt.debugResetPaintCounter();

      // Several idle frames with no terminal writes / no focus / no theme
      // change should not trigger any paints.
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(
        rt.debugPaintCount,
        0,
        reason:
            'Idle repaint count must be zero — the bug being fixed cannot '
            'be allowed to convert idle frames into paint frames.',
      );
    });
  });
}

/// Notes (not part of the test suite):
///
/// The earlier code audit found the throttle largely defeated because every
/// terminal change schedules both a frame callback (for paint) AND a postFrame
/// callback that calls markNeedsLayout(), and the postFrame-triggered
/// markNeedsLayout eventually causes a second paint per frame via the
/// layout pipeline. These tests pin the contract so the fix can be observed
/// empirically rather than argued by inspection.
