import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/gesture/gesture_detector.dart';

void main() {
  Widget buildDetector({
    GestureTapDownCallback? onTapDown,
    GestureTapUpCallback? onSingleTapUp,
    GestureTapDownCallback? onDoubleTapDown,
    GestureTapDownCallback? onSecondaryTapDown,
    GestureTapUpCallback? onSecondaryTapUp,
    GestureTapDownCallback? onTertiaryTapDown,
    GestureTapUpCallback? onTertiaryTapUp,
    GestureLongPressStartCallback? onLongPressStart,
    GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate,
    GestureLongPressUpCallback? onLongPressUp,
    GestureDragStartCallback? onDragStart,
    GestureDragUpdateCallback? onDragUpdate,
  }) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 400,
          height: 400,
          child: TerminalGestureDetector(
            onTapDown: onTapDown,
            onSingleTapUp: onSingleTapUp,
            onDoubleTapDown: onDoubleTapDown,
            onSecondaryTapDown: onSecondaryTapDown,
            onSecondaryTapUp: onSecondaryTapUp,
            onTertiaryTapDown: onTertiaryTapDown,
            onTertiaryTapUp: onTertiaryTapUp,
            onLongPressStart: onLongPressStart,
            onLongPressMoveUpdate: onLongPressMoveUpdate,
            onLongPressUp: onLongPressUp,
            onDragStart: onDragStart,
            onDragUpdate: onDragUpdate,
            child: Container(color: Colors.black),
          ),
        ),
      ),
    );
  }

  group('TerminalGestureDetector.tap', () {
    testWidgets('single tap fires onTapDown and onSingleTapUp', (tester) async {
      var downs = 0;
      var singleUps = 0;

      await tester.pumpWidget(buildDetector(
        onTapDown: (_) => downs++,
        onSingleTapUp: (_) => singleUps++,
      ));

      await tester.tap(find.byType(TerminalGestureDetector));

      expect(downs, 1);
      expect(singleUps, 1);

      // Flush the internal double tap timer.
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    });

    testWidgets('double tap fires onDoubleTapDown and suppresses the second '
        'single tap', (tester) async {
      var downs = 0;
      var singleUps = 0;
      var doubleDowns = 0;

      await tester.pumpWidget(buildDetector(
        onTapDown: (_) => downs++,
        onSingleTapUp: (_) => singleUps++,
        onDoubleTapDown: (_) => doubleDowns++,
      ));

      await tester.tap(find.byType(TerminalGestureDetector));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(TerminalGestureDetector));

      expect(downs, 2);
      expect(doubleDowns, 1);
      expect(singleUps, 1);

      // Flush the internal double tap timer.
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    });

    testWidgets('two distant taps are two single taps', (tester) async {
      var singleUps = 0;
      var doubleDowns = 0;

      await tester.pumpWidget(buildDetector(
        onSingleTapUp: (_) => singleUps++,
        onDoubleTapDown: (_) => doubleDowns++,
      ));

      final origin = tester.getTopLeft(find.byType(TerminalGestureDetector));

      await tester.tapAt(origin + const Offset(50, 50));
      await tester.pump(const Duration(milliseconds: 50));
      // Further away than kDoubleTapSlop.
      await tester.tapAt(origin + const Offset(50 + kDoubleTapSlop + 50, 50));

      expect(singleUps, 2);
      expect(doubleDowns, 0);

      // Flush the internal double tap timer.
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    });

    testWidgets('a tap after the double tap timeout is a new single tap',
        (tester) async {
      var singleUps = 0;
      var doubleDowns = 0;

      await tester.pumpWidget(buildDetector(
        onSingleTapUp: (_) => singleUps++,
        onDoubleTapDown: (_) => doubleDowns++,
      ));

      await tester.tap(find.byType(TerminalGestureDetector));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.tap(find.byType(TerminalGestureDetector));

      expect(singleUps, 2);
      expect(doubleDowns, 0);

      // Flush the internal double tap timer.
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    });
  });

  group('TerminalGestureDetector.secondaryAndTertiary', () {
    testWidgets('secondary tap fires secondary callbacks', (tester) async {
      var secondaryDowns = 0;
      var secondaryUps = 0;

      await tester.pumpWidget(buildDetector(
        onSecondaryTapDown: (_) => secondaryDowns++,
        onSecondaryTapUp: (_) => secondaryUps++,
      ));

      await tester.tap(
        find.byType(TerminalGestureDetector),
        buttons: kSecondaryButton,
      );

      expect(secondaryDowns, 1);
      expect(secondaryUps, 1);
    });

    testWidgets('tertiary tap fires tertiary callbacks', (tester) async {
      var tertiaryDowns = 0;
      var tertiaryUps = 0;

      await tester.pumpWidget(buildDetector(
        onTertiaryTapDown: (_) => tertiaryDowns++,
        onTertiaryTapUp: (_) => tertiaryUps++,
      ));

      await tester.tap(
        find.byType(TerminalGestureDetector),
        buttons: kTertiaryButton,
      );

      expect(tertiaryDowns, 1);
      expect(tertiaryUps, 1);
    });
  });

  group('TerminalGestureDetector.longPress', () {
    testWidgets('long press fires start and up callbacks', (tester) async {
      var starts = 0;
      var ups = 0;

      await tester.pumpWidget(buildDetector(
        onLongPressStart: (_) => starts++,
        onLongPressUp: () => ups++,
      ));

      await tester.longPress(find.byType(TerminalGestureDetector));

      expect(starts, 1);
      expect(ups, 1);
    });

    testWidgets('moving during a long press fires move updates',
        (tester) async {
      var starts = 0;
      var moves = 0;

      await tester.pumpWidget(buildDetector(
        onLongPressStart: (_) => starts++,
        onLongPressMoveUpdate: (_) => moves++,
      ));

      final center = tester.getCenter(find.byType(TerminalGestureDetector));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

      expect(starts, 1);

      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();

      expect(moves, greaterThan(0));

      await gesture.up();
    });
  });

  group('TerminalGestureDetector.drag', () {
    testWidgets('mouse drag fires drag start and update callbacks',
        (tester) async {
      DragStartDetails? startDetails;
      final updates = <DragUpdateDetails>[];

      await tester.pumpWidget(buildDetector(
        onDragStart: (details) => startDetails = details,
        onDragUpdate: updates.add,
      ));

      final center = tester.getCenter(find.byType(TerminalGestureDetector));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();

      expect(startDetails, isNotNull);
      expect(startDetails!.kind, PointerDeviceKind.mouse);
      expect(updates, isNotEmpty);

      await gesture.up();
    });
  });
}
