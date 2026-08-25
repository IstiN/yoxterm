import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/core.dart';
import 'package:yoxterm/src/ui/infinite_scroll_view.dart';
import 'package:yoxterm/src/ui/scroll_handler.dart';

void main() {
  Widget buildHandler({
    required Terminal terminal,
    bool simulateScroll = true,
  }) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 200,
          height: 200,
          child: TerminalScrollGestureHandler(
            terminal: terminal,
            simulateScroll: simulateScroll,
            getCellOffset: (offset) => CellOffset(0, 0),
            getLineHeight: () => 20,
            child: Container(
              width: 200,
              height: 200,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  group('TerminalScrollGestureHandler', () {
    testWidgets('renders the child directly in the main buffer', (tester) async {
      final terminal = Terminal();

      await tester.pumpWidget(buildHandler(terminal: terminal));

      expect(find.byType(InfiniteScrollView), findsNothing);
    });

    testWidgets('wraps the child in an InfiniteScrollView in the alt buffer',
        (tester) async {
      final terminal = Terminal();
      terminal.useAltBuffer();

      await tester.pumpWidget(buildHandler(terminal: terminal));

      expect(find.byType(InfiniteScrollView), findsOneWidget);
    });

    testWidgets('reacts when the terminal switches to the alt buffer',
        (tester) async {
      final terminal = Terminal();

      await tester.pumpWidget(buildHandler(terminal: terminal));
      expect(find.byType(InfiniteScrollView), findsNothing);

      terminal.write('\x1b[?47h');
      await tester.pump();
      expect(find.byType(InfiniteScrollView), findsOneWidget);

      terminal.write('\x1b[?47l');
      await tester.pump();
      expect(find.byType(InfiniteScrollView), findsNothing);
    });

    testWidgets('simulates scroll by sending arrow keys in the alt buffer',
        (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.useAltBuffer();

      await tester.pumpWidget(buildHandler(terminal: terminal));

      await tester.drag(
        find.byType(TerminalScrollGestureHandler),
        const Offset(0, -100),
      );
      await tester.pump();

      expect(output.join(), contains('\x1B[B'));
    });

    testWidgets(
        'scroll survives a scrollable re-attach without emitting an '
        'inverted burst', (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.useAltBuffer();

      await tester.pumpWidget(buildHandler(terminal: terminal));

      // Scroll down 100px (5 arrow-down events).
      await tester.drag(
        find.byType(TerminalScrollGestureHandler),
        const Offset(0, -100),
      );
      await tester.pump();
      output.clear();

      // Leave and re-enter the alt buffer: the InfiniteScrollView is
      // disposed and rebuilt, so its ScrollPosition restarts at pixels = 0.
      // The stale lastLineOffset must NOT turn the next physical scroll
      // into an inverted burst (or swallow it entirely).
      terminal.write('\x1b[?47l');
      await tester.pump();
      terminal.write('\x1b[?47h');
      await tester.pump();

      // A fresh downward drag must still send exactly downward events.
      await tester.drag(
        find.byType(TerminalScrollGestureHandler),
        const Offset(0, -60),
      );
      await tester.pump();

      final arrowsDown = '\x1B[B'.allMatches(output.join()).length;
      final arrowsUp = '\x1B[A'.allMatches(output.join()).length;
      expect(arrowsDown, 3,
          reason: '60px at 20px/line = 3 arrow-down events');
      expect(arrowsUp, 0,
          reason: 'no inverted burst may be emitted after a re-attach');
    });

    testWidgets('dragging down simulates arrow up keys', (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.useAltBuffer();

      await tester.pumpWidget(buildHandler(terminal: terminal));

      await tester.drag(
        find.byType(TerminalScrollGestureHandler),
        const Offset(0, 100),
      );
      await tester.pump();

      expect(output.join(), contains('\x1B[A'));
    });

    testWidgets('does nothing when simulateScroll is disabled', (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.useAltBuffer();

      await tester.pumpWidget(
        buildHandler(terminal: terminal, simulateScroll: false),
      );

      await tester.drag(
        find.byType(TerminalScrollGestureHandler),
        const Offset(0, -100),
      );
      await tester.pump();

      expect(output, isEmpty);
    });

    testWidgets('sends mouse wheel events when the app supports them',
        (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.write('\x1b[?1000h\x1b[?1006h');
      terminal.useAltBuffer();

      await tester.pumpWidget(
        buildHandler(terminal: terminal, simulateScroll: false),
      );

      await tester.drag(
        find.byType(TerminalScrollGestureHandler),
        const Offset(0, -100),
      );
      await tester.pump();

      // SGR-encoded wheel down events, no simulated arrow keys.
      expect(output.join(), contains('\x1b[<65;'));
      expect(output.join(), isNot(contains('\x1B[B')));
    });

    testWidgets('does not intercept scrolling in the main buffer',
        (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      await tester.pumpWidget(buildHandler(terminal: terminal));

      await tester.drag(
        find.byType(TerminalScrollGestureHandler),
        const Offset(0, -100),
      );
      await tester.pump();

      expect(output, isEmpty);
    });

    testWidgets('switches to a new terminal when the widget updates',
        (tester) async {
      final terminalA = Terminal();
      final terminalB = Terminal();
      terminalB.useAltBuffer();

      await tester.pumpWidget(buildHandler(terminal: terminalA));
      expect(find.byType(InfiniteScrollView), findsNothing);

      await tester.pumpWidget(buildHandler(terminal: terminalB));
      expect(find.byType(InfiniteScrollView), findsOneWidget);
    });

    testWidgets('stops listening to the old terminal after an update',
        (tester) async {
      final terminalA = Terminal();
      final terminalB = Terminal();

      await tester.pumpWidget(buildHandler(terminal: terminalA));
      await tester.pumpWidget(buildHandler(terminal: terminalB));

      // Mutating the old terminal must not rebuild or throw.
      terminalA.useAltBuffer();
      await tester.pump();

      expect(find.byType(InfiniteScrollView), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
