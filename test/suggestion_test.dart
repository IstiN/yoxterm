import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/suggestion.dart';

void main() {
  group('SuggestionPortal', () {
    Future<SuggestionPortalController> pumpPortal(
      WidgetTester tester, {
      EdgeInsets padding = const EdgeInsets.all(8),
      EdgeInsets cursorMargin = const EdgeInsets.all(4),
      Size popupSize = const Size(50, 30),
    }) async {
      final controller = SuggestionPortalController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SuggestionPortal(
            controller: controller,
            padding: padding,
            cursorMargin: cursorMargin,
            overlayBuilder: (context) => SizedBox(
              key: const Key('popup'),
              width: popupSize.width,
              height: popupSize.height,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ));

      return controller;
    }

    testWidgets('shows the popup below the cursor when it fits',
        (tester) async {
      final controller = await pumpPortal(tester);

      expect(find.byKey(const Key('popup')), findsNothing);

      controller.update(const Rect.fromLTWH(100, 100, 10, 20));
      await tester.pump();

      expect(find.byKey(const Key('popup')), findsOneWidget);

      final topLeft = tester.getTopLeft(find.byKey(const Key('popup')));
      // x: cursor left (fits within the screen minus padding).
      // y: cursor bottom + bottom margin.
      expect(topLeft, const Offset(100, 124));
    });

    testWidgets('shows the popup above the cursor when there is no space below',
        (tester) async {
      final controller = await pumpPortal(tester);

      // Test surface is 800x600; leave only 8 pixels below the cursor.
      controller.update(const Rect.fromLTWH(100, 564, 10, 20));
      await tester.pump();

      final topLeft = tester.getTopLeft(find.byKey(const Key('popup')));
      // y: cursor top - top margin - popup height.
      expect(topLeft, const Offset(100, 564 - 4 - 30));
    });

    testWidgets('clamps the popup to the screen edge', (tester) async {
      final controller = await pumpPortal(tester);

      // Cursor near the right edge: the popup must not overflow.
      controller.update(const Rect.fromLTWH(780, 100, 10, 20));
      await tester.pump();

      final topLeft = tester.getTopLeft(find.byKey(const Key('popup')));
      // x: width (800) - padding (8) - popup width (50).
      expect(topLeft.dx, 800 - 8 - 50);
    });

    testWidgets('repositions when the cursor moves', (tester) async {
      final controller = await pumpPortal(tester);

      controller.update(const Rect.fromLTWH(100, 100, 10, 20));
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(const Key('popup'))),
        const Offset(100, 124),
      );

      controller.update(const Rect.fromLTWH(200, 200, 10, 20));
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(const Key('popup'))),
        const Offset(200, 224),
      );
    });

    testWidgets('hide removes the popup', (tester) async {
      final controller = await pumpPortal(tester);

      controller.update(const Rect.fromLTWH(100, 100, 10, 20));
      await tester.pump();
      expect(find.byKey(const Key('popup')), findsOneWidget);

      controller.hide();
      await tester.pump();
      expect(find.byKey(const Key('popup')), findsNothing);
    });
  });

  group('RenderCompletionLayout', () {
    test('sizes itself to the smallest constraint without a child', () {
      final layout = RenderCompletionLayout(
        null,
        cursorRect: ValueNotifier(const Rect.fromLTWH(10, 10, 10, 20)),
        padding: const EdgeInsets.all(8),
        cursorMargin: const EdgeInsets.all(4),
      );

      layout.layout(const BoxConstraints.tightFor(width: 300, height: 300));

      expect(layout.size, const Size(300, 300));
    });

    testWidgets('property setters with equal values do not mark needs layout',
        (tester) async {
      final cursorRect = ValueNotifier(const Rect.fromLTWH(100, 100, 10, 20));

      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: SuggestionLayout(
              cursorRect: cursorRect,
              padding: const EdgeInsets.all(8),
              cursorMargin: const EdgeInsets.all(4),
              child: const SizedBox(width: 50, height: 30),
            ),
          ),
        ),
      ));

      final renderObject = tester.renderObject<RenderCompletionLayout>(
        find.byType(SuggestionLayout),
      );

      // Same instances/values are no-ops.
      renderObject.cursorRect = cursorRect;
      renderObject.padding = const EdgeInsets.all(8);
      renderObject.cursorMargin = const EdgeInsets.all(4);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // New values are applied.
      renderObject.padding = const EdgeInsets.all(10);
      renderObject.cursorMargin = const EdgeInsets.all(6);
      expect(renderObject.padding, const EdgeInsets.all(10));
      expect(renderObject.cursorMargin, const EdgeInsets.all(6));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('listens to a swapped cursorRect listenable', (tester) async {
      final cursorRect = ValueNotifier(const Rect.fromLTWH(100, 100, 10, 20));

      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: SuggestionLayout(
              cursorRect: cursorRect,
              padding: const EdgeInsets.all(8),
              cursorMargin: const EdgeInsets.all(4),
              child: const SizedBox(
                key: Key('popup'),
                width: 50,
                height: 30,
              ),
            ),
          ),
        ),
      ));

      final renderObject = tester.renderObject<RenderCompletionLayout>(
        find.byType(SuggestionLayout),
      );

      final newCursorRect =
          ValueNotifier(const Rect.fromLTWH(50, 50, 10, 20));
      renderObject.cursorRect = newCursorRect;
      await tester.pump();

      // Updates on the new listenable trigger a relayout.
      newCursorRect.value = const Rect.fromLTWH(120, 120, 10, 20);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('removes listeners when detached', (tester) async {
      final cursorRect = ValueNotifier(const Rect.fromLTWH(100, 100, 10, 20));
      final show = ValueNotifier(true);

      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (context, value, child) {
            if (!value) return const SizedBox();
            return Center(
              child: SizedBox(
                width: 400,
                height: 400,
                child: SuggestionLayout(
                  cursorRect: cursorRect,
                  padding: const EdgeInsets.all(8),
                  cursorMargin: const EdgeInsets.all(4),
                  child: const SizedBox(width: 50, height: 30),
                ),
              ),
            );
          },
        ),
      ));

      show.value = false;
      await tester.pump();

      // Updating the old listenable must not touch the detached render object.
      cursorRect.value = const Rect.fromLTWH(200, 200, 10, 20);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
