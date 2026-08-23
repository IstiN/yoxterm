import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:yoxterm/src/core/buffer/cell_flags.dart';
import 'package:yoxterm/src/ui/terminal_text_style.dart';

/// A lazily filled atlas of pre-rasterized glyph tiles.
///
/// Each tile holds a single glyph rendered WHITE through the same
/// [ParagraphBuilder] pipeline the paragraph paint path uses, so tiles are
/// pixel-identical to single-cell paragraphs. The terminal foreground color
/// is applied at draw time as a tint (`BlendMode.modulate` in
/// `Canvas.drawRawAtlas`), which is why theme changes must NOT invalidate the
/// atlas — only font-affecting changes do ([disposeAndClear]).
///
/// Tiles are [cellSize] * [devicePixelRatio] physical pixels, so drawing a
/// tile back with an RSTransform scale of 1/dpr maps texels 1:1 onto physical
/// pixels whenever the target position is snapped to the dpr grid (see
/// `TerminalPainter._snap`), giving exact sampling with any filter quality.
///
/// Packing is a fixed grid (all tiles share the same size), [capacity] tiles
/// in [columns] columns. When the atlas is full, lookups for unknown glyphs
/// keep returning -1 and the caller falls back to the paragraph path — the
/// atlas is an accelerator, never a requirement.
class GlyphAtlas {
  GlyphAtlas({
    required TerminalStyle textStyle,
    required TextScaler textScaler,
    required Size cellSize,
    required double devicePixelRatio,
    this.capacity = 256,
    this.columns = 16,
  })  : _textStyle = textStyle,
        _textScaler = textScaler,
        _cellSize = cellSize,
        devicePixelRatio = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio {
    _tileWidthPx = (_cellSize.width * this.devicePixelRatio).ceil();
    _tileHeightPx = (_cellSize.height * this.devicePixelRatio).ceil();
    _tileRects = Float32List(capacity * 4);
    for (var i = 0; i < capacity; i++) {
      final col = i % columns;
      final row = i ~/ columns;
      final o = i * 4;
      _tileRects[o] = (col * _tileWidthPx).toDouble();
      _tileRects[o + 1] = (row * _tileHeightPx).toDouble();
      _tileRects[o + 2] = ((col + 1) * _tileWidthPx).toDouble();
      _tileRects[o + 3] = ((row + 1) * _tileHeightPx).toDouble();
    }
  }

  /// Maximum number of glyph variants this atlas can hold.
  final int capacity;

  /// Number of tile columns in the atlas grid.
  final int columns;

  /// The device pixel ratio the tiles were rasterized for. When the view's
  /// dpr changes (window moved to another monitor), the atlas must be
  /// rebuilt.
  final double devicePixelRatio;

  final TerminalStyle _textStyle;
  final TextScaler _textScaler;
  final Size _cellSize;

  late final int _tileWidthPx;
  late final int _tileHeightPx;

  /// Texel-space rect (l, t, r, b) of every tile, indexed by tile * 4.
  late final Float32List _tileRects;

  /// Fast lookup for codepoints < 128 (the hot ASCII path): index is
  /// (codepoint << 3) | styleBits, value is tile + 1 (0 = not in atlas).
  final _asciiTiles = Int32List(128 * 8);

  /// Lookup for codepoints >= 128 (rare; never queried by the painter).
  final _otherTiles = <int, int>{};

  /// White paragraphs per glyph key, kept so a rebuild after adding a glyph
  /// does not re-layout the glyphs the atlas already had.
  final _paragraphs = <int, ui.Paragraph>{};

  ui.Image? _image;
  var _tileCount = 0;

  /// The current atlas image, or null when no glyph has been rasterized yet.
  ui.Image? get image => _image;

  /// Number of tiles currently assigned.
  int get tileCount => _tileCount;

  /// Whether the atlas can no longer take new glyph variants.
  bool get isFull => _tileCount >= capacity;

  /// Texel-space rect (l, t, r, b) of every tile, indexed by tile * 4.
  Float32List get tileRects => _tileRects;

  /// Encodes the glyph variant key: codepoint plus bold/italic/underline in
  /// bits 21..23. Color is deliberately not part of the key — it is applied
  /// as a tint at draw time.
  static int keyFor(int codepoint, int flags) {
    var key = codepoint;
    if (flags & CellFlags.bold != 0) key |= 1 << 21;
    if (flags & CellFlags.italic != 0) key |= 1 << 22;
    if (flags & CellFlags.underline != 0) key |= 1 << 23;
    return key;
  }

  static int _styleBitsOf(int key) => (key >> 21) & 0x7;

  /// Returns the tile index for the glyph variant, or -1 when it is not in
  /// the atlas (either never added or the atlas [isFull]).
  int tileIndex(int codepoint, int flags) {
    final styleBits = (flags & CellFlags.bold != 0 ? 1 : 0) |
        (flags & CellFlags.italic != 0 ? 2 : 0) |
        (flags & CellFlags.underline != 0 ? 4 : 0);
    if (codepoint < 128) {
      return _asciiTiles[(codepoint << 3) | styleBits] - 1;
    }
    return _otherTiles[keyFor(codepoint, flags)] ?? -1;
  }

  /// Adds every missing glyph variant in [keys] (see [keyFor]) and
  /// re-rasterizes the atlas image once. Keys beyond [capacity] are skipped;
  /// their lookups keep returning -1 so the caller falls back to paragraphs.
  void ensureAll(List<int> keys) {
    var added = false;
    for (final key in keys) {
      final codepoint = key & 0x1FFFFF;
      if (codepoint < 128) {
        final slot = (codepoint << 3) | _styleBitsOf(key);
        if (_asciiTiles[slot] != 0) continue;
        if (isFull) continue;
        _asciiTiles[slot] = ++_tileCount;
      } else {
        if (_otherTiles.containsKey(key)) continue;
        if (isFull) continue;
        _otherTiles[key] = _tileCount++;
      }
      added = true;
    }
    if (added) _rebuild();
  }

  void _rebuild() {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // Rasterize at physical resolution; drawing the tiles back with scale
    // 1/dpr then maps texels 1:1 onto device pixels.
    canvas.scale(devicePixelRatio);
    final tileLogicalWidth = _tileWidthPx / devicePixelRatio;
    final tileLogicalHeight = _tileHeightPx / devicePixelRatio;
    void drawTile(int key, int tile) {
      final paragraph = _paragraphs.putIfAbsent(key, () => _layoutGlyph(key));
      canvas.drawParagraph(
        paragraph,
        ui.Offset(
          (tile % columns) * tileLogicalWidth,
          (tile ~/ columns) * tileLogicalHeight,
        ),
      );
    }

    for (var slot = 0; slot < _asciiTiles.length; slot++) {
      final stored = _asciiTiles[slot];
      if (stored != 0) drawTile((slot >> 3) | ((slot & 0x7) << 21), stored - 1);
    }
    _otherTiles.forEach(drawTile);

    final picture = recorder.endRecording();
    final rows = (capacity + columns - 1) ~/ columns;
    final newImage = picture.toImageSync(
      columns * _tileWidthPx,
      rows * _tileHeightPx,
    );
    picture.dispose();
    _image?.dispose();
    _image = newImage;
  }

  ui.Paragraph _layoutGlyph(int key) {
    final style = _textStyle.toTextStyle(
      color: const Color(0xFFFFFFFF),
      bold: key & (1 << 21) != 0,
      italic: key & (1 << 22) != 0,
      underline: key & (1 << 23) != 0,
    );
    final builder = ui.ParagraphBuilder(style.getParagraphStyle());
    builder.pushStyle(style.getTextStyle(textScaler: _textScaler));
    builder.addText(String.fromCharCode(key & 0x1FFFFF));
    final paragraph = builder.build();
    paragraph.layout(const ui.ParagraphConstraints(width: double.infinity));
    return paragraph;
  }

  /// Drops every tile and releases the atlas image. Call when the same glyph
  /// no longer produces the same pixels: text style, text scaler, dpr or
  /// system font changes. Theme changes must NOT call this — colors are
  /// applied as draw-time tints.
  void disposeAndClear() {
    _image?.dispose();
    _image = null;
    for (final paragraph in _paragraphs.values) {
      paragraph.dispose();
    }
    _paragraphs.clear();
    _asciiTiles.fillRange(0, _asciiTiles.length, 0);
    _otherTiles.clear();
    _tileCount = 0;
  }
}
