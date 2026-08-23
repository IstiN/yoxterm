import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/src/ui/painter.dart';
import 'package:yoxterm/xterm.dart';

import '../../_fixture/_fixture.dart';

class _CountingCanvas implements Canvas {
  var rects = 0;
  var paragraphs = 0;
  var atlasCalls = 0;
  var atlasSprites = 0;

  @override
  void drawRect(Rect rect, Paint paint) => rects++;

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) => paragraphs++;

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
    atlasCalls++;
    atlasSprites += rstTransforms.length ~/ 4;
  }

  @override
  Float64List getTransform() => Matrix4.identity().storage;

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
    // A bare PictureRecorder canvas rasterizes at scale 1.0; make the
    // painter's dpr match so the glyph-atlas path is taken.
    painter.debugDevicePixelRatio = 1.0;
    final cw = painter.cellSize.width;

    // Current paintLine path: background runs + glyph-atlas sprite batches,
    // with paragraph fallbacks for non-mergeable cells.
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
        'merged+atlas: rects=${merged.rects} paragraphs=${merged.paragraphs} '
        'atlasCalls=${merged.atlasCalls} sprites=${merged.atlasSprites} '
        'total=${merged.rects + merged.paragraphs + merged.atlasCalls}');

    final perCellOps = perCell.rects + perCell.paragraphs;
    final mergedOps = merged.rects + merged.paragraphs + merged.atlasCalls;
    expect(mergedOps, lessThan(perCellOps ~/ 2),
        reason:
            'run merging + atlas batching must at least halve draw ops ($mergedOps vs $perCellOps)');
    // The atlas should absorb the bulk of ASCII glyphs into a handful of
    // batched draw calls.
    expect(merged.atlasSprites, greaterThan(cells ~/ 2),
        reason: 'most cells should be painted as atlas sprites');
    expect(merged.paragraphs, lessThan(100),
        reason: 'ASCII paragraphs should be replaced by atlas batches');
  });

  test('replayed lines emit the same canvas calls as fresh builds', () {
    final terminal = Terminal();
    terminal.write(TestFixtures.htop_80x25_3s());

    final painter = TerminalPainter(
      theme: TerminalThemes.defaultTheme,
      textStyle: const TerminalStyle(fontSize: 13),
      textScaler: TextScaler.noScaling,
    );
    painter.debugDevicePixelRatio = 1.0;

    // First pass builds (cache miss), second pass at the same offsets replays
    // the recorded ops, third pass at shifted offsets replays with recomputed
    // (re-snapped) coordinates. All three must emit identical op counts.
    final built = _CountingCanvas();
    final replayedSame = _CountingCanvas();
    final replayedShifted = _CountingCanvas();
    final lines = terminal.buffer.lines;
    for (var li = 0; li < lines.length; li++) {
      painter.paintLine(built, Offset(0, li * 16.0), lines[li]);
    }
    expect(painter.debugLineBuildCount, lines.length);
    for (var li = 0; li < lines.length; li++) {
      painter.paintLine(replayedSame, Offset(0, li * 16.0), lines[li]);
      painter.paintLine(replayedShifted, Offset(1.5, li * 16.0 + 0.5), lines[li]);
    }
    expect(painter.debugLineBuildCount, lines.length,
        reason: 'second and third passes must be pure replays');

    int opsOf(_CountingCanvas c) => c.rects + c.paragraphs + c.atlasCalls;
    expect(opsOf(replayedSame), opsOf(built));
    expect(replayedSame.atlasSprites, built.atlasSprites);
    expect(opsOf(replayedShifted), opsOf(built));
    expect(replayedShifted.atlasSprites, built.atlasSprites);
  });
}
