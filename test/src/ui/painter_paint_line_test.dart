import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

class _RecordingCanvas implements Canvas {
  final rects = <String>[];
  final paragraphs = <String>[];
  final atlasBatches = <String>[];

  @override
  void drawRect(Rect rect, Paint paint) {
    rects.add('rect(${rect.left},${rect.top},${rect.right},${rect.bottom}) color=${paint.color}');
  }

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    paragraphs.add('paragraph@(${offset.dx},${offset.dy})');
  }

  @override
  void drawRawAtlas(
    ui.Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) {
    // Record the batch by its first sprite's translation plus sprite count.
    atlasBatches.add(
      'atlas@(${rstTransforms[2]},${rstTransforms[3]}) sprites=${rstTransforms.length ~/ 4}',
    );
  }

  @override
  Float64List getTransform() => Matrix4.identity().storage;

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
    // A bare PictureRecorder canvas rasterizes at scale 1.0; make the
    // painter's dpr match so the glyph-atlas path is taken.
    painter.debugDevicePixelRatio = 1.0;
    final canvas = _RecordingCanvas();
    painter.paintLine(canvas, Offset.zero, line);

    final cw = painter.cellSize.width;
    // One bg rect covering exactly the two colored cells.
    expect(canvas.rects, hasLength(1));
    expect(canvas.rects.single, contains('rect(0.0,0.0,${cw * 2},'));
    // Mergeable ASCII cells are painted as atlas sprites: one batch for "AB"
    // (flushed when its blue background rect is drawn) and one for "CD"
    // (flushed at end of line). No paragraph calls remain for them.
    expect(canvas.paragraphs, isEmpty);
    expect(canvas.atlasBatches, hasLength(2));
    expect(canvas.atlasBatches[0], 'atlas@(0.0,0.0) sprites=2');
    expect(canvas.atlasBatches[1], 'atlas@(${cw * 3},0.0) sprites=2');
  });
}
