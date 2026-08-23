import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/src/ui/painter.dart';
import 'package:yoxterm/xterm.dart';

import '../../_fixture/_fixture.dart';

/// Time-based throughput benchmark for the terminal hot paths. Complements
/// draw_ops_bench_test.dart (which counts canvas ops) with wall-clock numbers
/// so regressions show up as numbers, not just op counts. Prints only — no
/// timing assertions, to stay stable on loaded CI machines.
void main() {
  test('perf benchmark: parse + paint throughput', () {
    // ── 1. Parse throughput (flood-style plain lines) ──────────────────────
    const line =
        'The quick brown fox jumps over the lazy dog 0123456789 !@#\$%^&*()\r\n';
    final chunk = line * 100;
    const iterations = 300; // 30k lines ≈ 2.2 MB

    var terminal = Terminal(maxLines: 1000);
    final parseSw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      terminal.write(chunk);
    }
    parseSw.stop();

    final totalMb = (chunk.length * iterations) / (1024 * 1024);
    final parseSeconds = parseSw.elapsedMicroseconds / 1e6;
    // ignore: avoid_print
    print(
      'parse flood: ${(totalMb / parseSeconds).toStringAsFixed(1)} MB/s, '
      '${(parseSw.elapsedMicroseconds / (iterations * 100)).toStringAsFixed(2)} µs/line '
      '(incl. scrollback recycling)',
    );

    // ── 1b. Parser bypass fast path: plain-text flood without any control
    // characters. Terminal.write now skips the parser for such chunks; the
    // EscapeParser-driven terminal below is the pre-change baseline.
    const plainLine =
        'The quick brown fox jumps over the lazy dog 0123456789 !@#\$%^&*()  ';
    final plainChunk = plainLine * 100;

    final bypassTerminal = Terminal(maxLines: 1000);
    final bypassSw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      bypassTerminal.write(plainChunk);
    }
    bypassSw.stop();

    final parserTerminal = Terminal(maxLines: 1000);
    final referenceParser = EscapeParser(parserTerminal);
    final parserOnlySw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      referenceParser.write(plainChunk);
    }
    parserOnlySw.stop();

    final plainMb = (plainChunk.length * iterations) / (1024 * 1024);
    // ignore: avoid_print
    print(
      'parse plain: ${(plainMb / (bypassSw.elapsedMicroseconds / 1e6)).toStringAsFixed(1)} MB/s fast path vs '
      '${(plainMb / (parserOnlySw.elapsedMicroseconds / 1e6)).toStringAsFixed(1)} MB/s parser only',
    );

    // ── 2. Parse throughput with SGR colors (agent-output-like mix) ───────
    const coloredLine =
        '\x1b[32m✓\x1b[0m test_passes \x1b[90mtest/unit/foo_test.dart\x1b[0m \x1b[33m12ms\x1b[0m\r\n';
    final coloredChunk = coloredLine * 100;

    terminal = Terminal(maxLines: 1000);
    final colorSw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      terminal.write(coloredChunk);
    }
    colorSw.stop();

    final coloredMb = (coloredChunk.length * iterations) / (1024 * 1024);
    final colorSeconds = colorSw.elapsedMicroseconds / 1e6;
    // ignore: avoid_print
    print(
      'parse sgr:   ${(coloredMb / colorSeconds).toStringAsFixed(1)} MB/s, '
      '${(colorSw.elapsedMicroseconds / (iterations * 100)).toStringAsFixed(2)} µs/line',
    );

    // ── 3. Paint throughput on realistic htop content ──────────────────────
    final paintTerminal = Terminal();
    paintTerminal.write(TestFixtures.htop_80x25_3s());

    final painter = TerminalPainter(
      theme: TerminalThemes.defaultTheme,
      textStyle: const TerminalStyle(fontSize: 13),
      textScaler: TextScaler.noScaling,
    );
    // A bare PictureRecorder canvas rasterizes at scale 1.0; make the
    // painter's dpr match so the glyph-atlas path is taken.
    painter.debugDevicePixelRatio = 1.0;
    final lines = paintTerminal.buffer.lines;

    void paintFrame(Canvas canvas) {
      for (var li = 0; li < lines.length; li++) {
        painter.paintLine(canvas, Offset(0, li * 16.0), lines[li]);
      }
    }

    // Warm-up: fills the paragraph cache (steady state = user reading a
    // static screen, repaint triggered by cursor blink or board pan).
    final recorder = PictureRecorder();
    paintFrame(Canvas(recorder));
    recorder.endRecording().dispose();

    const warmFrames = 300;
    final warmRecorder = PictureRecorder();
    final warmCanvas = Canvas(warmRecorder);
    final warmSw = Stopwatch()..start();
    for (var f = 0; f < warmFrames; f++) {
      paintFrame(warmCanvas);
    }
    warmSw.stop();
    warmRecorder.endRecording().dispose();
    // ignore: avoid_print
    print(
      'paint warm (cached): ${(warmSw.elapsedMicroseconds / warmFrames).toStringAsFixed(0)} µs/frame '
      'for ${lines.length} lines',
    );

    // Cold: clear the paragraph cache before every frame — worst case of a
    // flood repaint, where every line's text is new and all layouts miss.
    const coldFrames = 30;
    final coldSw = Stopwatch()..start();
    for (var f = 0; f < coldFrames; f++) {
      painter.clearFontCache();
      final coldRecorder = PictureRecorder();
      paintFrame(Canvas(coldRecorder));
      coldRecorder.endRecording().dispose();
    }
    coldSw.stop();
    // ignore: avoid_print
    print(
      'paint cold (all miss): ${(coldSw.elapsedMicroseconds / coldFrames).toStringAsFixed(0)} µs/frame '
      '(incl. cache clear)',
    );

    // Realistic flood: the text of every line is new (paragraph layouts all
    // miss), but the glyph atlas stays warm — glyphs themselves were already
    // rasterized. This is the steady state of a flooding terminal and must
    // not pay for Paragraph.layout anymore.
    final floodSw = Stopwatch()..start();
    for (var f = 0; f < coldFrames; f++) {
      painter.clearParagraphCache();
      final floodRecorder = PictureRecorder();
      paintFrame(Canvas(floodRecorder));
      floodRecorder.endRecording().dispose();
    }
    floodSw.stop();
    // ignore: avoid_print
    print(
      'paint flood (atlas hit, layout miss): ${(floodSw.elapsedMicroseconds / coldFrames).toStringAsFixed(0)} µs/frame',
    );
  });

  test('perf benchmark: partial damage rebuild scales with changed lines', () {
    // htop-like steady state: a full-screen TUI repaints every frame, but
    // only a couple of lines actually change (clock, load average, cursor).
    // The per-line replay cache must confine rebuild work to those lines.
    final terminal = Terminal();
    terminal.write(TestFixtures.htop_80x25_3s());

    final painter = TerminalPainter(
      theme: TerminalThemes.defaultTheme,
      textStyle: const TerminalStyle(fontSize: 13),
      textScaler: TextScaler.noScaling,
    );
    painter.debugDevicePixelRatio = 1.0;
    final lines = terminal.buffer.lines;

    void paintFrame(Canvas canvas) {
      for (var li = 0; li < lines.length; li++) {
        painter.paintLine(canvas, Offset(0, li * 16.0), lines[li]);
      }
    }

    void paintRecorded() {
      final recorder = PictureRecorder();
      paintFrame(Canvas(recorder));
      recorder.endRecording().dispose();
    }

    // Frame 1 builds every line.
    paintRecorded();
    expect(painter.debugLineBuildCount, lines.length,
        reason: 'first frame must build every line');

    // Idle frame (nothing changed — the cursor-blink repaint case, where only
    // the cursor overlay moves and no line content changes): zero rebuilds.
    painter.debugLineBuildCount = 0;
    const idleFrames = 300;
    final idleSw = Stopwatch()..start();
    for (var f = 0; f < idleFrames; f++) {
      paintRecorded();
    }
    idleSw.stop();
    expect(painter.debugLineBuildCount, 0,
        reason: 'unchanged lines must be replayed, not rebuilt');
    // ignore: avoid_print
    print(
      'paint idle (all replay): ${(idleSw.elapsedMicroseconds / idleFrames).toStringAsFixed(0)} µs/frame '
      'for ${lines.length} lines',
    );

    // Partial damage: 2 of 24 lines change per frame (htop clock/status row),
    // simulated by real cell writes. Only the damaged lines may be rebuilt.
    const damagedA = 3;
    const damagedB = 17;
    var tick = 0;
    void damageTwoLines() {
      tick++;
      final char = 0x30 + (tick % 10); // '0'..'9'
      lines[damagedA].setCell(70, char, 1, CursorStyle.empty);
      lines[damagedB].setCell(70, char, 1, CursorStyle.empty);
    }

    damageTwoLines();
    painter.debugLineBuildCount = 0;
    paintRecorded();
    expect(painter.debugLineBuildCount, 2,
        reason: 'rebuild work must scale with changed lines, not total lines');

    const partialFrames = 300;
    final partialSw = Stopwatch()..start();
    for (var f = 0; f < partialFrames; f++) {
      damageTwoLines();
      paintRecorded();
    }
    partialSw.stop();
    // ignore: avoid_print
    print(
      'paint partial damage (2/${lines.length} lines): ${(partialSw.elapsedMicroseconds / partialFrames).toStringAsFixed(0)} µs/frame',
    );
  });

  test('op pool recycles evicted line ops across rebuilds', () {
    final terminal = Terminal();
    terminal.write(TestFixtures.htop_80x25_3s());

    final painter = TerminalPainter(
      theme: TerminalThemes.defaultTheme,
      textStyle: const TerminalStyle(fontSize: 13),
      textScaler: TextScaler.noScaling,
    );
    painter.debugDevicePixelRatio = 1.0;
    final lines = terminal.buffer.lines;

    void paintRecorded() {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      for (var li = 0; li < lines.length; li++) {
        painter.paintLine(canvas, Offset(0, li * 16.0), lines[li]);
      }
      recorder.endRecording().dispose();
    }

    // Frame 1: build all lines. No evictions yet, so the pools stay empty.
    paintRecorded();
    expect(painter.debugOpPoolSize, 0,
        reason: 'nothing has been evicted after the first frame');

    // Damage every line and repaint: each rebuilt line overwrites its cached
    // entry, recycling the previous ops into the pools.
    for (var li = 0; li < lines.length; li++) {
      lines[li].setCell(0, 0x58 /* 'X' */, 1, CursorStyle.empty);
    }
    paintRecorded();
    final afterSecondFrame = painter.debugOpPoolSize;
    expect(afterSecondFrame, greaterThan(0),
        reason: 'overwritten cache entries must recycle their ops');

    // Damage and repaint again: the recycled ops must be reused, so the pool
    // size must not keep growing.
    for (var li = 0; li < lines.length; li++) {
      lines[li].setCell(1, 0x59 /* 'Y' */, 1, CursorStyle.empty);
    }
    paintRecorded();
    expect(painter.debugOpPoolSize, lessThanOrEqualTo(afterSecondFrame),
        reason: 'rebuilds must draw from the pools instead of allocating');

    // Theme change clears the whole cache; the pools must absorb it and stay
    // bounded by their capacity.
    painter.theme = TerminalThemes.defaultTheme;
    paintRecorded();
    painter.theme = TerminalThemes.whiteOnBlack;
    expect(painter.debugOpPoolSize, lessThanOrEqualTo(4 * 512),
        reason: 'pools are capped per op type');
  });
}
