import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/src/ui/shortcut/actions.dart';

void main() {
  late List<MethodCall> clipboardCalls;
  late String? clipboardText;

  setUp(() {
    clipboardCalls = <MethodCall>[];
    clipboardText = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      clipboardCalls.add(call);
      if (call.method == 'Clipboard.getData') {
        if (clipboardText == null) return null;
        return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<BuildContext> pumpActions(
    WidgetTester tester,
    Terminal terminal,
    TerminalController controller,
  ) async {
    late BuildContext actionsContext;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TerminalActions(
          terminal: terminal,
          controller: controller,
          child: Builder(
            builder: (context) {
              actionsContext = context;
              return const SizedBox(width: 100, height: 100);
            },
          ),
        ),
      ),
    ));

    return actionsContext;
  }

  group('TerminalActions.paste', () {
    testWidgets('pastes clipboard text into the terminal', (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      final controller = TerminalController();

      final context = await pumpActions(tester, terminal, controller);

      clipboardText = 'pasted content';
      Actions.invoke(context, const PasteTextIntent(
        SelectionChangedCause.keyboard,
      ));
      await tester.pump();

      expect(output, ['pasted content']);
    });

    testWidgets('does nothing when the clipboard is empty', (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      final controller = TerminalController();

      final context = await pumpActions(tester, terminal, controller);

      Actions.invoke(context, const PasteTextIntent(
        SelectionChangedCause.keyboard,
      ));
      await tester.pump();

      expect(output, isEmpty);
    });

    testWidgets('clears the selection after pasting', (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();

      terminal.write('hello world');
      final context = await pumpActions(tester, terminal, controller);

      controller.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(2, 0),
      );
      expect(controller.selection, isNotNull);

      clipboardText = 'x';
      Actions.invoke(context, const PasteTextIntent(
        SelectionChangedCause.keyboard,
      ));
      await tester.pump();

      expect(controller.selection, isNull);
    });

    testWidgets('respects bracketed paste mode', (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      final controller = TerminalController();

      final context = await pumpActions(tester, terminal, controller);

      terminal.write('\x1b[?2004h');
      clipboardText = 'pasted';
      Actions.invoke(context, const PasteTextIntent(
        SelectionChangedCause.keyboard,
      ));
      await tester.pump();

      expect(output, ['\x1b[200~pasted\x1b[201~']);
    });
  });

  group('TerminalActions.copy', () {
    testWidgets('copies the selected text to the clipboard', (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();

      terminal.write('hello world');
      final context = await pumpActions(tester, terminal, controller);

      controller.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(5, 0),
      );
      await tester.pump();

      Actions.invoke(context, CopySelectionTextIntent.copy);
      await tester.pump();

      final setDataCalls = clipboardCalls
          .where((call) => call.method == 'Clipboard.setData')
          .toList();
      expect(setDataCalls, hasLength(1));
      expect(setDataCalls.single.arguments['text'], 'hello');
    });

    testWidgets('does nothing without a selection', (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();

      terminal.write('hello world');
      final context = await pumpActions(tester, terminal, controller);

      Actions.invoke(context, CopySelectionTextIntent.copy);
      await tester.pump();

      expect(
        clipboardCalls.where((call) => call.method == 'Clipboard.setData'),
        isEmpty,
      );
    });
  });

  group('TerminalActions.selectAll', () {
    testWidgets('selects the whole buffer', (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();

      for (var i = 0; i < 30; i++) {
        terminal.write('line $i\r\n');
      }

      final context = await pumpActions(tester, terminal, controller);

      expect(controller.selection, isNull);

      Actions.invoke(context, const SelectAllTextIntent(
        SelectionChangedCause.keyboard,
      ));
      await tester.pump();

      final selection = controller.selection;
      expect(selection, isNotNull);

      // The selection covers the full buffer including the scrollback
      // (line 0 .. buffer.height - 1), not just the visible viewport.
      final text = terminal.buffer.getText(selection!);
      expect(text, contains('line 0\n'));
      expect(text, contains('line 7\n'));
      expect(text, contains('line 29'));
    });

    testWidgets('selects in line selection mode', (tester) async {
      final terminal = Terminal();
      final controller = TerminalController(
        selectionMode: SelectionMode.block,
      );

      terminal.write('hello');
      final context = await pumpActions(tester, terminal, controller);

      Actions.invoke(context, const SelectAllTextIntent(
        SelectionChangedCause.keyboard,
      ));
      await tester.pump();

      // SelectAll forces line selection mode.
      expect(controller.selectionMode, SelectionMode.line);
      expect(controller.selection, isA<BufferRangeLine>());
    });
  });
}
