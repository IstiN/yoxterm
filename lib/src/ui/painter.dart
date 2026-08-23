import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:xterm/src/ui/glyph_atlas.dart';
import 'package:xterm/src/ui/palette_builder.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';
import 'package:xterm/xterm.dart';

/// Encapsulates the logic for painting various terminal elements.
class TerminalPainter {
  TerminalPainter({
    required TerminalTheme theme,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
  })  : _textStyle = textStyle,
        _theme = theme,
        _textScaler = textScaler;

  /// Reusable CellData to avoid allocation per line during paint.
  final _reusableCellData = CellData.empty();

  /// Reusable StringBuffer for building merged text runs in [paintLine].
  /// Runs are consumed (toString) and the buffer is cleared before the next
  /// run/line, so a single instance can be shared across the paint pass.
  final _reusableTextRun = StringBuffer();

  /// Reusable Paint for all solid rect/line fills (background runs, cursor,
  /// highlights, box drawing, cell backgrounds). Canvas records the paint's
  /// attributes synchronously at each draw call, so mutating a single
  /// instance between calls is safe and avoids one allocation per run/cell
  /// per frame — significant for box-drawing-heavy TUIs at 60fps.
  final _fillPaint = Paint()..isAntiAlias = false;

  /// A lookup table from terminal colors to Flutter colors.
  late var _colorPalette = PaletteBuilder(_theme).build();

  /// Size of each character in the terminal.
  late var _cellSize = _measureCharSize();

  /// Returns the current device pixel ratio.
  double get _dpr =>
      debugDevicePixelRatio ??
      PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
      1.0;

  /// Overrides the device pixel ratio used for snapping and glyph-atlas
  /// rasterization. Tests use this to make [_dpr] match the raster scale of
  /// a bare `PictureRecorder` canvas (always 1.0).
  @visibleForTesting
  double? debugDevicePixelRatio;

  /// The cached for cells in the terminal. Should be cleared when the same
  /// cell no longer produces the same visual output. For example, when
  /// [_textStyle] is changed, or when the system font changes.
  final _paragraphCache = ParagraphCache(10240);

  /// Lazily created glyph atlas for mergeable ASCII cells. Null until the
  /// first [paintLine] with mergeable content, and after every invalidation
  /// (text style / text scaler / font cache / dpr change). Theme changes must
  /// NOT invalidate it: glyph tiles are white and the terminal color is
  /// applied as a draw-time tint.
  GlyphAtlas? _glyphAtlas;

  /// Reusable sprite batches for [Canvas.drawRawAtlas]. The pending batch is
  /// flushed (and the arrays reused) whenever it fills up mid-line.
  final _atlasTransforms = Float32List(512 * 4);
  final _atlasRects = Float32List(512 * 4);
  final _atlasColors = Int32List(512);

  /// Cell column of each pending atlas sprite, parallel to [_atlasColors].
  /// Only consumed when a line is recorded into [_linePaintCache].
  final _atlasSpriteCols = Int32List(512);

  /// Per-line replay cache for [paintLine]. Each entry holds the canvas ops a
  /// line produced (parameterized by cell column, not absolute coordinates),
  /// validated against [BufferLine.version] and the glyph atlas instance.
  /// Unchanged lines are replayed without re-walking their cells.
  final _linePaintCache = <BufferLine, _LinePaintCache>{};

  /// Bounds [_linePaintCache] memory. On overflow the whole map is dropped
  /// and rebuilt from misses — only visible lines are painted per frame, so
  /// the steady-state size stays far below this.
  static const _maxLinePaintCacheEntries = 1024;

  /// Number of lines rebuilt (cache miss) in [paintLine] since this counter
  /// was last reset. Tests use it to assert repaint work scales with the
  /// number of changed lines, not with the number of visible lines.
  @visibleForTesting
  int debugLineBuildCount = 0;

  /// Paint used for atlas sprite batches. Bilinear sampling is exact for the
  /// dpr-snapped 1:1 texel mapping and smoother for fractional positions.
  final _atlasPaint = Paint()..filterQuality = FilterQuality.low;

  /// Scratch list of glyph keys to add to the atlas, reused across lines.
  final _atlasMissingKeys = <int>[];

  TerminalStyle get textStyle => _textStyle;
  TerminalStyle _textStyle;
  set textStyle(TerminalStyle value) {
    if (value == _textStyle) return;
    _textStyle = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _invalidateGlyphAtlas();
  }

  TextScaler get textScaler => _textScaler;
  TextScaler _textScaler = TextScaler.linear(1.0);
  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _invalidateGlyphAtlas();
  }

  TerminalTheme get theme => _theme;
  TerminalTheme _theme;
  set theme(TerminalTheme value) {
    if (value == _theme) return;
    _theme = value;
    _colorPalette = PaletteBuilder(value).build();
    _paragraphCache.clear();
    // Colors are baked into recorded line ops, so the replay cache must go.
    _linePaintCache.clear();
  }

  Size _measureCharSize() {
    const test = 'mmmmmmmmmm';

    final textStyle = _textStyle.toTextStyle();
    final builder = ParagraphBuilder(textStyle.getParagraphStyle());
    builder.pushStyle(
      textStyle.getTextStyle(textScaler: _textScaler),
    );
    builder.addText(test);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    final result = Size(
      paragraph.maxIntrinsicWidth / test.length,
      paragraph.height,
    );

    paragraph.dispose();
    return result;
  }

  /// The size of each character in the terminal.
  Size get cellSize => _cellSize;

  /// When the set of font available to the system changes, call this method to
  /// clear cached state related to font rendering.
  void clearFontCache() {
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _invalidateGlyphAtlas();
  }

  /// Clears only the paragraph layout cache, keeping the glyph atlas warm.
  /// This models a flood repaint in benchmarks: the text is new (every layout
  /// misses) but the glyphs themselves are already rasterized.
  void clearParagraphCache() {
    _paragraphCache.clear();
  }

  void _invalidateGlyphAtlas() {
    _glyphAtlas?.disposeAndClear();
    _glyphAtlas = null;
    // Recorded sprite ops reference atlas tiles, so the replay cache must go.
    _linePaintCache.clear();
  }

  /// Returns the atlas for the current configuration, creating it on first
  /// use and rebuilding it when the device pixel ratio changed.
  GlyphAtlas _atlas() {
    final dpr = _dpr;
    final atlas = _glyphAtlas;
    if (atlas != null && atlas.devicePixelRatio == dpr) return atlas;
    atlas?.disposeAndClear();
    return _glyphAtlas = GlyphAtlas(
      textStyle: _textStyle,
      textScaler: _textScaler,
      cellSize: _cellSize,
      devicePixelRatio: dpr,
    );
  }

  /// Whether the glyph atlas can serve [canvas]: the canvas transform must
  /// be axis-aligned and scale by exactly [_dpr], so dpr-snapped sprite
  /// positions map texels 1:1 onto output pixels.
  bool _atlasUsableOn(Canvas canvas) {
    final t = canvas.getTransform();
    return t[1] == 0 &&
        t[4] == 0 &&
        t[0] == t[5] &&
        t[0] == _dpr;
  }

  /// Pre-rasterizes every mergeable glyph variant of [line] that the atlas
  /// does not have yet, batching the additions into a single atlas rebuild.
  void _ensureLineGlyphs(GlyphAtlas atlas, BufferLine line) {
    final missing = _atlasMissingKeys..clear();
    final cellData = _reusableCellData;
    for (var i = 0; i < line.length; i++) {
      line.getCellData(i, cellData);
      final charWidth = cellData.content >> CellContent.widthShift;
      final charCode = cellData.content & CellContent.codepointMask;
      if (charWidth == 1 && charCode > 0x20 && charCode <= 0x7E) {
        if (atlas.tileIndex(charCode, cellData.flags) < 0) {
          final key = GlyphAtlas.keyFor(charCode, cellData.flags);
          if (!missing.contains(key)) missing.add(key);
        }
      }
      if (charWidth == 2) i++;
    }
    if (missing.isNotEmpty) atlas.ensureAll(missing);
  }

  /// Paints the cursor based on the current cursor type.
  void paintCursor(
    Canvas canvas,
    Offset offset, {
    required TerminalCursorType cursorType,
    bool hasFocus = true,
  }) {
    final paint = _fillPaint
      ..color = _theme.cursor
      ..strokeWidth = 1
      ..style = PaintingStyle.fill;

    if (!hasFocus) {
      paint.style = PaintingStyle.stroke;
      canvas.drawRect(offset & _cellSize, paint);
      return;
    }

    switch (cursorType) {
      case TerminalCursorType.block:
        paint.style = PaintingStyle.fill;
        canvas.drawRect(_snapRect(offset & _cellSize), paint);
        return;
      case TerminalCursorType.underline:
        return canvas.drawLine(
          _snapOffset(Offset(offset.dx, offset.dy + _cellSize.height - 1)),
          _snapOffset(
            Offset(
                offset.dx + _cellSize.width, offset.dy + _cellSize.height - 1),
          ),
          paint,
        );
      case TerminalCursorType.verticalBar:
        return canvas.drawLine(
          _snapOffset(offset),
          _snapOffset(Offset(offset.dx, offset.dy + _cellSize.height)),
          paint,
        );
    }
  }

  @pragma('vm:prefer-inline')
  void paintHighlight(Canvas canvas, Offset offset, int length, Color color) {
    final endOffset =
        offset.translate(length * _cellSize.width, _cellSize.height);

    final paint = _fillPaint
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      _snapRect(Rect.fromPoints(offset, endOffset)),
      paint,
    );
  }

  /// Paints [line] to [canvas] at [offset]. The x offset of [offset] is usually
  /// 0, and the y offset is the top of the line.
  ///
  /// Adjacent cells with the same resolved background are painted as a single
  /// rect. Mergeable foreground cells (printable ASCII, single-width) are
  /// painted as sprite batches from the glyph atlas: each cell appends an
  /// RSTransform + tint color to reusable typed arrays, and the pending batch
  /// is flushed with a single [Canvas.drawRawAtlas] right after the
  /// background rect that covers it (and before any inline cell foreground),
  /// and at end of line. This preserves the per-cell draw order (bg(i),
  /// fg(i), bg(i+1), fg(i+1)…, so the next cell's background still covers
  /// the previous glyph's right-edge antialiasing bleed) while collapsing
  /// dozens of drawParagraph calls into ~1 GPU draw call per line. Glyph
  /// layout happens once per glyph variant, not once per unique line, so
  /// flood frames with all-new text no longer pay for Paragraph.layout.
  ///
  /// Cells the atlas cannot serve (overflow beyond its capacity, or a canvas
  /// whose raster scale doesn't match the dpr — widget-test captures, board
  /// zoom) fall back to the merged text-run path: adjacent printable ASCII
  /// cells with equal style are painted as a single paragraph. Faint and italic cells are
  /// excluded from text runs (their alpha/skew rasterizes a couple of levels
  /// differently in a multi-glyph run) but ARE served by the atlas, whose
  /// tiles are single-glyph paragraphs — pixel-identical to the per-cell
  /// path. Emoji, wide chars and other non-ASCII cells keep the per-cell
  /// paragraph path; box-drawing chars use primitives.
  void paintLine(
    Canvas canvas,
    Offset offset,
    BufferLine line,
  ) {
    // The atlas is only usable when the canvas raster scale matches the dpr
    // the tiles are (re)built for — otherwise snapped sprite positions no
    // longer land on texel boundaries and sampling would blur compared to
    // the paragraph path. In particular widget tests capture at 1x while
    // the implicit view reports a higher dpr, and board zoom applies a
    // scale on top of the dpr; both fall back to the paragraph path.
    final atlas = _atlasUsableOn(canvas) ? _atlas() : null;

    // Replay the ops recorded for this line when neither the line content
    // ([BufferLine.version]) nor the atlas configuration changed. Replay
    // recomputes snapped coordinates from [offset], so the emitted canvas
    // calls are identical to a fresh build. When [offset] itself is unchanged
    // (the common idle/partial-damage frame) the baked coordinates recorded
    // at build time are reused verbatim, skipping even the snapping math.
    final version = line.version;
    final cached = _linePaintCache[line];
    if (cached != null &&
        cached.version == version &&
        identical(cached.atlas, atlas)) {
      _replayLine(canvas, offset, _snap(offset.dy), cached);
      return;
    }
    debugLineBuildCount++;
    final ops = <_LinePaintOp>[];
    _buildLine(canvas, offset, line, atlas, ops);
    if (_linePaintCache.length >= _maxLinePaintCacheEntries) {
      _linePaintCache.clear();
    }
    _linePaintCache[line] = _LinePaintCache(version, offset, atlas, ops);
  }

  /// Replays the ops recorded by [_buildLine] for an unchanged line.
  void _replayLine(
    Canvas canvas,
    Offset offset,
    double snappedY,
    _LinePaintCache cache,
  ) {
    final cellWidth = _cellSize.width;
    final atlas = cache.atlas;
    // When the line is painted at the same offset it was recorded at, every
    // snapped coordinate is identical — replay the baked geometry directly.
    final sameOffset = offset == cache.offset;
    for (final op in cache.ops) {
      switch (op) {
        case _BgRectOp():
          canvas.drawRect(
            sameOffset
                ? op.rect
                : Rect.fromLTRB(
                    _snap(offset.dx + op.startCol * cellWidth),
                    snappedY,
                    _snap(offset.dx + op.endCol * cellWidth),
                    snappedY + _cellSize.height,
                  ),
            _fillPaint
              ..color = Color(op.colorArgb)
              ..style = PaintingStyle.fill,
          );
        case _SpriteBatchOp():
          final count = op.cols.length;
          var transforms = op.transforms;
          if (!sameOffset) {
            final atlasScale = 1.0 / atlas!.devicePixelRatio;
            for (var s = 0; s < count; s++) {
              final o = s * 4;
              _atlasTransforms[o] = atlasScale;
              _atlasTransforms[o + 1] = 0;
              _atlasTransforms[o + 2] =
                  _snap(offset.dx + op.cols[s] * cellWidth);
              _atlasTransforms[o + 3] = snappedY;
            }
            transforms =
                Float32List.sublistView(_atlasTransforms, 0, count * 4);
          }
          canvas.drawRawAtlas(
            atlas!.image!,
            transforms,
            op.rects,
            op.colors,
            BlendMode.modulate,
            null,
            _atlasPaint,
          );
        case _TextRunOp():
          _paintTextRun(
            canvas,
            sameOffset
                ? op.offset
                : Offset(_snap(offset.dx + op.startCol * cellWidth), snappedY),
            op.text,
            op.flags,
            op.foreground,
            op.background,
          );
        case _CellOp():
          final cellData = _reusableCellData
            ..foreground = op.foreground
            ..background = op.background
            ..flags = op.flags
            ..content = op.content;
          final left =
              sameOffset ? op.left : _snap(offset.dx + op.col * cellWidth);
          final right = sameOffset
              ? op.right
              : _snap(offset.dx + (op.col + op.effectiveCols) * cellWidth);
          paintCellForeground(canvas, Offset(left, snappedY), cellData, right);
      }
    }
  }

  /// Builds [line]'s sprite batches and paints them to [canvas] at [offset],
  /// recording every emitted canvas call into [ops] for later replay.
  void _buildLine(
    Canvas canvas,
    Offset offset,
    BufferLine line,
    GlyphAtlas? atlas,
    List<_LinePaintOp> ops,
  ) {
    final cellData = _reusableCellData;
    final cellWidth = _cellSize.width;
    final snappedY = _snap(offset.dy);
    final atlasScale = atlas == null ? 0.0 : 1.0 / atlas.devicePixelRatio;

    var spriteCount = 0;

    // Flushes the pending sprite batch with one drawRawAtlas call. Mid-line
    // flushes only happen at points where the per-cell path would draw too
    // (before a background rect or an inline cell foreground), so the
    // relative order of canvas ops is unchanged.
    void flushSprites() {
      if (spriteCount == 0) return;
      // Sprites only accumulate when the atlas served their tiles, so the
      // atlas and its image are non-null here.
      ops.add(
        _SpriteBatchOp(
          Float32List.fromList(
            Float32List.sublistView(_atlasRects, 0, spriteCount * 4),
          ),
          Int32List.fromList(Int32List.sublistView(_atlasColors, 0, spriteCount)),
          Int32List.fromList(
            Int32List.sublistView(_atlasSpriteCols, 0, spriteCount),
          ),
          Float32List.fromList(
            Float32List.sublistView(_atlasTransforms, 0, spriteCount * 4),
          ),
        ),
      );
      canvas.drawRawAtlas(
        atlas!.image!,
        Float32List.sublistView(_atlasTransforms, 0, spriteCount * 4),
        Float32List.sublistView(_atlasRects, 0, spriteCount * 4),
        Int32List.sublistView(_atlasColors, 0, spriteCount),
        BlendMode.modulate,
        null,
        _atlasPaint,
      );
      spriteCount = 0;
    }

    Color? bgRunColor;
    var bgRunStartCol = 0;

    void flushBackgroundRun(int endCol) {
      if (endCol == bgRunStartCol) return;
      final color = bgRunColor;
      if (color == null) {
        bgRunStartCol = endCol;
        return;
      }
      final paint = _fillPaint
        ..color = color
        ..style = PaintingStyle.fill;
      final rect = Rect.fromLTRB(
        _snap(offset.dx + bgRunStartCol * cellWidth),
        snappedY,
        _snap(offset.dx + endCol * cellWidth),
        snappedY + _cellSize.height,
      );
      ops.add(_BgRectOp(bgRunStartCol, endCol, color.toARGB32(), rect));
      canvas.drawRect(rect, paint);
      // This rect covers the pending sprite cells, so their glyphs go next,
      // exactly like bg-then-fg per cell in the per-cell path.
      flushSprites();
      bgRunStartCol = endCol;
    }

    final textRun = _reusableTextRun;
    // -1 = no active run (flags bitmask itself can be 0).
    var textRunFlags = -1;
    var textRunStartCol = 0;
    var textRunForeground = 0;
    var textRunBackground = 0;

    // Paints the text run covering [textRunStartCol, endCol), flushing the
    // pending background segment first (see the doc comment for why).
    void flushTextRun(int endCol) {
      if (textRunFlags < 0) return;
      flushBackgroundRun(endCol);
      final text = textRun.toString();
      final runOffset =
          Offset(_snap(offset.dx + textRunStartCol * cellWidth), snappedY);
      ops.add(
        _TextRunOp(
          textRunStartCol,
          text,
          textRunFlags,
          textRunForeground,
          textRunBackground,
          runOffset,
        ),
      );
      _paintTextRun(
        canvas,
        runOffset,
        text,
        textRunFlags,
        textRunForeground,
        textRunBackground,
      );
      textRun.clear();
      textRunFlags = -1;
    }

    for (var i = 0; i < line.length; i++) {
      line.getCellData(i, cellData);

      final charWidth = cellData.content >> CellContent.widthShift;
      final charCode = cellData.content & CellContent.codepointMask;
      final effectiveCols = charWidth == 2 ? 2 : 1;

      // Background run: break on a different resolved color.
      final bg = _resolvedCellBackground(cellData);
      if (bg != bgRunColor) {
        flushBackgroundRun(i);
        bgRunColor = bg;
      }

      // Foreground: mergeable cells (printable single-width ASCII) become
      // atlas sprites when the atlas is usable. Unlike text runs this
      // includes faint (draw-time alpha tint) and italic (single-glyph tile)
      // cells.
      final mergeable =
          charWidth == 1 && charCode > 0x20 && charCode <= 0x7E;
      var tile = -1;
      if (mergeable && atlas != null) {
        tile = atlas.tileIndex(charCode, cellData.flags);
        if (tile < 0 && !atlas.isFull) {
          _ensureLineGlyphs(atlas, line);
          tile = atlas.tileIndex(charCode, cellData.flags);
        }
      }
      if (tile >= 0) {
        flushTextRun(i);
        if (spriteCount * 4 == _atlasTransforms.length) {
          // Sprite arrays full — flush mid-line. Consecutive sprites have
          // no interleaved canvas ops, so splitting the batch is safe.
          flushSprites();
        }
        final o = spriteCount * 4;
        _atlasTransforms[o] = atlasScale;
        _atlasTransforms[o + 1] = 0;
        _atlasTransforms[o + 2] = _snap(offset.dx + i * cellWidth);
        _atlasTransforms[o + 3] = snappedY;
        final r = tile * 4;
        final tileRects = atlas!.tileRects;
        _atlasRects[o] = tileRects[r];
        _atlasRects[o + 1] = tileRects[r + 1];
        _atlasRects[o + 2] = tileRects[r + 2];
        _atlasRects[o + 3] = tileRects[r + 3];
        final flags = cellData.flags;
        var color = flags & CellFlags.inverse == 0
            ? resolveForegroundColor(cellData.foreground)
            : resolveBackgroundColor(cellData.background);
        if (flags & CellFlags.faint != 0) {
          color = color.withAlpha(128);
        }
        _atlasColors[spriteCount] = color.toARGB32();
        _atlasSpriteCols[spriteCount] = i;
        spriteCount++;
      } else if (mergeable &&
          cellData.flags & (CellFlags.faint | CellFlags.italic) == 0) {
        // Atlas unavailable (canvas raster scale mismatch) or full: merged
        // text-run path. Faint cells are excluded: their alpha-128 glyph
        // coverage rounds a couple of levels differently between a run
        // paragraph and single-cell paragraphs (subpixel AA), which golden
        // tests catch. Italic cells are excluded for the same reason:
        // synthetic-italic skew rasterizes slightly differently in a
        // multi-glyph run. Spaces are excluded too: a plain space paints
        // nothing, and keeping it out of the run lets the pending background
        // segment cover the previous glyph's right-edge AA bleed exactly
        // like the per-cell path does.
        final flags = cellData.flags;
        if (textRunFlags >= 0 &&
            flags == textRunFlags &&
            cellData.foreground == textRunForeground &&
            cellData.background == textRunBackground) {
          textRun.writeCharCode(charCode);
        } else {
          flushTextRun(i);
          textRunStartCol = i;
          textRunFlags = flags;
          textRunForeground = cellData.foreground;
          textRunBackground = cellData.background;
          textRun.writeCharCode(charCode);
        }
      } else {
        flushTextRun(i);
        // A plain space paints nothing (no glyph, no underline) — skip it
        // entirely. Its background stays in the pending bg run, which keeps
        // the per-cell draw order (next cell's bg covers the previous glyph's
        // right-edge AA bleed).
        if (charCode != 0 &&
            !(charCode == 0x20 && cellData.flags & CellFlags.underline == 0)) {
          if (spriteCount > 0) {
            // Draw the background segment covering the pending sprites,
            // then the sprites, then this cell's background — exactly the
            // per-cell order (bg, fg, next bg).
            flushBackgroundRun(i);
            flushSprites();
          }
          // Snap directly from the original offset so that cellRight(i)
          // always equals cellLeft(i+1), eliminating rounding gaps.
          final cellLeft = _snap(offset.dx + i * cellWidth);
          final cellRight = _snap(offset.dx + (i + effectiveCols) * cellWidth);
          // Paint this cell's background segment first, exactly like the
          // per-cell path does (bg then fg per cell).
          flushBackgroundRun(i + effectiveCols);
          ops.add(
            _CellOp(
              i,
              effectiveCols,
              cellData.foreground,
              cellData.background,
              cellData.flags,
              cellData.content,
              cellLeft,
              cellRight,
            ),
          );
          paintCellForeground(
            canvas,
            Offset(cellLeft, snappedY),
            cellData,
            cellRight,
          );
        }
      }

      if (charWidth == 2) {
        i++;
      }
    }

    flushTextRun(line.length);
    flushBackgroundRun(line.length);
    flushSprites();
  }

  /// Resolves the effective background color of a cell, mirroring
  /// [paintCellBackground]. Returns null when the cell shows the theme
  /// background (nothing is painted).
  Color? _resolvedCellBackground(CellData cellData) {
    if (cellData.flags & CellFlags.inverse != 0) {
      return resolveForegroundColor(cellData.foreground);
    }
    if (cellData.background & CellColor.typeMask == CellColor.normal) {
      return null;
    }
    return resolveBackgroundColor(cellData.background);
  }

  /// Paints a merged run of same-style printable ASCII cells as a single
  /// paragraph. Style resolution mirrors [paintCellForeground].
  void _paintTextRun(
    Canvas canvas,
    Offset offset,
    String text,
    int flags,
    int foreground,
    int background,
  ) {
    var color = flags & CellFlags.inverse == 0
        ? resolveForegroundColor(foreground)
        : resolveBackgroundColor(background);

    if (flags & CellFlags.faint != 0) {
      color = color.withAlpha(128);
    }

    final cacheKey = Object.hash(
      text,
      flags,
      foreground,
      background,
      _textScaler,
    );
    var paragraph = _paragraphCache.getLayoutFromCache(cacheKey);
    if (paragraph == null) {
      final style = _textStyle
          .toTextStyle(
            color: color,
            bold: flags & CellFlags.bold != 0,
            italic: flags & CellFlags.italic != 0,
            underline: flags & CellFlags.underline != 0,
          )
          // Single cells can never kern or ligate, so disable both in runs
          // to stay pixel-identical with the per-cell path.
          .copyWith(
            fontFeatures: const [
              FontFeature.disable('kern'),
              FontFeature.disable('liga'),
              FontFeature.disable('clig'),
              FontFeature.disable('calt'),
            ],
          );

      paragraph = _paragraphCache.performAndCacheLayout(
        text,
        style,
        _textScaler,
        cacheKey,
      );
    }

    canvas.drawParagraph(paragraph, offset);
  }

  @pragma('vm:prefer-inline')
  void paintCell(Canvas canvas, Offset offset, CellData cellData, double rightEdge) {
    paintCellBackground(canvas, offset, cellData, rightEdge);
    paintCellForeground(canvas, offset, cellData, rightEdge);
  }

  /// Paints the character in the cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellForeground(Canvas canvas, Offset offset, CellData cellData, double rightEdge) {
    final charCode = cellData.content & CellContent.codepointMask;
    if (charCode == 0) return;

    final cellFlags = cellData.flags;

    var color = cellFlags & CellFlags.inverse == 0
        ? resolveForegroundColor(cellData.foreground)
        : resolveBackgroundColor(cellData.background);

    if (cellData.flags & CellFlags.faint != 0) {
      // withAlpha(128) == withOpacity(0.5) but skips the double math.
      color = color.withAlpha(128);
    }

    // Use the actual snapped cell width so lines exactly meet edges.
    final actualWidth = rightEdge - offset.dx;
    final actualHeight = _cellSize.height;

    // Box-drawing characters (U+2500–U+257F) are drawn manually with Canvas
    // primitives to guarantee perfect alignment between adjacent cells,
    // regardless of font metrics.
    if (charCode >= 0x2500 && charCode <= 0x257F) {
      if (_drawBoxDrawingChar(
        canvas,
        offset,
        charCode,
        color,
        actualWidth,
        actualHeight,
      )) {
        return;
      }
    }

    final cacheKey = cellData.getHash() ^ _textScaler.hashCode;
    var paragraph = _paragraphCache.getLayoutFromCache(cacheKey);

    if (paragraph == null) {
      final style = _textStyle.toTextStyle(
        color: color,
        bold: cellFlags & CellFlags.bold != 0,
        italic: cellFlags & CellFlags.italic != 0,
        underline: cellFlags & CellFlags.underline != 0,
      );

      // Flutter does not draw an underline below a space which is not between
      // other regular characters. As only single characters are drawn, this
      // will never produce an underline below a space in the terminal. As a
      // workaround the regular space CodePoint 0x20 is replaced with
      // the CodePoint 0xA0. This is a non breaking space and a underline can be
      // drawn below it.
      var char = _charFromCodePoint(charCode);
      if (cellFlags & CellFlags.underline != 0 && charCode == 0x20) {
        char = _charFromCodePoint(0xA0);
      }

      paragraph = _paragraphCache.performAndCacheLayout(
        char,
        style,
        _textScaler,
        cacheKey,
      );
    }

    canvas.drawParagraph(paragraph, _snapOffset(offset));
  }

  /// Converts a Unicode code point to a Dart string, handling surrogate pairs
  /// for code points above U+FFFF (e.g. emoji).
  static String _charFromCodePoint(int codePoint) {
    // Surrogate code points (0xD800–0xDFFF) and values above U+10FFFF are
    // invalid in Unicode. Return the replacement character to avoid crashes.
    if (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
      return String.fromCharCode(0xFFFD);
    }
    if (codePoint > 0x10FFFF) {
      return String.fromCharCode(0xFFFD);
    }
    if (codePoint <= 0xFFFF) return String.fromCharCode(codePoint);
    codePoint -= 0x10000;
    return String.fromCharCodes([
      0xD800 + (codePoint >> 10),
      0xDC00 + (codePoint & 0x3FF),
    ]);
  }

  /// Draws a Unicode box-drawing character (U+2500–U+257F) using Canvas lines.
  /// Returns `true` if the character was handled.
  bool _drawBoxDrawingChar(
    Canvas canvas,
    Offset offset,
    int codePoint,
    Color color,
    double width,
    double height,
  ) {
    final paint = _fillPaint
      ..color = color
      ..style = PaintingStyle.fill;

    final left = offset.dx;
    final right = offset.dx + width;
    final top = offset.dy;
    final bottom = offset.dy + height;
    final midX = (offset.dx + width / 2).roundToDouble();
    final midY = (offset.dy + height / 2).roundToDouble();

    // Helper closures using drawRect for pixel-perfect 1px strokes.
    void hRect(double y, double x1, double x2) {
      final yr = y.roundToDouble();
      canvas.drawRect(Rect.fromLTRB(x1, yr, x2, yr + 1.0), paint);
    }

    void vRect(double x, double y1, double y2) {
      final xr = x.roundToDouble();
      canvas.drawRect(Rect.fromLTRB(xr, y1, xr + 1.0, y2), paint);
    }

    switch (codePoint) {
      // ─━┄┅┈┉╌╍
      case 0x2500: // ─ light horizontal
        hRect(midY, left, right);
        return true;
      case 0x2501: // ━ heavy horizontal
        hRect(midY, left, right);
        return true;
      case 0x2502: // │ light vertical
        vRect(midX, top, bottom);
        return true;
      case 0x2503: // ┃ heavy vertical
        vRect(midX, top, bottom);
        return true;

      // corners light
      case 0x250C: // ┌ down and right
        hRect(midY, midX, right);
        vRect(midX, midY, bottom);
        return true;
      case 0x2510: // ┐ down and left
        hRect(midY, left, midX);
        vRect(midX, midY, bottom);
        return true;
      case 0x2514: // └ up and right
        hRect(midY, midX, right);
        vRect(midX, top, midY);
        return true;
      case 0x2518: // ┘ up and left
        hRect(midY, left, midX);
        vRect(midX, top, midY);
        return true;

      // corners heavy
      case 0x250F: // ┏ heavy down and right
        hRect(midY, midX, right);
        vRect(midX, midY, bottom);
        return true;
      case 0x2513: // ┓ heavy down and left
        hRect(midY, left, midX);
        vRect(midX, midY, bottom);
        return true;
      case 0x2517: // ┗ heavy up and right
        hRect(midY, midX, right);
        vRect(midX, top, midY);
        return true;
      case 0x251B: // ┛ heavy up and left
        hRect(midY, left, midX);
        vRect(midX, top, midY);
        return true;

      // T-junctions light
      case 0x251C: // ├ vertical and right
        vRect(midX, top, bottom);
        hRect(midY, midX, right);
        return true;
      case 0x2524: // ┤ vertical and left
        vRect(midX, top, bottom);
        hRect(midY, left, midX);
        return true;
      case 0x252C: // ┬ down and horizontal
        hRect(midY, left, right);
        vRect(midX, midY, bottom);
        return true;
      case 0x2534: // ┴ up and horizontal
        hRect(midY, left, right);
        vRect(midX, top, midY);
        return true;
      case 0x253C: // ┼ vertical and horizontal
        hRect(midY, left, right);
        vRect(midX, top, bottom);
        return true;

      // T-junctions heavy
      case 0x2523: // ┣ heavy vertical and right
        vRect(midX, top, bottom);
        hRect(midY, midX, right);
        return true;
      case 0x252B: // ┫ heavy vertical and left
        vRect(midX, top, bottom);
        hRect(midY, left, midX);
        return true;
      case 0x2533: // ┳ heavy down and horizontal
        hRect(midY, left, right);
        vRect(midX, midY, bottom);
        return true;
      case 0x253B: // ┻ heavy up and horizontal
        hRect(midY, left, right);
        vRect(midX, top, midY);
        return true;
      case 0x254B: // ╋ heavy vertical and horizontal
        hRect(midY, left, right);
        vRect(midX, top, bottom);
        return true;

      // double
      case 0x2550: // ═ double horizontal
        hRect(midY - 0.5, left, right);
        hRect(midY + 0.5, left, right);
        return true;
      case 0x2551: // ║ double vertical
        vRect(midX - 0.5, top, bottom);
        vRect(midX + 0.5, top, bottom);
        return true;
      case 0x2554: // ╔ double down and right
        hRect(midY - 0.5, midX, right);
        hRect(midY + 0.5, midX, right);
        vRect(midX - 0.5, midY, bottom);
        vRect(midX + 0.5, midY - 0.5, bottom);
        return true;
      case 0x2557: // ╗ double down and left
        hRect(midY - 0.5, left, midX);
        hRect(midY + 0.5, left, midX);
        vRect(midX - 0.5, midY - 0.5, bottom);
        vRect(midX + 0.5, midY, bottom);
        return true;
      case 0x255A: // ╚ double up and right
        hRect(midY - 0.5, midX, right);
        hRect(midY + 0.5, midX, right);
        vRect(midX - 0.5, top, midY + 0.5);
        vRect(midX + 0.5, top, midY);
        return true;
      case 0x255D: // ╝ double up and left
        hRect(midY - 0.5, left, midX);
        hRect(midY + 0.5, left, midX);
        vRect(midX - 0.5, top, midY);
        vRect(midX + 0.5, top, midY + 0.5);
        return true;
      case 0x2560: // ╠ double vertical and right
        vRect(midX - 0.5, top, bottom);
        vRect(midX + 0.5, top, bottom);
        hRect(midY - 0.5, midX + 0.5, right);
        hRect(midY + 0.5, midX + 0.5, right);
        return true;
      case 0x2563: // ╣ double vertical and left
        vRect(midX - 0.5, top, bottom);
        vRect(midX + 0.5, top, bottom);
        hRect(midY - 0.5, left, midX - 0.5);
        hRect(midY + 0.5, left, midX - 0.5);
        return true;
      case 0x2566: // ╦ double down and horizontal
        hRect(midY - 0.5, left, right);
        hRect(midY + 0.5, left, right);
        vRect(midX - 0.5, midY + 0.5, bottom);
        vRect(midX + 0.5, midY + 0.5, bottom);
        return true;
      case 0x2569: // ╩ double up and horizontal
        hRect(midY - 0.5, left, right);
        hRect(midY + 0.5, left, right);
        vRect(midX - 0.5, top, midY - 0.5);
        vRect(midX + 0.5, top, midY - 0.5);
        return true;
      case 0x256C: // ╬ double cross
        hRect(midY - 0.5, left, right);
        hRect(midY + 0.5, left, right);
        vRect(midX - 0.5, top, bottom);
        vRect(midX + 0.5, top, bottom);
        return true;

      // rounded corners (drawn as straight lines for perfect alignment)
      case 0x256D: // ╭ light arc down and right
        hRect(midY, midX, right);
        vRect(midX, midY, bottom);
        return true;
      case 0x256E: // ╮ light arc down and left
        hRect(midY, left, midX);
        vRect(midX, midY, bottom);
        return true;
      case 0x256F: // ╯ light arc up and left
        hRect(midY, left, midX);
        vRect(midX, top, midY);
        return true;
      case 0x2570: // ╰ light arc up and right
        hRect(midY, midX, right);
        vRect(midX, top, midY);
        return true;

      default:
        return false;
    }
  }

  /// Paints the background of a cell represented by [cellData] to [canvas] at
  /// [offset]. [rightEdge] is the pre-snapped x coordinate of the cell's right
  /// boundary, ensuring adjacent cells share the same edge without overlap or
  /// gaps.
  @pragma('vm:prefer-inline')
  void paintCellBackground(Canvas canvas, Offset offset, CellData cellData, double rightEdge) {
    late Color color;
    final colorType = cellData.background & CellColor.typeMask;

    if (cellData.flags & CellFlags.inverse != 0) {
      color = resolveForegroundColor(cellData.foreground);
    } else if (colorType == CellColor.normal) {
      return;
    } else {
      color = resolveBackgroundColor(cellData.background);
    }

    final paint = _fillPaint
      ..color = color
      ..style = PaintingStyle.fill;
    final y1 = offset.dy + _cellSize.height;
    canvas.drawRect(Rect.fromLTRB(offset.dx, offset.dy, rightEdge, y1), paint);
  }

  double _snap(double value) {
    if (_dpr <= 0) return value;
    return (value * _dpr).roundToDouble() / _dpr;
  }

  Offset _snapOffset(Offset offset) =>
      Offset(_snap(offset.dx), _snap(offset.dy));

  Rect _snapRect(Rect rect) => Rect.fromLTRB(
        _snap(rect.left),
        _snap(rect.top),
        _snap(rect.right),
        _snap(rect.bottom),
      );

  /// Get the effective foreground color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveForegroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.foreground;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }

  /// Get the effective background color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveBackgroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.background;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }
}

/// A canvas operation recorded by [TerminalPainter.paintLine], parameterized
/// by cell column rather than absolute coordinates so it can be replayed at
/// any line offset with freshly snapped coordinates. Replaying a line's op
/// list emits exactly the same canvas calls as rebuilding it.
sealed class _LinePaintOp {
  const _LinePaintOp();
}

/// A merged background rect covering columns [startCol]..[endCol] filled with
/// [colorArgb]. [rect] is the baked, snapped geometry from recording time,
/// reused verbatim when the line is replayed at the same offset.
final class _BgRectOp extends _LinePaintOp {
  const _BgRectOp(this.startCol, this.endCol, this.colorArgb, this.rect);

  final int startCol;
  final int endCol;
  final int colorArgb;
  final Rect rect;
}

/// A flushed [Canvas.drawRawAtlas] batch. [rects] are the baked texel rects
/// and [transforms] the baked RSTransforms (both stable for the atlas
/// instance and offset the batch was recorded against), [colors] the
/// per-sprite tint, and [cols] the cell column of each sprite — used to
/// recompute snapped positions when replaying at a different offset.
final class _SpriteBatchOp extends _LinePaintOp {
  const _SpriteBatchOp(this.rects, this.colors, this.cols, this.transforms);

  final Float32List rects;
  final Int32List colors;
  final Int32List cols;
  final Float32List transforms;
}

/// A merged run of same-style printable cells painted as a single paragraph.
/// [offset] is the baked draw offset from recording time.
final class _TextRunOp extends _LinePaintOp {
  const _TextRunOp(
    this.startCol,
    this.text,
    this.flags,
    this.foreground,
    this.background,
    this.offset,
  );

  final int startCol;
  final String text;
  final int flags;
  final int foreground;
  final int background;
  final Offset offset;
}

/// A cell painted individually (emoji, wide chars, box drawing, or a
/// faint/italic cell when the atlas is unavailable) — replayed via
/// [TerminalPainter.paintCellForeground]. [left] and [right] are the baked,
/// snapped horizontal edges from recording time.
final class _CellOp extends _LinePaintOp {
  const _CellOp(
    this.col,
    this.effectiveCols,
    this.foreground,
    this.background,
    this.flags,
    this.content,
    this.left,
    this.right,
  );

  final int col;
  final int effectiveCols;
  final int foreground;
  final int background;
  final int flags;
  final int content;
  final double left;
  final double right;
}

/// The recorded op list of one [BufferLine], valid only for the [BufferLine]
/// [version] and [GlyphAtlas] instance it was built with. [offset] is the
/// paint offset the ops were recorded at; replaying at the same offset reuses
/// the baked geometry verbatim.
final class _LinePaintCache {
  const _LinePaintCache(this.version, this.offset, this.atlas, this.ops);

  final int version;
  final Offset offset;
  final GlyphAtlas? atlas;
  final List<_LinePaintOp> ops;
}
