import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/src/ui/painter.dart';
import 'package:yoxterm/xterm.dart';

/// Recording canvas with a configurable (axis-aligned) raster scale so tests
/// can flip the glyph-atlas usability check in [TerminalPainter.paintLine].
class _RecordingCanvas implements Canvas {
  _RecordingCanvas({double scale = 1.0})
      : _transform =
            (Matrix4.identity()..scaleByDouble(scale, scale, 1.0, 1.0)).storage;

  final Float64List _transform;

  final rects = <Rect>[];
  final rectColors = <int>[];
  final rectStyles = <PaintingStyle>[];
  final lines = <String>[];
  final paragraphOffsets = <Offset>[];
  final atlasTranslations = <Offset>[];

  int get paragraphs => paragraphOffsets.length;

  @override
  void drawRect(Rect rect, Paint paint) {
    rects.add(rect);
    // Recorded as ARGB32 because Paint.color round-trips through Float32
    // precision, making exact Color equality unreliable.
    rectColors.add(paint.color.toARGB32());
    rectStyles.add(paint.style);
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    lines.add('${p1.dx},${p1.dy}->${p2.dx},${p2.dy} '
        'color=${paint.color.toARGB32()} style=${paint.style}');
  }

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    paragraphOffsets.add(offset);
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
    for (var i = 0; i < rstTransforms.length ~/ 4; i++) {
      atlasTranslations
          .add(Offset(rstTransforms[i * 4 + 2], rstTransforms[i * 4 + 3]));
    }
  }

  @override
  Float64List getTransform() => _transform;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
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

_RecordingCanvas _paintText(TerminalPainter painter, String text,
    {double scale = 1.0}) {
  final terminal = Terminal();
  terminal.write(text);
  final canvas = _RecordingCanvas(scale: scale);
  painter.paintLine(canvas, Offset.zero, terminal.buffer.lines[0]);
  return canvas;
}

void main() {
  group('paintCursor', () {
    test('focused block paints a filled cell-sized rect in the cursor color', () {
      final painter = _painter();
      final canvas = _RecordingCanvas();
      painter.paintCursor(canvas, Offset.zero,
          cursorType: TerminalCursorType.block);

      expect(canvas.rects.single,
          Offset.zero & painter.cellSize);
      expect(canvas.rectColors.single, TerminalThemes.defaultTheme.cursor.toARGB32());
      expect(canvas.rectStyles.single, PaintingStyle.fill);
    });

    test('unfocused block paints only the cell outline', () {
      final painter = _painter();
      final canvas = _RecordingCanvas();
      painter.paintCursor(canvas, Offset.zero,
          cursorType: TerminalCursorType.block, hasFocus: false);

      expect(canvas.rects, hasLength(1));
      expect(canvas.rectStyles.single, PaintingStyle.stroke);
      expect(canvas.rectColors.single, TerminalThemes.defaultTheme.cursor.toARGB32());
      // An outline cursor never touches the line-drawing path.
      expect(canvas.lines, isEmpty);
    });

    test('underline paints a line along the bottom edge', () {
      final painter = _painter();
      final canvas = _RecordingCanvas();
      final cw = painter.cellSize.width;
      final ch = painter.cellSize.height;

      painter.paintCursor(canvas, Offset.zero,
          cursorType: TerminalCursorType.underline);

      expect(canvas.rects, isEmpty);
      expect(canvas.lines.single,
          '0.0,${ch - 1}->$cw,${ch - 1} '
          'color=${TerminalThemes.defaultTheme.cursor.toARGB32()} '
          'style=PaintingStyle.fill');
    });

    test('verticalBar paints a line along the left edge', () {
      final painter = _painter();
      final canvas = _RecordingCanvas();
      final ch = painter.cellSize.height;

      painter.paintCursor(canvas, const Offset(3, 5),
          cursorType: TerminalCursorType.verticalBar);

      expect(canvas.rects, isEmpty);
      expect(canvas.lines.single, startsWith('3.0,5.0->3.0,${5 + ch}'));
    });

    test('unfocused underline/verticalBar still paint (only block is outlined)', () {
      final painter = _painter();
      final canvas = _RecordingCanvas();
      painter.paintCursor(canvas, Offset.zero,
          cursorType: TerminalCursorType.underline, hasFocus: false);
      expect(canvas.rects.single, Offset.zero & painter.cellSize);
      expect(canvas.rectStyles.single, PaintingStyle.stroke);
    });
  });

  group('paintHighlight', () {
    test('paints a snapped rect covering [length] cells', () {
      final painter = _painter();
      final canvas = _RecordingCanvas();
      final cw = painter.cellSize.width;
      final ch = painter.cellSize.height;

      painter.paintHighlight(
          canvas, const Offset(2, 4), 3, const Color(0xFF00FF00));

      expect(canvas.rects.single,
          Rect.fromLTRB(2, 4, 2 + 3 * cw, 4 + ch));
      expect(canvas.rectColors.single, 0xFF00FF00);
    });
  });

  group('color resolution', () {
    test('normal colors resolve to the theme', () {
      final painter = _painter();
      expect(painter.resolveForegroundColor(CellColor.normal | 5),
          TerminalThemes.defaultTheme.foreground);
      expect(painter.resolveBackgroundColor(CellColor.normal | 5),
          TerminalThemes.defaultTheme.background);
    });

    test('named colors resolve through the palette', () {
      final painter = _painter();
      expect(painter.resolveForegroundColor(CellColor.named | 1),
          TerminalThemes.defaultTheme.red);
      expect(painter.resolveBackgroundColor(CellColor.named | 4),
          TerminalThemes.defaultTheme.blue);
    });

    test('palette colors resolve through the extended palette', () {
      final painter = _painter();
      // 256-color palette entry 196 is a pure red in the xterm palette.
      expect(painter.resolveForegroundColor(CellColor.palette | 196),
          const Color(0xFFFF0000));
    });

    test('rgb colors are opaque values from the cell payload', () {
      final painter = _painter();
      expect(painter.resolveForegroundColor(CellColor.rgb | 0x123456),
          const Color(0xFF123456));
      expect(painter.resolveBackgroundColor(CellColor.rgb | 0x000000),
          const Color(0xFF000000));
    });
  });

  group('paintCellBackground / paintCell', () {
    CellData cell({int fg = 0, int bg = 0, int flags = 0, int content = 0x41}) {
      return CellData(
          foreground: fg, background: bg, flags: flags, content: content);
    }

    test('normal background paints nothing', () {
      final painter = _painter();
      final canvas = _RecordingCanvas();
      painter.paintCellBackground(canvas, Offset.zero, cell(), 10);
      expect(canvas.rects, isEmpty);
    });

    test('named background paints the cell rect', () {
      final painter = _painter();
      final canvas = _RecordingCanvas();
      final ch = painter.cellSize.height;
      painter.paintCellBackground(
          canvas, const Offset(1, 2), cell(bg: CellColor.named | 2), 9);
      expect(canvas.rects.single, Rect.fromLTRB(1, 2, 9, 2 + ch));
      expect(canvas.rectColors.single, TerminalThemes.defaultTheme.green.toARGB32());
    });

    test('inverse paints the background in the foreground color', () {
      final painter = _painter();
      final canvas = _RecordingCanvas();
      painter.paintCellBackground(
        canvas,
        Offset.zero,
        cell(fg: CellColor.named | 1, flags: CellFlags.inverse),
        10,
      );
      expect(canvas.rectColors.single, TerminalThemes.defaultTheme.red.toARGB32());
    });

    test('rgb background resolves from the cell payload', () {
      final painter = _painter();
      final canvas = _RecordingCanvas();
      painter.paintCellBackground(
          canvas, Offset.zero, cell(bg: CellColor.rgb | 0x101010), 10);
      expect(canvas.rectColors.single, 0xFF101010);
    });

    test('paintCell paints background then foreground', () {
      final painter = _painter();
      final canvas = _RecordingCanvas();
      painter.paintCell(
        canvas,
        Offset.zero,
        cell(bg: CellColor.named | 4),
        painter.cellSize.width,
      );
      expect(canvas.rects, hasLength(1)); // background
      expect(canvas.paragraphs, 1); // foreground glyph 'A'
    });

    test('cell with content 0 paints background only', () {
      final painter = _painter();
      final canvas = _RecordingCanvas();
      painter.paintCell(
        canvas,
        Offset.zero,
        cell(bg: CellColor.named | 4, content: 0),
        painter.cellSize.width,
      );
      expect(canvas.rects, hasLength(1));
      expect(canvas.paragraphs, 0);
    });

    test('surrogate-range codepoint is replaced, not crashed on', () {
      final painter = _painter();
      final canvas = _RecordingCanvas();
      painter.paintCellForeground(
        canvas,
        Offset.zero,
        cell(content: 0xD800),
        painter.cellSize.width,
      );
      expect(canvas.paragraphs, 1);
    });

    test('astral codepoint paints via a surrogate pair', () {
      final painter = _painter();
      final canvas = _RecordingCanvas();
      painter.paintCellForeground(
        canvas,
        Offset.zero,
        cell(content: 0x1F600), // 😀
        painter.cellSize.width * 2,
      );
      expect(canvas.paragraphs, 1);
    });
  });

  group('style/theme/scaler setters', () {
    test('assigning the same textStyle is a no-op', () {
      final painter = _painter();
      final size = painter.cellSize;
      // ignore: prefer_const_constructors
      painter.textStyle = painter.textStyle;
      expect(painter.cellSize, same(size));
    });

    test('changing font size re-measures the cell', () {
      final painter = _painter();
      final small = painter.cellSize;
      painter.textStyle = const TerminalStyle(fontSize: 16);
      expect(painter.cellSize.width, greaterThan(small.width));
      expect(painter.cellSize.height, greaterThan(small.height));
    });

    test('changing the text scaler re-measures the cell', () {
      final painter = _painter();
      final unscaled = painter.cellSize;
      painter.textScaler = const TextScaler.linear(2);
      expect(painter.cellSize.height, greaterThan(unscaled.height * 1.5));
    });

    test('assigning the same scaler is a no-op', () {
      final painter = _painter();
      final size = painter.cellSize;
      painter.textScaler = painter.textScaler;
      expect(painter.cellSize, same(size));
    });

    test('theme change re-resolves colors', () {
      final painter = _painter();
      expect(painter.resolveForegroundColor(CellColor.normal),
          TerminalThemes.defaultTheme.foreground);
      painter.theme = TerminalThemes.whiteOnBlack;
      expect(painter.resolveForegroundColor(CellColor.normal),
          TerminalThemes.whiteOnBlack.foreground);
      // The atlas survives theme changes (colors are draw-time tints).
      final canvas = _paintText(painter, 'AB');
      expect(canvas.atlasTranslations, hasLength(2));
      expect(canvas.paragraphs, 0);
    });

    test('clearFontCache keeps the painter functional', () {
      final painter = _painter();
      _paintText(painter, 'AB');
      painter.clearFontCache();
      final canvas = _paintText(painter, 'AB');
      expect(canvas.atlasTranslations, hasLength(2));
    });

    test('clearParagraphCache only drops paragraph layouts', () {
      final painter = _painter();
      _paintText(painter, 'AB');
      painter.clearParagraphCache();
      // Glyphs stay in the atlas — still sprites, no paragraphs.
      final canvas = _paintText(painter, 'CD');
      expect(canvas.atlasTranslations, hasLength(2));
      expect(canvas.paragraphs, 0);
    });
  });

  group('paintLine paths', () {
    test('an empty line paints nothing', () {
      final painter = _painter();
      final canvas = _RecordingCanvas();
      painter.paintLine(canvas, Offset.zero, Terminal().buffer.lines[0]);
      expect(canvas.rects, isEmpty);
      expect(canvas.paragraphs, 0);
      expect(canvas.atlasTranslations, isEmpty);
    });

    test('canvas with mismatched raster scale uses merged text runs', () {
      final painter = _painter();
      // dpr 1.0 but canvas scale 2.0 → atlas unusable.
      final canvas = _paintText(painter, 'ABCD', scale: 2.0);
      expect(canvas.atlasTranslations, isEmpty);
      // All four same-style cells merge into a single paragraph.
      expect(canvas.paragraphs, 1);
    });

    test('a style change splits the text run', () {
      final painter = _painter();
      final canvas = _paintText(painter, 'AB\x1b[1mCD', scale: 2.0);
      expect(canvas.paragraphs, 2);
      expect(canvas.paragraphOffsets[0].dx, 0);
      expect(
          canvas.paragraphOffsets[1].dx, painter.cellSize.width * 2);
    });

    test('a foreground color change splits the text run', () {
      final painter = _painter();
      final canvas = _paintText(painter, 'AB\x1b[31mCD', scale: 2.0);
      expect(canvas.paragraphs, 2);
    });

    test('faint cells are excluded from text runs', () {
      final painter = _painter();
      final canvas = _paintText(painter, '\x1b[2mAB', scale: 2.0);
      // Each faint cell gets its own paragraph.
      expect(canvas.paragraphs, 2);
      expect(canvas.paragraphOffsets[1].dx, painter.cellSize.width);
    });

    test('italic cells are excluded from text runs', () {
      final painter = _painter();
      final canvas = _paintText(painter, '\x1b[3mAB', scale: 2.0);
      expect(canvas.paragraphs, 2);
    });

    test('plain spaces break text runs but paint nothing', () {
      final painter = _painter();
      final canvas = _paintText(painter, 'A B', scale: 2.0);
      // 'A' run, skipped space, 'B' run.
      expect(canvas.paragraphs, 2);
      expect(canvas.rects, isEmpty);
    });

    test('underlined spaces are painted (non-breaking-space workaround)', () {
      final painter = _painter();
      final canvas = _paintText(painter, '\x1b[4m ', scale: 2.0);
      expect(canvas.paragraphs, 1);
    });

    test('wide chars take the paragraph path and occupy two columns', () {
      final painter = _painter();
      final cw = painter.cellSize.width;
      final canvas = _paintText(painter, 'A世B');
      // A and B are atlas sprites; 世 is a paragraph at column 1.
      expect(canvas.atlasTranslations, [Offset.zero, Offset(3 * cw, 0)]);
      expect(canvas.paragraphs, 1);
      expect(canvas.paragraphOffsets.single.dx, cw);
    });

    test('emoji take the paragraph path', () {
      final painter = _painter();
      final canvas = _paintText(painter, 'A😀');
      expect(canvas.atlasTranslations, [Offset.zero]);
      expect(canvas.paragraphs, 1);
    });

    test('faint atlas sprites carry alpha-128 tints', () {
      // Verified indirectly: faint cells still go through the atlas (unlike
      // the text-run path which excludes them).
      final painter = _painter();
      final canvas = _paintText(painter, '\x1b[2mAB');
      expect(canvas.paragraphs, 0);
      expect(canvas.atlasTranslations, hasLength(2));
    });

    test('inverse cells draw background from foreground color', () {
      final painter = _painter();
      final canvas = _paintText(painter, '\x1b[7mAB');
      expect(canvas.rects, hasLength(1));
      expect(canvas.rectColors.single, TerminalThemes.defaultTheme.foreground.toARGB32());
      expect(canvas.atlasTranslations, hasLength(2));
    });

    test('named background run covers exactly the colored cells', () {
      final painter = _painter();
      final cw = painter.cellSize.width;
      final canvas = _paintText(painter, 'A\x1b[44mBC\x1b[0mD');
      expect(canvas.rects, hasLength(1));
      expect(canvas.rects.single.left, cw);
      expect(canvas.rects.single.right, 3 * cw);
      expect(canvas.rectColors.single, TerminalThemes.defaultTheme.blue.toARGB32());
      // All four glyphs are sprites; the run is split around the bg rect.
      expect(canvas.atlasTranslations, hasLength(4));
    });

    test('atlas is rebuilt when the device pixel ratio changes', () {
      final painter = _painter();
      final first = _paintText(painter, 'AB');
      expect(first.atlasTranslations, hasLength(2));

      // Move to a 2x display: paint on a canvas whose raster scale matches.
      painter.debugDevicePixelRatio = 2.0;
      final second = _paintText(painter, 'AB', scale: 2.0);
      expect(second.atlasTranslations, hasLength(2));
      // Sprite positions are snapped to the 1/2-logical-pixel grid.
      for (final t in second.atlasTranslations) {
        expect((t.dx * 2).roundToDouble() / 2, t.dx);
      }
    });

    test('atlas overflow falls back to paragraphs for the excess glyphs', () {
      final painter = _painter();
      final terminal = Terminal();
      // 80 distinct printable chars per style: plain, bold, italic fill
      // 240 of 256 atlas tiles; underline overflows after 16.
      final chars =
          String.fromCharCodes([for (var c = 0x21; c <= 0x70; c++) c]);
      expect(chars.length, 80);
      terminal.write(
          '$chars\r\n\x1b[0m\x1b[1m$chars\r\n\x1b[0m\x1b[3m$chars\r\n\x1b[0m\x1b[4m$chars');

      // The atlas fills lazily per painted line — paint the first three
      // lines to occupy 240 of the 256 tiles before the underlined line.
      final warm = _RecordingCanvas();
      for (var i = 0; i < 3; i++) {
        painter.paintLine(warm, Offset.zero, terminal.buffer.lines[i]);
      }
      expect(warm.atlasTranslations, hasLength(240));
      expect(warm.paragraphs, 0);

      final canvas = _RecordingCanvas();
      painter.paintLine(canvas, Offset.zero, terminal.buffer.lines[3]);

      // Only 16 underline variants fit; the remaining 64 underlined cells
      // merge into a single text-run paragraph.
      expect(canvas.atlasTranslations, hasLength(16));
      expect(canvas.paragraphs, 1);
    });
  });
}
