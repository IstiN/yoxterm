import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('TerminalView.onKeyEvent', () {
    testWidgets('overrides input handling when it returns handled',
        (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            autofocus: true,
            onKeyEvent: (node, event) => KeyEventResult.handled,
          ),
        ),
      ));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      expect(output, isEmpty);
    });

    testWidgets('falls through to default handling when ignored',
        (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            autofocus: true,
            onKeyEvent: (node, event) => KeyEventResult.ignored,
          ),
        ),
      ));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(output.join(), '\r');
    });
  });

  group('TerminalView.shortcuts', () {
    testWidgets('custom shortcuts override the defaults', (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      var invocations = 0;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            autofocus: true,
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyB, control: true):
                  _TestIntent(),
            },
          ),
        ),
      ));

      // Register the action for the custom intent above the terminal.
      // (Shortcut handling only routes the intent; without a matching action
      // the key is still consumed by the shortcut manager.)
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Actions(
            actions: {
              _TestIntent: CallbackAction<_TestIntent>(
                onInvoke: (intent) {
                  invocations++;
                  return null;
                },
              ),
            },
            child: TerminalView(
              terminal,
              autofocus: true,
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.keyB, control: true):
                    _TestIntent(),
              },
            ),
          ),
        ),
      ));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      expect(invocations, 1);
      expect(output, isEmpty);
    });
  });

  group('TerminalView.deleteDetection', () {
    testWidgets('sends backspace when the IME shrinks the text',
        (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            autofocus: true,
            deleteDetection: true,
          ),
        ),
      ));

      await tester.tap(find.byType(TerminalView));
      await tester.pump(const Duration(seconds: 1));

      // Initial editing state is two spaces; the IME removing one means the
      // user pressed delete.
      binding.testTextInput.updateEditingValue(const TextEditingValue(
        text: ' ',
        selection: TextSelection.collapsed(offset: 1),
      ));
      await binding.idle();

      expect(output.join(), contains('\x7f'));

      // Flush the internal double tap timer.
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    });
  });

  group('TerminalView.state', () {
    testWidgets('requestKeyboard and closeKeyboard toggle the input connection',
        (tester) async {
      final terminal = Terminal();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal),
        ),
      ));

      final state = tester.state<TerminalViewState>(find.byType(TerminalView));

      expect(state.hasInputConnection, isFalse);

      state.requestKeyboard();
      await tester.pump();

      expect(state.hasInputConnection, isTrue);

      state.closeKeyboard();
      await tester.pump();

      expect(state.hasInputConnection, isFalse);
    });

    testWidgets('cursorRect and globalCursorRect are valid', (tester) async {
      final terminal = Terminal();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal),
        ),
      ));

      final state = tester.state<TerminalViewState>(find.byType(TerminalView));

      expect(state.cursorRect.width, greaterThan(0));
      expect(state.cursorRect.height, greaterThan(0));
      expect(state.globalCursorRect.width, state.cursorRect.width);
    });
  });

  group('TerminalView.didUpdateWidget', () {
    testWidgets('keeps external controllers alive when they are swapped',
        (tester) async {
      final terminal = Terminal();
      final controller1 = TerminalController();
      final controller2 = TerminalController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal, controller: controller1),
        ),
      ));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal, controller: controller2),
        ),
      ));

      // External controllers are not disposed by the widget.
      expect(
        () => controller1.addListener(() {}),
        returnsNormally,
      );

      // Removing the controller creates a new internal one.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal),
        ),
      ));

      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps external focus nodes alive when they are swapped',
        (tester) async {
      final terminal = Terminal();
      final focusNode1 = FocusNode();
      final focusNode2 = FocusNode();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal, focusNode: focusNode1),
        ),
      ));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal, focusNode: focusNode2),
        ),
      ));

      expect(() => focusNode1.addListener(() {}), returnsNormally);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps external scroll controllers alive when swapped',
        (tester) async {
      final terminal = Terminal();
      final scrollController1 = ScrollController();
      final scrollController2 = ScrollController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal, scrollController: scrollController1),
        ),
      ));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal, scrollController: scrollController2),
        ),
      ));

      expect(
        () => scrollController1.addListener(() {}),
        returnsNormally,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('TerminalView.readOnly + hardwareKeyboardOnly', () {
    testWidgets('ignores all keyboard input', (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            autofocus: true,
            readOnly: true,
            hardwareKeyboardOnly: true,
          ),
        ),
      ));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      expect(output, isEmpty);
    });
  });

  group('TerminalView.decoration', () {
    testWidgets('applies backgroundOpacity and padding', (tester) async {
      final terminal = Terminal();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            backgroundOpacity: 0.5,
            padding: const EdgeInsets.all(10),
          ),
        ),
      ));

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(TerminalView),
              matching: find.byType(Container),
            )
            .first,
      );

      expect(container.padding, const EdgeInsets.all(10));
      expect(container.color!.a, closeTo(0.5, 0.01));
    });
  });
}

class _TestIntent extends Intent {
  const _TestIntent();
}
