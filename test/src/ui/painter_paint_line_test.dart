import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

class _RecordingCanvas implements Canvas {
  final rects = <String>[];
  final paragraphs = <String>[];

  @override
  void drawRect(Rect rect, Paint paint) {
    rects.add('rect(${rect.left},${rect.top},${rect.right},${rect.bottom}) color=${paint.color}');
  }

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    paragraphs.add('paragraph@(${offset.dx},${offset.dy})');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('paintLine paints every cell of a colored ASCII line', () {
    final terminal = Terminal();
    // fg red (31) bg blue (44): "AB", then default space, then fg green (32)
    // bg default: "CD".
    terminal.write('\x1b[31;44mAB\x1b[0m \x1b[32mCD');
    final line = terminal.buffer.lines[0];

    final painter = TerminalPainter(
      theme: TerminalThemes.defaultTheme,
      textStyle: const TerminalStyle(fontSize: 8),
      textScaler: TextScaler.noScaling,
    );
    final canvas = _RecordingCanvas();
    painter.paintLine(canvas, Offset.zero, line);

    final cw = painter.cellSize.width;
    // One bg rect covering exactly the two colored cells.
    expect(canvas.rects, hasLength(1));
    expect(canvas.rects.single, contains('rect(0.0,0.0,${cw * 2},'));
    // Two text runs: "AB" at col 0, "CD" at col 3.
    expect(canvas.paragraphs, hasLength(2));
    expect(canvas.paragraphs[0], 'paragraph@(0.0,0.0)');
    expect(canvas.paragraphs[1], 'paragraph@(${cw * 3},0.0)');
  });
}
