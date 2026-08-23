import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

/// Records every rect/paragraph/atlas call with the paint color attached, so
/// box-drawing geometry can be asserted exactly.
class _RecordingCanvas implements Canvas {
  final rects = <Rect>[];
  // Recorded as ARGB32 because Paint.color round-trips through Float32
  // precision, making exact Color equality unreliable.
  final rectColors = <int>[];
  var paragraphs = 0;
  var atlasSprites = 0;

  @override
  void drawRect(Rect rect, Paint paint) {
    rects.add(rect);
    rectColors.add(paint.color.toARGB32());
  }

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    paragraphs++;
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
    atlasSprites += rstTransforms.length ~/ 4;
  }

  @override
  Float64List getTransform() => Matrix4.identity().storage;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Pixel geometry of a single cell, mirroring the math inside
/// `TerminalPainter._drawBoxDrawingChar` (dpr = 1.0 snapping).
class _CellGeom {
  _CellGeom(double left, this.top, double right, this.bottom)
      : left = left.roundToDouble(),
        right = right.roundToDouble();

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get midX => (left + (right - left) / 2).roundToDouble();
  double get midY => (top + (bottom - top) / 2).roundToDouble();

  Rect h(double y, double x1, double x2) {
    final yr = y.roundToDouble();
    return Rect.fromLTRB(x1, yr, x2, yr + 1.0);
  }

  Rect v(double x, double y1, double y2) {
    final xr = x.roundToDouble();
    return Rect.fromLTRB(xr, y1, xr + 1.0, y2);
  }
}

TerminalPainter _painter() {
  final painter = TerminalPainter(
    theme: TerminalThemes.defaultTheme,
    textStyle: const TerminalStyle(fontSize: 8),
    textScaler: TextScaler.noScaling,
  );
  // A bare PictureRecorder canvas rasterizes at scale 1.0; make the painter's
  // dpr match so snapping is identity and the glyph-atlas path is taken.
  painter.debugDevicePixelRatio = 1.0;
  return painter;
}

_RecordingCanvas _paintText(TerminalPainter painter, String text) {
  final terminal = Terminal();
  terminal.write(text);
  final canvas = _RecordingCanvas();
  painter.paintLine(canvas, Offset.zero, terminal.buffer.lines[0]);
  return canvas;
}

void main() {
  group('box-drawing geometry', () {
    // Every codepoint handled by _drawBoxDrawingChar with its exact expected
    // rects, expressed through the same h/v helpers the implementation uses.
    final cases = <int, List<Rect> Function(_CellGeom)>{
      // light/heavy singles
      0x2500: (g) => [g.h(g.midY, g.left, g.right)], // ─
      0x2501: (g) => [g.h(g.midY, g.left, g.right)], // ━
      0x2502: (g) => [g.v(g.midX, g.top, g.bottom)], // │
      0x2503: (g) => [g.v(g.midX, g.top, g.bottom)], // ┃
      // light corners
      0x250C: (g) => [g.h(g.midY, g.midX, g.right), g.v(g.midX, g.midY, g.bottom)], // ┌
      0x2510: (g) => [g.h(g.midY, g.left, g.midX), g.v(g.midX, g.midY, g.bottom)], // ┐
      0x2514: (g) => [g.h(g.midY, g.midX, g.right), g.v(g.midX, g.top, g.midY)], // └
      0x2518: (g) => [g.h(g.midY, g.left, g.midX), g.v(g.midX, g.top, g.midY)], // ┘
      // heavy corners
      0x250F: (g) => [g.h(g.midY, g.midX, g.right), g.v(g.midX, g.midY, g.bottom)], // ┏
      0x2513: (g) => [g.h(g.midY, g.left, g.midX), g.v(g.midX, g.midY, g.bottom)], // ┓
      0x2517: (g) => [g.h(g.midY, g.midX, g.right), g.v(g.midX, g.top, g.midY)], // ┗
      0x251B: (g) => [g.h(g.midY, g.left, g.midX), g.v(g.midX, g.top, g.midY)], // ┛
      // light T-junctions
      0x251C: (g) => [g.v(g.midX, g.top, g.bottom), g.h(g.midY, g.midX, g.right)], // ├
      0x2524: (g) => [g.v(g.midX, g.top, g.bottom), g.h(g.midY, g.left, g.midX)], // ┤
      0x252C: (g) => [g.h(g.midY, g.left, g.right), g.v(g.midX, g.midY, g.bottom)], // ┬
      0x2534: (g) => [g.h(g.midY, g.left, g.right), g.v(g.midX, g.top, g.midY)], // ┴
      0x253C: (g) => [g.h(g.midY, g.left, g.right), g.v(g.midX, g.top, g.bottom)], // ┼
      // heavy T-junctions
      0x2523: (g) => [g.v(g.midX, g.top, g.bottom), g.h(g.midY, g.midX, g.right)], // ┣
      0x252B: (g) => [g.v(g.midX, g.top, g.bottom), g.h(g.midY, g.left, g.midX)], // ┫
      0x2533: (g) => [g.h(g.midY, g.left, g.right), g.v(g.midX, g.midY, g.bottom)], // ┳
      0x253B: (g) => [g.h(g.midY, g.left, g.right), g.v(g.midX, g.top, g.midY)], // ┻
      0x254B: (g) => [g.h(g.midY, g.left, g.right), g.v(g.midX, g.top, g.bottom)], // ╋
      // double lines
      0x2550: (g) => [g.h(g.midY - 0.5, g.left, g.right), g.h(g.midY + 0.5, g.left, g.right)], // ═
      0x2551: (g) => [g.v(g.midX - 0.5, g.top, g.bottom), g.v(g.midX + 0.5, g.top, g.bottom)], // ║
      0x2554: (g) => [
            // ╔
            g.h(g.midY - 0.5, g.midX, g.right),
            g.h(g.midY + 0.5, g.midX, g.right),
            g.v(g.midX - 0.5, g.midY, g.bottom),
            g.v(g.midX + 0.5, g.midY - 0.5, g.bottom),
          ],
      0x2557: (g) => [
            // ╗
            g.h(g.midY - 0.5, g.left, g.midX),
            g.h(g.midY + 0.5, g.left, g.midX),
            g.v(g.midX - 0.5, g.midY - 0.5, g.bottom),
            g.v(g.midX + 0.5, g.midY, g.bottom),
          ],
      0x255A: (g) => [
            // ╚
            g.h(g.midY - 0.5, g.midX, g.right),
            g.h(g.midY + 0.5, g.midX, g.right),
            g.v(g.midX - 0.5, g.top, g.midY + 0.5),
            g.v(g.midX + 0.5, g.top, g.midY),
          ],
      0x255D: (g) => [
            // ╝
            g.h(g.midY - 0.5, g.left, g.midX),
            g.h(g.midY + 0.5, g.left, g.midX),
            g.v(g.midX - 0.5, g.top, g.midY),
            g.v(g.midX + 0.5, g.top, g.midY + 0.5),
          ],
      0x2560: (g) => [
            // ╠
            g.v(g.midX - 0.5, g.top, g.bottom),
            g.v(g.midX + 0.5, g.top, g.bottom),
            g.h(g.midY - 0.5, g.midX + 0.5, g.right),
            g.h(g.midY + 0.5, g.midX + 0.5, g.right),
          ],
      0x2563: (g) => [
            // ╣
            g.v(g.midX - 0.5, g.top, g.bottom),
            g.v(g.midX + 0.5, g.top, g.bottom),
            g.h(g.midY - 0.5, g.left, g.midX - 0.5),
            g.h(g.midY + 0.5, g.left, g.midX - 0.5),
          ],
      0x2566: (g) => [
            // ╦
            g.h(g.midY - 0.5, g.left, g.right),
            g.h(g.midY + 0.5, g.left, g.right),
            g.v(g.midX - 0.5, g.midY + 0.5, g.bottom),
            g.v(g.midX + 0.5, g.midY + 0.5, g.bottom),
          ],
      0x2569: (g) => [
            // ╩
            g.h(g.midY - 0.5, g.left, g.right),
            g.h(g.midY + 0.5, g.left, g.right),
            g.v(g.midX - 0.5, g.top, g.midY - 0.5),
            g.v(g.midX + 0.5, g.top, g.midY - 0.5),
          ],
      0x256C: (g) => [
            // ╬
            g.h(g.midY - 0.5, g.left, g.right),
            g.h(g.midY + 0.5, g.left, g.right),
            g.v(g.midX - 0.5, g.top, g.bottom),
            g.v(g.midX + 0.5, g.top, g.bottom),
          ],
      // rounded corners (drawn as straight lines)
      0x256D: (g) => [g.h(g.midY, g.midX, g.right), g.v(g.midX, g.midY, g.bottom)], // ╭
      0x256E: (g) => [g.h(g.midY, g.left, g.midX), g.v(g.midX, g.midY, g.bottom)], // ╮
      0x256F: (g) => [g.h(g.midY, g.left, g.midX), g.v(g.midX, g.top, g.midY)], // ╯
      0x2570: (g) => [g.h(g.midY, g.midX, g.right), g.v(g.midX, g.top, g.midY)], // ╰
    };

    test('table covers every handled codepoint', () {
      // Guards the table itself against drift with the implementation.
      expect(cases, hasLength(37));
    });

    for (final entry in cases.entries) {
      test(
          'U+${entry.key.toRadixString(16).toUpperCase()} '
          '${String.fromCharCode(entry.key)}', () {
        final painter = _painter();
        final cw = painter.cellSize.width;
        final ch = painter.cellSize.height;

        final canvas = _paintText(painter, String.fromCharCode(entry.key));

        final geom = _CellGeom(0, 0, cw, ch);
        expect(
          canvas.rects,
          entry.value(geom),
          reason: 'box rects must match the expected geometry exactly',
        );
        // Box-drawing chars never go through the paragraph or atlas paths.
        expect(canvas.paragraphs, 0);
        expect(canvas.atlasSprites, 0);
      });
    }

    test('adjacent cells meet exactly at shared edges', () {
      final painter = _painter();
      final cw = painter.cellSize.width;
      final ch = painter.cellSize.height;

      final canvas = _paintText(painter, '┌─┐');

      // ┌ at col 0, ─ at col 1, ┐ at col 2.
      final g0 = _CellGeom(0, 0, cw, ch);
      final g1 = _CellGeom(cw, 0, cw * 2, ch);
      final g2 = _CellGeom(cw * 2, 0, cw * 3, ch);
      expect(canvas.rects, [
        ...[g0.h(g0.midY, g0.midX, g0.right), g0.v(g0.midX, g0.midY, g0.bottom)],
        g1.h(g1.midY, g1.left, g1.right),
        ...[g2.h(g2.midY, g2.left, g2.midX), g2.v(g2.midX, g2.midY, g2.bottom)],
      ]);
      // The corner arm of ┌ ends where ─ begins — no gap, no overlap.
      expect(canvas.rects[0].right, canvas.rects[2].left);
      // All three share the same horizontal stroke band.
      expect(canvas.rects[0].top, canvas.rects[2].top);
      expect(canvas.rects[0].top, canvas.rects[3].top);
    });
  });

  group('box-drawing colors and flags', () {
    test('uses the resolved foreground color', () {
      final painter = _painter();
      final canvas = _paintText(painter, '\x1b[31m\u{2500}'); // red ─
      expect(canvas.rects, hasLength(1));
      expect(canvas.rectColors.single, TerminalThemes.defaultTheme.red.toARGB32());
    });

    test('faint halves the alpha', () {
      final painter = _painter();
      final canvas = _paintText(painter, '\x1b[2m\u{2500}'); // faint ─
      expect(canvas.rects, hasLength(1));
      expect(
        canvas.rectColors.single,
        TerminalThemes.defaultTheme.foreground.withAlpha(128).toARGB32(),
      );
    });

    test('bold flag still paints with primitives', () {
      final painter = _painter();
      final canvas = _paintText(painter, '\x1b[1m\u{2500}'); // bold ─
      expect(canvas.rects, hasLength(1));
      expect(canvas.paragraphs, 0);
    });

    test('inverse swaps foreground and background', () {
      final painter = _painter();
      final cw = painter.cellSize.width;
      final ch = painter.cellSize.height;

      final canvas = _paintText(painter, '\x1b[7m\u{2500}'); // inverse ─

      // First rect: the cell background in the (inversed) foreground color.
      expect(canvas.rects[0], Rect.fromLTRB(0, 0, cw.roundToDouble(), ch));
      expect(canvas.rectColors[0], TerminalThemes.defaultTheme.foreground.toARGB32());
      // Second rect: the ─ stroke in the theme background color.
      expect(canvas.rects, hasLength(2));
      expect(canvas.rectColors[1], TerminalThemes.defaultTheme.background.toARGB32());
    });
  });

  group('unhandled codepoints fall back to paragraphs', () {
    // In-range codepoints _drawBoxDrawingChar returns false for.
    final inRangeUnhandled = [
      0x2504, // ┄ light triple dash horizontal
      0x2508, // ┈ light quadruple dash horizontal
      0x250D, // ╍-adjacent heavy corner variant
      0x254C, // ╌ light double dash horizontal
      0x2571, // ╱ light diagonal upper right to lower left
      0x2573, // ╳ light diagonal cross
    ];

    for (final cp in inRangeUnhandled) {
      test(
          'U+${cp.toRadixString(16).toUpperCase()} '
          '${String.fromCharCode(cp)} paints as a paragraph', () {
        final painter = _painter();
        final canvas = _paintText(painter, String.fromCharCode(cp));
        expect(canvas.rects, isEmpty);
        expect(canvas.paragraphs, 1);
      });
    }

    test('U+2580 (block elements, outside the range) paints as a paragraph', () {
      final painter = _painter();
      final canvas = _paintText(painter, '\u{2580}'); // ▀
      expect(canvas.rects, isEmpty);
      expect(canvas.paragraphs, 1);
    });
  });
}
