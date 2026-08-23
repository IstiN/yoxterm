import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('KeyboardVisibilty', () {
    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: KeyboardVisibilty(
            child: Text('child'),
          ),
        ),
      );

      expect(find.text('child'), findsOneWidget);
    });

    testWidgets('calls onKeyboardShow when viewInsets appear', (tester) async {
      var shows = 0;
      var hides = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: KeyboardVisibilty(
            onKeyboardShow: () => shows++,
            onKeyboardHide: () => hides++,
            child: const Text('child'),
          ),
        ),
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();

      expect(shows, 1);
      expect(hides, 0);

      tester.view.resetViewInsets();
    });

    testWidgets('calls onKeyboardHide when viewInsets disappear', (tester) async {
      var shows = 0;
      var hides = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: KeyboardVisibilty(
            onKeyboardShow: () => shows++,
            onKeyboardHide: () => hides++,
            child: const Text('child'),
          ),
        ),
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();

      expect(shows, 1);
      expect(hides, 1);

      tester.view.resetViewInsets();
    });

    testWidgets('does not fire again when the inset is unchanged', (tester) async {
      var shows = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: KeyboardVisibilty(
            onKeyboardShow: () => shows++,
            child: const Text('child'),
          ),
        ),
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      expect(shows, 1);

      // Same inset again (e.g. an unrelated metrics change): no extra events.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      expect(shows, 1);

      tester.view.resetViewInsets();
    });

    testWidgets('works without callbacks', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: KeyboardVisibilty(
            child: Text('child'),
          ),
        ),
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();

      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
    });
  });
}
