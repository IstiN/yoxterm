import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ViewportOffset;
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/src/ui/render.dart';
import 'package:yoxterm/xterm.dart';

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
  group('layout', () {
    testWidgets('autoResize fits the terminal to the viewport', (tester) async {
      final terminal = Terminal();
      final rt = await _pump(tester, terminal, size: const Size(800, 400));

      expect(terminal.viewWidth, 800 ~/ rt.cellSize.width);
      expect(terminal.viewHeight, 400 ~/ rt.cellSize.height);
      expect(rt.size, const Size(800, 400));
      expect(rt.lineHeight, rt.cellSize.height);
    });

    testWidgets('autoResize false keeps the default terminal size',
        (tester) async {
      final terminal = Terminal();
      await _pump(tester, terminal, autoResize: false);

      expect(terminal.viewWidth, 80);
      expect(terminal.viewHeight, 24);
    });

    testWidgets('hitTestSelf is always true', (tester) async {
      final terminal = Terminal();
      final rt = await _pump(tester, terminal);
      expect(rt.hitTestSelf(Offset.zero), isTrue);
    });
  });

  group('coordinates', () {
    testWidgets('getOffset and getCellOffset round-trip a cell',
        (tester) async {
      final terminal = Terminal();
      final rt = await _pump(tester, terminal);
      final cw = rt.cellSize.width;
      final ch = rt.cellSize.height;

      final offset = rt.getOffset(const CellOffset(2, 3));
      expect(offset, Offset(2 * cw, 3 * ch));
      expect(rt.getCellOffset(offset), const CellOffset(2, 3));
      // Any point inside the cell maps back to the same cell.
      expect(
        rt.getCellOffset(offset.translate(cw - 1, ch - 1)),
        const CellOffset(2, 3),
      );
    });

    testWidgets('getCellOffset clamps to the visible buffer', (tester) async {
      final terminal = Terminal();
      final rt = await _pump(tester, terminal);

      expect(rt.getCellOffset(const Offset(-100, -100)), const CellOffset(0, 0));
      expect(
        rt.getCellOffset(const Offset(100000, 100000)),
        CellOffset(
          terminal.viewWidth - 1,
          terminal.buffer.lines.length - 1,
        ),
      );
    });

    testWidgets('cursorOffset tracks the buffer cursor', (tester) async {
      final terminal = Terminal();
      final rt = await _pump(tester, terminal);
      terminal.write('hello');

      final dpr = tester.view.devicePixelRatio;
      final rawX = 5 * rt.cellSize.width;
      final snappedX = dpr > 0 ? (rawX * dpr).roundToDouble() / dpr : rawX;
      expect(rt.cursorOffset, Offset(snappedX, 0));
    });
  });

  group('selection', () {
    testWidgets('selectWord selects the whole word', (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();
      final rt = await _pump(tester, terminal, controller: controller);
      terminal.write('hello world');

      rt.selectWord(rt.getOffset(const CellOffset(1, 0)));

      expect(controller.selection, isNotNull);
      expect(terminal.buffer.getText(controller.selection!), 'hello');
    });

    testWidgets('selectWord with an end point merges both word boundaries',
        (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();
      final rt = await _pump(tester, terminal, controller: controller);
      terminal.write('hello big world');

      rt.selectWord(
        rt.getOffset(const CellOffset(1, 0)),
        rt.getOffset(const CellOffset(13, 0)),
      );

      expect(terminal.buffer.getText(controller.selection!), 'hello big world');
    });

    testWidgets('selectWord on a word separator selects the adjacent word',
        (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();
      final rt = await _pump(tester, terminal, controller: controller);
      terminal.write('hello world');

      // The space at column 5 has 'hello' on its left: getWordBoundary scans
      // left from the separator and returns that word.
      rt.selectWord(rt.getOffset(const CellOffset(5, 0)));

      expect(terminal.buffer.getText(controller.selection!), 'hello');
    });

    testWidgets('selectWord between two separators selects nothing',
        (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();
      final rt = await _pump(tester, terminal, controller: controller);
      terminal.write('a  b');

      // The second space is surrounded by separators on both sides, so there
      // is no word boundary to select.
      rt.selectWord(rt.getOffset(const CellOffset(2, 0)));

      expect(controller.selection, isNull);
    });

    testWidgets('selectCharacters selects the character range',
        (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();
      final rt = await _pump(tester, terminal, controller: controller);
      terminal.write('hello');

      rt.selectCharacters(
        rt.getOffset(const CellOffset(0, 0)),
        rt.getOffset(const CellOffset(2, 0)),
      );

      expect(terminal.buffer.getText(controller.selection!), 'hel');
    });

    testWidgets('selectCharacters without an end sets an empty caret',
        (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();
      final rt = await _pump(tester, terminal, controller: controller);
      terminal.write('hello');

      rt.selectCharacters(rt.getOffset(const CellOffset(1, 0)));

      // A selection exists but covers zero cells (a caret).
      expect(controller.selection, isNotNull);
      expect(terminal.buffer.getText(controller.selection!), '');
    });

    testWidgets('selectCharacters with the same end point selects one cell',
        (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();
      final rt = await _pump(tester, terminal, controller: controller);
      terminal.write('hello');

      final point = rt.getOffset(const CellOffset(1, 0));
      rt.selectCharacters(point, point);

      expect(terminal.buffer.getText(controller.selection!), 'e');
    });

    testWidgets('selectCharacters backwards does not extend the end',
        (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();
      final rt = await _pump(tester, terminal, controller: controller);
      terminal.write('hello');

      rt.selectCharacters(
        rt.getOffset(const CellOffset(3, 0)),
        rt.getOffset(const CellOffset(1, 0)),
      );

      expect(terminal.buffer.getText(controller.selection!), 'el');
    });
  });

  group('mouse input', () {
    testWidgets('mouse events are ignored without mouse reporting',
        (tester) async {
      final terminal = Terminal();
      final rt = await _pump(tester, terminal);

      final handled = rt.mouseEvent(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        rt.getOffset(const CellOffset(0, 0)),
      );
      expect(handled, isFalse);
    });

    testWidgets('mouse events are reported when mouse mode is enabled',
        (tester) async {
      final outputs = <String>[];
      final terminal = Terminal()..onOutput = outputs.add;
      final rt = await _pump(tester, terminal);
      terminal.write('\x1b[?1000h'); // VT200 mouse tracking

      final handled = rt.mouseEvent(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        rt.getOffset(const CellOffset(0, 0)),
      );

      expect(handled, isTrue);
      expect(outputs.single, contains('\x1b[M'));
    });
  });

  group('painting', () {
    testWidgets('paints text, cursor, selection and highlights', (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();
      final rt = await _pump(tester, terminal,
          controller: controller, alwaysShowCursor: true);
      terminal.write('\x1b[31;44mAB\x1b[0m CD \u{2500}\u{2554}\u{4e16}\x1b[0m');

      controller.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(2, 0),
      );
      controller.highlight(
        p1: terminal.buffer.createAnchor(4, 0),
        p2: terminal.buffer.createAnchor(6, 0),
        color: Colors.yellow,
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(rt.debugNeedsPaint, isFalse);
    });

    testWidgets('paints all cursor types, focused and unfocused',
        (tester) async {
      final terminal = Terminal();
      await _pump(tester, terminal, alwaysShowCursor: true);
      terminal.write('x');

      for (final type in TerminalCursorType.values) {
        final rt = tester
            .state<TerminalViewState>(find.byType(TerminalView))
            .renderTerminal;
        rt.cursorType = type;
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('paints composing text at the cursor', (tester) async {
      final terminal = Terminal();
      final rt = await _pump(tester, terminal, alwaysShowCursor: true);
      terminal.write('prompt> ');

      rt.composingText = 'ê';
      await tester.pump();
      expect(tester.takeException(), isNull);

      rt.composingText = null;
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('paints after scrolling into the scrollback', (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();
      await _pump(tester, terminal, controller: controller);
      for (var i = 0; i < 200; i++) {
        terminal.write('line $i\r\n');
      }
      await tester.pump();

      // Select a range spanning into the scrollback, then scroll up.
      controller.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(5, 2),
      );
      controller.highlight(
        p1: terminal.buffer.createAnchor(0, 0),
        p2: terminal.buffer.createAnchor(3, 0),
        color: Colors.yellow,
      );
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      scrollable.position.jumpTo(0);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('property setters', () {
    testWidgets('textStyle change re-measures cells and resizes the terminal',
        (tester) async {
      final terminal = Terminal();
      final rt = await _pump(tester, terminal, size: const Size(800, 400));
      final small = rt.cellSize;

      rt.textStyle = const TerminalStyle(fontSize: 26);
      await tester.pump();

      expect(rt.cellSize.width, greaterThan(small.width));
      expect(terminal.viewWidth, 800 ~/ rt.cellSize.width);

      // Same-value assignment is a no-op (does not throw or relayout).
      const biggerStyle = TerminalStyle(fontSize: 26);
      rt.textStyle = biggerStyle;
      rt.textStyle = biggerStyle;
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('textScaler change re-measures cells', (tester) async {
      final terminal = Terminal();
      final rt = await _pump(tester, terminal);
      final unscaled = rt.cellSize;

      rt.textScaler = const TextScaler.linear(2);
      await tester.pump();

      expect(rt.cellSize.height, greaterThan(unscaled.height * 1.5));
      const doubleScaler = TextScaler.linear(2);
      rt.textScaler = doubleScaler; // no-op reassignment
      await tester.pump();
    });

    testWidgets('theme and padding changes repaint without error',
        (tester) async {
      final terminal = Terminal();
      final rt = await _pump(tester, terminal);
      terminal.write('hello');

      rt.theme = TerminalThemes.whiteOnBlack;
      rt.padding = const EdgeInsets.all(8);
      rt.autoResize = false;
      rt.alwaysShowCursor = true;
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Padding shifts cell coordinates horizontally; the y position also
      // depends on the current scroll offset, so compare against row 0.
      final offset = rt.getOffset(const CellOffset(2, 3));
      final row0 = rt.getOffset(const CellOffset(0, 0));
      expect(offset.dx, 2 * rt.cellSize.width + 8);
      expect(offset.dy, row0.dy + 3 * rt.cellSize.height);

      // No-op reassignments (RenderTerminal exposes setters only).
      rt.theme = TerminalThemes.whiteOnBlack;
      rt.padding = const EdgeInsets.all(8);
      rt.autoResize = false;
      rt.alwaysShowCursor = true;
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('terminal, controller, offset and focusNode are swappable',
        (tester) async {
      final terminal = Terminal();
      final controller = TerminalController();
      final rt = await _pump(tester, terminal, controller: controller);
      terminal.write('old');

      final newTerminal = Terminal()..write('new');
      final newController = TerminalController();
      rt.terminal = newTerminal;
      rt.controller = newController;
      rt.offset = ViewportOffset.fixed(0);
      rt.focusNode = FocusNode();
      await tester.pump();

      expect(tester.takeException(), isNull);

      // The render object now follows the new terminal.
      newTerminal.write('!');
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Same-value assignments are no-ops.
      final fixedOffset = ViewportOffset.fixed(0);
      final focusNode = FocusNode();
      rt.terminal = newTerminal;
      rt.controller = newController;
      rt.offset = fixedOffset;
      rt.offset = fixedOffset;
      rt.focusNode = focusNode;
      rt.focusNode = focusNode;
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('onEditableRect is notified when the terminal changes',
        (tester) async {
      final terminal = Terminal();
      final rt = await _pump(tester, terminal);

      final calls = <List<Rect>>[];
      rt.onEditableRect = (rect, caretRect) => calls.add([rect, caretRect]);
      // Notifications are gated on an open IME input connection (the only
      // consumer of the geometry) — simulate one being open.
      rt.inputConnectionOpen = () => true;

      terminal.write('x');
      await tester.pump();

      expect(calls, isNotEmpty);
      expect(calls.last[1].width, rt.cellSize.width);
      expect(calls.last[1].height, rt.cellSize.height);

      // A closed input connection skips the notifications.
      calls.clear();
      rt.inputConnectionOpen = () => false;
      terminal.write('z');
      await tester.pump();
      expect(calls, isEmpty);

      // Clearing the callback stops the notifications.
      rt.inputConnectionOpen = () => true;
      rt.onEditableRect = null;
      terminal.write('y');
      await tester.pump();
      expect(calls, isEmpty);
    });

    testWidgets('systemFontsDidChange clears painter caches', (tester) async {
      final terminal = Terminal();
      final rt = await _pump(tester, terminal);
      terminal.write('hello');
      await tester.pump();

      rt.systemFontsDidChange();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('resize debounce', () {
    testWidgets('alt-buffer resizes are debounced by 200ms', (tester) async {
      final terminal = Terminal();
      await _pump(tester, terminal, size: const Size(800, 400));
      final oldWidth = terminal.viewWidth;
      expect(terminal.isUsingAltBuffer, isFalse);

      terminal.write('\x1b[?1049h'); // switch to the alt buffer
      expect(terminal.isUsingAltBuffer, isTrue);

      // Shrink the widget: layout picks up the new viewport size but the
      // terminal resize is debounced.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: _view(terminal, size: const Size(400, 400)),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(terminal.viewWidth, oldWidth); // debounced, not yet applied

      await tester.pump(const Duration(milliseconds: 250));
      expect(terminal.viewWidth, isNot(oldWidth));
    });

    testWidgets('detaching cancels a pending debounced resize', (tester) async {
      final terminal = Terminal();
      await _pump(tester, terminal, size: const Size(800, 400));
      terminal.write('\x1b[?1049h');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: _view(terminal, size: const Size(400, 400)),
            ),
          ),
        ),
      ));
      await tester.pump();

      // Remove the widget before the debounce timer fires: detach must cancel
      // it so no pending-timer failure surfaces at test end.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      terminal.write('late output');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('main buffer with large scrollback debounces by 150ms',
        (tester) async {
      final terminal = Terminal(maxLines: 1000);
      await _pump(tester, terminal, size: const Size(800, 400));
      final oldWidth = terminal.viewWidth;

      // Push the scrollback past the 100-line debounce threshold.
      for (var i = 0; i < 200; i++) {
        terminal.write('line $i\r\n');
      }
      await tester.pump();
      expect(terminal.isUsingAltBuffer, isFalse);
      expect(
        terminal.lines.length - terminal.viewHeight,
        greaterThan(100),
      );

      // An immediate resize happens for small scrollbacks; here it debounces.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: _view(terminal, size: const Size(400, 400)),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(terminal.viewWidth, oldWidth); // debounced, not yet applied

      await tester.pump(const Duration(milliseconds: 200));
      expect(terminal.viewWidth, isNot(oldWidth));
    });

    testWidgets('main buffer with small scrollback resizes immediately',
        (tester) async {
      final terminal = Terminal();
      await _pump(tester, terminal, size: const Size(800, 400));
      final oldWidth = terminal.viewWidth;
      terminal.write('short session');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: _view(terminal, size: const Size(400, 400)),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(terminal.viewWidth, isNot(oldWidth)); // applied synchronously
    });
  });
}
