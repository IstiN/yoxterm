import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/custom_text_edit.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(CustomTextEdit edit) {
    return MaterialApp(
      home: Scaffold(
        body: edit,
      ),
    );
  }

  group('CustomTextEdit.inputConnection', () {
    testWidgets('opens when autofocused', (tester) async {
      final key = GlobalKey<CustomTextEditState>();

      await tester.pumpWidget(wrap(CustomTextEdit(
        key: key,
        focusNode: FocusNode(),
        autofocus: true,
        onInsert: (_) {},
        onDelete: () {},
        onComposing: (_) {},
        onAction: (_) {},
        onKeyEvent: (_, __) => KeyEventResult.ignored,
        child: const SizedBox(width: 100, height: 100),
      )));

      expect(key.currentState!.hasInputConnection, isTrue);
    });

    testWidgets('does not open without focus', (tester) async {
      final key = GlobalKey<CustomTextEditState>();

      await tester.pumpWidget(wrap(CustomTextEdit(
        key: key,
        focusNode: FocusNode(),
        onInsert: (_) {},
        onDelete: () {},
        onComposing: (_) {},
        onAction: (_) {},
        onKeyEvent: (_, __) => KeyEventResult.ignored,
        child: const SizedBox(width: 100, height: 100),
      )));

      expect(key.currentState!.hasInputConnection, isFalse);
    });

    testWidgets('requestKeyboard focuses and opens the connection',
        (tester) async {
      final key = GlobalKey<CustomTextEditState>();
      final focusNode = FocusNode();

      await tester.pumpWidget(wrap(CustomTextEdit(
        key: key,
        focusNode: focusNode,
        onInsert: (_) {},
        onDelete: () {},
        onComposing: (_) {},
        onAction: (_) {},
        onKeyEvent: (_, __) => KeyEventResult.ignored,
        child: const SizedBox(width: 100, height: 100),
      )));

      expect(focusNode.hasFocus, isFalse);

      key.currentState!.requestKeyboard();
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);
      expect(key.currentState!.hasInputConnection, isTrue);
    });

    testWidgets('closeKeyboard closes the connection', (tester) async {
      final key = GlobalKey<CustomTextEditState>();

      await tester.pumpWidget(wrap(CustomTextEdit(
        key: key,
        focusNode: FocusNode(),
        autofocus: true,
        onInsert: (_) {},
        onDelete: () {},
        onComposing: (_) {},
        onAction: (_) {},
        onKeyEvent: (_, __) => KeyEventResult.ignored,
        child: const SizedBox(width: 100, height: 100),
      )));

      expect(key.currentState!.hasInputConnection, isTrue);

      key.currentState!.closeKeyboard();
      await tester.pump();

      expect(key.currentState!.hasInputConnection, isFalse);
    });

    testWidgets('closes the connection when focus is lost', (tester) async {
      final key = GlobalKey<CustomTextEditState>();
      final focusNode = FocusNode();
      final otherNode = FocusNode();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CustomTextEdit(
                key: key,
                focusNode: focusNode,
                autofocus: true,
                onInsert: (_) {},
                onDelete: () {},
                onComposing: (_) {},
                onAction: (_) {},
                onKeyEvent: (_, __) => KeyEventResult.ignored,
                child: const SizedBox(width: 100, height: 100),
              ),
              Focus(focusNode: otherNode, child: const SizedBox()),
            ],
          ),
        ),
      ));

      expect(key.currentState!.hasInputConnection, isTrue);

      otherNode.requestFocus();
      await tester.pump();

      expect(key.currentState!.hasInputConnection, isFalse);
    });

    testWidgets('does not open a connection in readOnly mode', (tester) async {
      final key = GlobalKey<CustomTextEditState>();
      final focusNode = FocusNode();

      await tester.pumpWidget(wrap(CustomTextEdit(
        key: key,
        focusNode: focusNode,
        autofocus: true,
        readOnly: true,
        onInsert: (_) {},
        onDelete: () {},
        onComposing: (_) {},
        onAction: (_) {},
        onKeyEvent: (_, __) => KeyEventResult.ignored,
        child: const SizedBox(width: 100, height: 100),
      )));

      expect(focusNode.hasFocus, isTrue);
      expect(key.currentState!.hasInputConnection, isFalse);

      // Even explicit requests must not open a connection.
      key.currentState!.requestKeyboard();
      await tester.pump();

      expect(key.currentState!.hasInputConnection, isFalse);
    });
  });

  group('CustomTextEdit.textInput', () {
    testWidgets('forwards inserted text to onInsert', (tester) async {
      final inserted = <String>[];

      await tester.pumpWidget(wrap(CustomTextEdit(
        focusNode: FocusNode(),
        autofocus: true,
        onInsert: inserted.add,
        onDelete: () {},
        onComposing: (_) {},
        onAction: (_) {},
        onKeyEvent: (_, __) => KeyEventResult.ignored,
        child: const SizedBox(width: 100, height: 100),
      )));

      binding.testTextInput.enterText('ls -al');
      await binding.idle();

      expect(inserted, ['ls -al']);
    });

    testWidgets('forwards deletions to onDelete with deleteDetection',
        (tester) async {
      var deletes = 0;

      await tester.pumpWidget(wrap(CustomTextEdit(
        focusNode: FocusNode(),
        autofocus: true,
        deleteDetection: true,
        onInsert: (_) {},
        onDelete: () => deletes++,
        onComposing: (_) {},
        onAction: (_) {},
        onKeyEvent: (_, __) => KeyEventResult.ignored,
        child: const SizedBox(width: 100, height: 100),
      )));

      // Initial editing state is two spaces; simulate the IME removing one.
      binding.testTextInput.updateEditingValue(const TextEditingValue(
        text: ' ',
        selection: TextSelection.collapsed(offset: 1),
      ));
      await binding.idle();

      expect(deletes, 1);
    });

    testWidgets('reports composing text while composing', (tester) async {
      final composing = <String?>[];

      await tester.pumpWidget(wrap(CustomTextEdit(
        focusNode: FocusNode(),
        autofocus: true,
        onInsert: (_) {},
        onDelete: () {},
        onComposing: composing.add,
        onAction: (_) {},
        onKeyEvent: (_, __) => KeyEventResult.ignored,
        child: const SizedBox(width: 100, height: 100),
      )));

      binding.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'nie',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      ));
      await binding.idle();

      expect(composing, ['nie']);
    });

    testWidgets('forwards input actions to onAction', (tester) async {
      final actions = <TextInputAction>[];

      await tester.pumpWidget(wrap(CustomTextEdit(
        focusNode: FocusNode(),
        autofocus: true,
        onInsert: (_) {},
        onDelete: () {},
        onComposing: (_) {},
        onAction: actions.add,
        onKeyEvent: (_, __) => KeyEventResult.ignored,
        child: const SizedBox(width: 100, height: 100),
      )));

      await binding.testTextInput.receiveAction(TextInputAction.done);
      await binding.idle();

      expect(actions, [TextInputAction.done]);
    });
  });

  group('CustomTextEdit.misc', () {
    testWidgets('setEditingState updates the current editing value',
        (tester) async {
      final key = GlobalKey<CustomTextEditState>();

      await tester.pumpWidget(wrap(CustomTextEdit(
        key: key,
        focusNode: FocusNode(),
        autofocus: true,
        onInsert: (_) {},
        onDelete: () {},
        onComposing: (_) {},
        onAction: (_) {},
        onKeyEvent: (_, __) => KeyEventResult.ignored,
        child: const SizedBox(width: 100, height: 100),
      )));

      key.currentState!.setEditingState(const TextEditingValue(
        text: 'x',
        selection: TextSelection.collapsed(offset: 1),
      ));

      expect(key.currentState!.currentTextEditingValue!.text, 'x');
    });

    testWidgets('setEditableRect is a no-op without a connection',
        (tester) async {
      final key = GlobalKey<CustomTextEditState>();

      await tester.pumpWidget(wrap(CustomTextEdit(
        key: key,
        focusNode: FocusNode(),
        onInsert: (_) {},
        onDelete: () {},
        onComposing: (_) {},
        onAction: (_) {},
        onKeyEvent: (_, __) => KeyEventResult.ignored,
        child: const SizedBox(width: 100, height: 100),
      )));

      expect(
        () => key.currentState!.setEditableRect(Rect.zero, Rect.zero),
        returnsNormally,
      );
    });

    testWidgets('forwards key events to onKeyEvent when not composing',
        (tester) async {
      final events = <KeyEvent>[];

      await tester.pumpWidget(wrap(CustomTextEdit(
        focusNode: FocusNode(),
        autofocus: true,
        onInsert: (_) {},
        onDelete: () {},
        onComposing: (_) {},
        onAction: (_) {},
        onKeyEvent: (_, event) {
          events.add(event);
          return KeyEventResult.handled;
        },
        child: const SizedBox(width: 100, height: 100),
      )));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);

      expect(events, hasLength(greaterThan(0)));
      expect(events.first.logicalKey, LogicalKeyboardKey.keyA);
    });
  });
}
