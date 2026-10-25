import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

    testWidgets('moves scroll listeners when the position is replaced', (tester) async {
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

      final renderObject = tester
          .renderObject(find.byKey(const Key('child')))
          .parent! as dynamic;
      final newPosition = _TestViewportOffset(initialPixels: 42);

      expect(newPosition.debugListenerCount, 0);

      renderObject.position = newPosition;

      // The new position receives both the scroll callback listener and
      // markNeedsLayout; the old position is fully detached.
      expect(newPosition.debugListenerCount, 2);

      // Scrolling the old position must no longer reach the render object.
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );
      scrollable.position.jumpTo(10);
      expect(offsets, isEmpty);
    });

    testWidgets('delivers scroll callbacks from the replacement position', (tester) async {
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

      final renderObject = tester
          .renderObject(find.byKey(const Key('child')))
          .parent! as dynamic;
      final newPosition = _TestViewportOffset(initialPixels: 42);
      renderObject.position = newPosition;

      newPosition.debugFireScroll();
      expect(offsets, <double>[42]);

      // Mutating the replaced position must not emit stale callbacks.
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );
      scrollable.position.jumpTo(5);
      expect(offsets, <double>[42]);
    });

    testWidgets('detach after a position swap removes the scroll listener', (tester) async {
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

      final renderObject = tester
          .renderObject(find.byKey(const Key('child')))
          .parent! as dynamic;
      final newPosition = _TestViewportOffset(initialPixels: 42);
      renderObject.position = newPosition;

      // Unmounting the tree detaches the render object; it must release the
      // replacement position's scroll listener without throwing.
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
      // detach() removes the _onScroll listener it owns; the markNeedsLayout
      // listener registered by the position setter while attached is not
      // managed by attach/detach (pre-existing semantics), so one remains.
      expect(newPosition.debugListenerCount, 1);
    });
  });
}

class _TestViewportOffset extends ViewportOffset {
  _TestViewportOffset({double initialPixels = 0}) : _pixels = initialPixels;

  double _pixels;

  int _listenerCount = 0;

  int get debugListenerCount => _listenerCount;

  void debugFireScroll() => notifyListeners();

  @override
  void addListener(VoidCallback listener) {
    _listenerCount++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listenerCount--;
    super.removeListener(listener);
  }

  @override
  double get pixels => _pixels;

  @override
  bool get hasPixels => true;

  @override
  bool applyViewportDimension(double viewportDimension) => true;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) => true;

  @override
  void correctBy(double correction) {
    _pixels += correction;
  }

  @override
  void jumpTo(double pixels) {
    _pixels = pixels;
    notifyListeners();
  }

  @override
  Future<void> animateTo(
    double to, {
    required Duration duration,
    required Curve curve,
  }) async {
    _pixels = to;
    notifyListeners();
  }

  @override
  ScrollDirection get userScrollDirection => ScrollDirection.idle;

  @override
  bool get allowImplicitScrolling => false;
}
