import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/src/ui/painter.dart';
import 'package:yoxterm/xterm.dart';

import '../../_fixture/_fixture.dart';

/// Counts picture replays vs raw canvas ops, so tests can assert that a
/// cached line is re-emitted with a single [Canvas.drawPicture] call instead
/// of re-walking its recorded ops from Dart.
class _PictureCountingCanvas implements Canvas {
  var pictures = 0;
  var rects = 0;
  var paragraphs = 0;
  var atlasCalls = 0;

  @override
  void drawPicture(Picture picture) => pictures++;

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
  }

  @override
  Float64List getTransform() => Matrix4.identity().storage;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TerminalPainter buildPainter() {
    final painter = TerminalPainter(
      theme: TerminalThemes.defaultTheme,
      textStyle: const TerminalStyle(fontSize: 13),
      textScaler: TextScaler.noScaling,
    );
    painter.debugDevicePixelRatio = 1.0;
    return painter;
  }

  test('unchanged line replays as a single drawPicture', () {
    final terminal = Terminal();
    terminal.write(TestFixtures.htop_80x25_3s());
    final painter = buildPainter();
    final lines = terminal.buffer.lines;

    // Frame 1: build every line (through the picture path). The render loop
    // always runs the glyph discovery pass first; without it the first build
    // would discover glyphs mid-line and discard those pictures (safety
    // against mid-build atlas rebuilds).
    final built = _PictureCountingCanvas();
    painter.prepareLineGlyphs(built, lines, 0, lines.length - 1);
    for (var li = 0; li < lines.length; li++) {
      painter.paintLine(built, Offset(0, li * 16.0), lines[li]);
    }
    expect(painter.debugLineBuildCount, lines.length);
    // The build pass emits the raw ops (the op list stays authoritative);
    // it is the replay that must collapse to one drawPicture per line.
    expect(built.pictures, 0);
    expect(built.rects + built.paragraphs + built.atlasCalls, greaterThan(0));

    // Frame 2, same offsets: pure replay — one drawPicture per line, zero
    // raw canvas ops from Dart.
    final replayed = _PictureCountingCanvas();
    painter.debugLineBuildCount = 0;
    for (var li = 0; li < lines.length; li++) {
      painter.paintLine(replayed, Offset(0, li * 16.0), lines[li]);
    }
    expect(painter.debugLineBuildCount, 0,
        reason: 'unchanged lines must not rebuild');
    expect(replayed.pictures, lines.length);
    expect(replayed.rects + replayed.paragraphs + replayed.atlasCalls, 0,
        reason: 'replay must not re-walk ops from Dart');
  });

  test('vertical scroll reuses the cached picture via translation', () {
    final terminal = Terminal();
    terminal.write(TestFixtures.htop_80x25_3s());
    final painter = buildPainter();
    final lines = terminal.buffer.lines;

    final warm = _PictureCountingCanvas();
    painter.prepareLineGlyphs(warm, lines, 0, lines.length - 1);
    for (var li = 0; li < lines.length; li++) {
      painter.paintLine(warm, Offset(0, li * 16.0), lines[li]);
    }
    painter.debugLineBuildCount = 0;

    // Every line shifted vertically (scrollback scroll): same pictures, no
    // rebuilds, still one drawPicture per line.
    final scrolled = _PictureCountingCanvas();
    for (var li = 0; li < lines.length; li++) {
      painter.paintLine(scrolled, Offset(0, li * 16.0 + 32.0), lines[li]);
    }
    expect(painter.debugLineBuildCount, 0,
        reason: 'a dy shift must not rebuild the line');
    expect(scrolled.pictures, lines.length);
    expect(scrolled.rects + scrolled.paragraphs + scrolled.atlasCalls, 0);
  });

  test('a changed line rebuilds and re-records its picture', () {
    final terminal = Terminal();
    terminal.write(TestFixtures.htop_80x25_3s());
    final painter = buildPainter();
    final lines = terminal.buffer.lines;

    final warm = _PictureCountingCanvas();
    painter.prepareLineGlyphs(warm, lines, 0, lines.length - 1);
    for (var li = 0; li < lines.length; li++) {
      painter.paintLine(warm, Offset(0, li * 16.0), lines[li]);
    }

    // Damage with a glyph the warm atlas already serves, so the rebuild
    // records a picture instead of discarding it on a mid-build atlas growth.
    lines[5].setCell(70, 0x30 /* '0' */, 1, CursorStyle.empty);
    painter.debugLineBuildCount = 0;
    final canvas = _PictureCountingCanvas();
    painter.paintLine(canvas, Offset(0, 5 * 16.0), lines[5]);
    expect(painter.debugLineBuildCount, 1);
    // The rebuild re-records the line's picture: the next unchanged paint
    // replays it as a single drawPicture.
    final repainted = _PictureCountingCanvas();
    painter.paintLine(repainted, Offset(0, 5 * 16.0), lines[5]);
    expect(painter.debugLineBuildCount, 1);
    expect(repainted.pictures, 1);
    expect(repainted.rects + repainted.paragraphs + repainted.atlasCalls, 0);
  });

  test('a horizontal offset change falls back to exact op replay', () {
    final terminal = Terminal();
    terminal.write(TestFixtures.htop_80x25_3s());
    final painter = buildPainter();
    final lines = terminal.buffer.lines;

    final warm = _PictureCountingCanvas();
    painter.prepareLineGlyphs(warm, lines, 0, lines.length - 1);
    for (var li = 0; li < lines.length; li++) {
      painter.paintLine(warm, Offset(0, li * 16.0), lines[li]);
    }
    painter.debugLineBuildCount = 0;

    // A different dx (board pan) cannot reuse the baked picture without
    // subpixel drift; the painter must fall back to the op replay with
    // re-snapped coordinates instead of rebuilding.
    final shifted = _PictureCountingCanvas();
    for (var li = 0; li < lines.length; li++) {
      painter.paintLine(shifted, Offset(1.5, li * 16.0), lines[li]);
    }
    expect(painter.debugLineBuildCount, 0,
        reason: 'dx shift replays ops, it does not rebuild');
    expect(shifted.pictures, 0);
    expect(shifted.rects + shifted.atlasCalls, greaterThan(0),
        reason: 'the fallback path emits the recorded ops');
  });

  test('line pictures are disposed when the cache is invalidated', () {
    final terminal = Terminal();
    terminal.write(TestFixtures.htop_80x25_3s());
    final painter = buildPainter();
    final lines = terminal.buffer.lines;

    final warm = _PictureCountingCanvas();
    painter.prepareLineGlyphs(warm, lines, 0, lines.length - 1);
    for (var li = 0; li < lines.length; li++) {
      painter.paintLine(warm, Offset(0, li * 16.0), lines[li]);
    }
    expect(painter.debugLivePictureCount, lines.length,
        reason: 'every cached line holds exactly one live picture');

    // Theme change clears the whole cache — pictures must not leak.
    painter.theme = TerminalThemes.whiteOnBlack;
    expect(painter.debugLivePictureCount, 0);
  });

  test('glyph discovery skips lines whose paint cache is still valid', () {
    final terminal = Terminal();
    terminal.write(TestFixtures.htop_80x25_3s());
    final painter = buildPainter();
    final lines = terminal.buffer.lines;
    final last = lines.length - 1;

    // Frame 1: nothing is cached yet, the discovery pass must scan every
    // line (and batch the atlas rebuild).
    final canvas = _PictureCountingCanvas();
    painter.prepareLineGlyphs(canvas, lines, 0, last);
    expect(painter.debugGlyphScanCount, lines.length);
    for (var li = 0; li <= last; li++) {
      painter.paintLine(canvas, Offset(0, li * 16.0), lines[li]);
    }

    // Frame 2: only one line changed. The discovery pass must scan that
    // single line, not the whole viewport — valid cache entries prove their
    // glyphs are already in the (monotonically growing) atlas.
    // Damage with a glyph the warm atlas already serves.
    lines[7].setCell(70, 0x30 /* '0' */, 1, CursorStyle.empty);
    final rebuildsBefore = painter.debugAtlasRebuildCount;
    painter.debugGlyphScanCount = 0;
    painter.prepareLineGlyphs(canvas, lines, 0, last);
    expect(painter.debugGlyphScanCount, 1);
    for (var li = 0; li <= last; li++) {
      painter.paintLine(canvas, Offset(0, li * 16.0), lines[li]);
    }
    expect(painter.debugAtlasRebuildCount, rebuildsBefore,
        reason: 'no new glyphs appeared, so the atlas must not rebuild');
  });
}
