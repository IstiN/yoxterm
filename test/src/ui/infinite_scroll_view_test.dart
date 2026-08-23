import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/src/ui/infinite_scroll_view.dart';

void main() {
  group('InfiniteScrollView', () {
    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: InfiniteScrollView(
                onScroll: (_) {},
                child: Container(
                  key: const Key('child'),
                  width: 200,
                  height: 200,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('child')), findsOneWidget);
    });

    testWidgets('reports scroll offsets via onScroll', (tester) async {
      final offsets = <double>[];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: InfiniteScrollView(
                onScroll: offsets.add,
                child: Container(
                  width: 200,
                  height: 200,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ),
      );

      expect(offsets, isEmpty);

      await tester.drag(
        find.byType(InfiniteScrollView),
        const Offset(0, -50),
      );
      await tester.pump();

      expect(offsets, isNotEmpty);
      // Dragging up produces positive offsets.
      expect(offsets.last, greaterThan(0));
    });

    testWidgets('supports scrolling in both directions', (tester) async {
      final offsets = <double>[];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: InfiniteScrollView(
                onScroll: offsets.add,
                child: Container(
                  width: 200,
                  height: 200,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.drag(
        find.byType(InfiniteScrollView),
        const Offset(0, -50),
      );
      await tester.pump();
      final afterUp = offsets.last;
      expect(afterUp, greaterThan(0));

      await tester.drag(
        find.byType(InfiniteScrollView),
        const Offset(0, 20),
      );
      await tester.pump();
      final afterDown = offsets.last;
      expect(afterDown, lessThan(afterUp));
    });
  });
}
