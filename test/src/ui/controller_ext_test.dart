import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/xterm.dart';

void main() {
  group('TerminalController.defaults', () {
    test('has sensible defaults', () {
      final controller = TerminalController();

      expect(controller.selectionMode, SelectionMode.line);
      expect(controller.pointerInput.inputs, {PointerInput.tap});
      expect(controller.suspendedPointerInputs, isFalse);
      expect(controller.selection, isNull);
      expect(controller.highlights, isEmpty);
    });

    test('accepts initial configuration', () {
      final controller = TerminalController(
        selectionMode: SelectionMode.block,
        pointerInputs: const PointerInputs({PointerInput.scroll}),
        suspendPointerInput: true,
      );

      expect(controller.selectionMode, SelectionMode.block);
      expect(controller.pointerInput.inputs, {PointerInput.scroll});
      expect(controller.suspendedPointerInputs, isTrue);
    });
  });

  group('TerminalController.selectionMode', () {
    test('setSelectionMode notifies listeners', () {
      final controller = TerminalController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setSelectionMode(SelectionMode.block);

      expect(controller.selectionMode, SelectionMode.block);
      expect(notifications, 1);
    });

    test('setSelectionMode with the same mode does not notify', () {
      final controller = TerminalController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setSelectionMode(SelectionMode.line);

      expect(notifications, 0);
    });
  });

  group('TerminalController.pointerInputs', () {
    test('setPointerInputs updates and notifies', () {
      final controller = TerminalController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setPointerInputs(const PointerInputs.all());

      expect(controller.pointerInput.inputs, hasLength(4));
      expect(notifications, 1);
    });

    test('shouldSendPointerInput reflects the configured set', () {
      final controller = TerminalController(
        pointerInputs: const PointerInputs({PointerInput.scroll}),
      );

      // ignore: invalid_use_of_visible_for_testing_member
      expect(controller.shouldSendPointerInput(PointerInput.scroll), isTrue);
      // ignore: invalid_use_of_visible_for_testing_member
      expect(controller.shouldSendPointerInput(PointerInput.tap), isFalse);
    });

    test('suspendPointerInput blocks all pointer inputs', () {
      final controller = TerminalController(
        pointerInputs: const PointerInputs.all(),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setSuspendPointerInput(true);

      expect(controller.suspendedPointerInputs, isTrue);
      expect(notifications, 1);
      // ignore: invalid_use_of_visible_for_testing_member
      expect(controller.shouldSendPointerInput(PointerInput.tap), isFalse);
      // ignore: invalid_use_of_visible_for_testing_member
      expect(controller.shouldSendPointerInput(PointerInput.scroll), isFalse);

      controller.setSuspendPointerInput(false);

      expect(notifications, 2);
      // ignore: invalid_use_of_visible_for_testing_member
      expect(controller.shouldSendPointerInput(PointerInput.tap), isTrue);
    });
  });

  group('TerminalController.selection', () {
    test('setSelection takes ownership and notifies', () {
      final terminal = Terminal();
      final controller = TerminalController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(2, 2),
      );

      expect(controller.selection, isNotNull);
      expect(notifications, 1);
    });

    test('setSelection replaces and disposes previous anchors', () {
      final terminal = Terminal();
      final controller = TerminalController();

      final base1 = terminal.buffer.createAnchor(0, 0);
      final extent1 = terminal.buffer.createAnchor(2, 2);
      controller.setSelection(base1, extent1);

      controller.setSelection(
        terminal.buffer.createAnchor(1, 1),
        terminal.buffer.createAnchor(3, 3),
      );

      expect(base1.attached, isFalse);
      expect(extent1.attached, isFalse);
      expect(controller.selection, isNotNull);
    });

    test('setSelection can switch the selection mode', () {
      final terminal = Terminal();
      final controller = TerminalController();

      controller.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(2, 2),
        mode: SelectionMode.block,
      );

      expect(controller.selectionMode, SelectionMode.block);
      expect(controller.selection, isA<BufferRangeBlock>());
    });

    test('selection is null when an anchor gets detached', () {
      final terminal = Terminal(maxLines: 40);
      final controller = TerminalController();

      controller.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(2, 2),
      );
      expect(controller.selection, isNotNull);

      // Push enough lines to discard the lines the anchors point to.
      for (var i = 0; i < 60; i++) {
        terminal.write('line $i\r\n');
      }

      expect(controller.selection, isNull);
    });

    test('clearSelection notifies and disposes anchors', () {
      final terminal = Terminal();
      final controller = TerminalController();

      final base = terminal.buffer.createAnchor(0, 0);
      final extent = terminal.buffer.createAnchor(2, 2);
      controller.setSelection(base, extent);

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.clearSelection();

      expect(controller.selection, isNull);
      expect(base.attached, isFalse);
      expect(extent.attached, isFalse);
      expect(notifications, 1);
    });

    test('clearSelection works when nothing is selected', () {
      final controller = TerminalController();
      expect(controller.clearSelection, returnsNormally);
      expect(controller.selection, isNull);
    });
  });

  group('TerminalController.highlight', () {
    test('exposes a BufferRangeLine while anchors are attached', () {
      final terminal = Terminal();
      final controller = TerminalController();

      final highlight = controller.highlight(
        p1: terminal.buffer.createAnchor(5, 0),
        p2: terminal.buffer.createAnchor(10, 2),
        color: Colors.yellow,
      );

      expect(highlight.range, isA<BufferRangeLine>());
      expect(highlight.owner, same(controller));
      expect(highlight.color, Colors.yellow);
    });

    test('range is null when an anchor is detached', () {
      final terminal = Terminal();
      final controller = TerminalController();

      final p1 = terminal.buffer.createAnchor(5, 0);
      final highlight = controller.highlight(
        p1: p1,
        p2: terminal.buffer.createAnchor(10, 2),
        color: Colors.yellow,
      );

      expect(highlight.range, isNotNull);

      p1.dispose();

      expect(highlight.range, isNull);
    });

    test('notifies on add and on remove', () {
      final terminal = Terminal();
      final controller = TerminalController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      final highlight = controller.highlight(
        p1: terminal.buffer.createAnchor(5, 0),
        p2: terminal.buffer.createAnchor(10, 2),
        color: Colors.yellow,
      );
      expect(controller.highlights, hasLength(1));
      expect(notifications, 1);

      highlight.dispose();
      expect(controller.highlights, isEmpty);
      expect(notifications, 2);
    });
  });
}
