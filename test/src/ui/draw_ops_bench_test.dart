import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

import '../../_fixture/_fixture.dart';

class _CountingCanvas implements Canvas {
  var rects = 0;
  var paragraphs = 0;

  @override
  void drawRect(Rect rect, Paint paint) => rects++;

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) => paragraphs++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('count draw ops for htop frame', () {
    final terminal = Terminal();
    terminal.write(TestFixtures.htop_80x25_3s());

    final painter = TerminalPainter(
      theme: TerminalThemes.defaultTheme,
      textStyle: const TerminalStyle(fontSize: 13),
      textScaler: TextScaler.noScaling,
    );
    final cw = painter.cellSize.width;

    // New merged path.
    final merged = _CountingCanvas();
    var cells = 0;
    for (var li = 0; li < terminal.buffer.lines.length; li++) {
      final line = terminal.buffer.lines[li];
      painter.paintLine(merged, Offset.zero, line);
      cells += line.length;
    }

    // Old per-cell path (paintCell per cell).
    final perCell = _CountingCanvas();
    final cellData = CellData.empty();
    for (var li = 0; li < terminal.buffer.lines.length; li++) {
      final line = terminal.buffer.lines[li];
      for (var i = 0; i < line.length; i++) {
        line.getCellData(i, cellData);
        final charWidth = cellData.content >> CellContent.widthShift;
        final eff = charWidth == 2 ? 2 : 1;
        painter.paintCell(
            perCell, Offset(i * cw, 0), cellData, (i + eff) * cw);
        if (charWidth == 2) i++;
      }
    }

    // ignore: avoid_print
    print('cells=$cells');
    // ignore: avoid_print
    print(
        'per-cell: rects=${perCell.rects} paragraphs=${perCell.paragraphs} total=${perCell.rects + perCell.paragraphs}');
    // ignore: avoid_print
    print(
        'merged:   rects=${merged.rects} paragraphs=${merged.paragraphs} total=${merged.rects + merged.paragraphs}');

    final perCellOps = perCell.rects + perCell.paragraphs;
    final mergedOps = merged.rects + merged.paragraphs;
    expect(mergedOps, lessThan(perCellOps ~/ 2),
        reason:
            'run merging must at least halve draw ops ($mergedOps vs $perCellOps)');
  });
}
