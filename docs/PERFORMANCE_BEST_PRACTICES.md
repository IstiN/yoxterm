# yoxterm — performance best practices

Distilled, reusable rules extracted from the optimization work logged in
[PERFORMANCE.md](PERFORMANCE.md). Every rule here was learned by measuring:
each one either shipped a measured win or was reverted after a benchmark
showed no gain. Follow them when touching the parser, the painter, or the
render object — and when in doubt, measure (`§ Reproducing` at the end).

The single meta-rule: **TDD for performance**. Write the contract test that
counts work (paint calls, rebuilt lines, canvas ops, emitted events) first,
watch it fail, then optimize until it passes. A number you did not measure
is a number you do not have.

---

## 1. Recording and replay beats rebuilding

The single biggest structural win available in Flutter's canvas model:
record expensive work once into a `ui.Picture`, replay it with a single
native `drawPicture` call.

- **Per line** (`644dc14`): every rebuilt line records its ops into a
  `Picture`; an unchanged line costs one native call instead of a Dart-side
  op walk. Guard with the atlas generation — a picture that baked a
  disposed atlas image must never replay (fall back to the op list).
- **Per frame** (`012c74c`): the static viewport layer (background + all
  visible lines) is one `Picture`; cursor blink, selection and focus changes
  re-emit it in one call and redraw only the overlay from Dart.
- **Replay must be position-independent.** Record at `Offset.zero` and
  `translate` at replay time. Baking the paint offset into the picture
  produces stale geometry when the parent repositions the render object
  without a layout change (board switch) — the shipped bug behind "the TUI
  bottom rows don't render until I resize" (`aa54230`).
- Fractional offsets (board zoom) must fall back to exact re-snapped replay,
  not a translated picture — translation preserves snapping only in whole
  device-pixel steps.

## 2. Damage tracking: skip what did not change

Walking every visible cell every frame is the default disaster. Three
layers, cheapest first:

- **Cache-hit proof**: a valid per-line cache entry proves the line's glyphs
  are in the (monotonic) atlas, so the frame-wide glyph discovery pass skips
  it (`644dc14`). Idle frames walk zero cells.
- **Version, not comparison**: per-line `version` ints beat content
  equality. One integer compare decides replay-vs-rebuild.
- **Invalidate on the event, not by re-checking**: a dirty flag set in the
  listener (`_onTerminalChange`, scroll, theme, fonts, layout) is cheaper
  and more reliable than diffing state during paint.

## 3. Batch at the boundary, not per item

- Deliver whole runs to the consumer: text runs as `(list, start, end)`
  views (`TextRunHandler`), bytes as zero-copy chunks. Per-item virtual
  calls (one `consume()`/`writeChar()` per byte) are the tax you are paying
  to remove.
- **But measure before batching a hot loop.** The bulk-CSI port (item 5)
  benchmarked dead even with the per-byte path because real sequences carry
  2–4 digits — the JIT had already eaten the overhead. It was reverted.
  Batching pays where per-item work is heavy (layout, allocation), not
  where it is a few integer ops.

## 4. Keep the parser stateless across chunks — persistently

Never roll back and re-parse on a chunk boundary. The persistent state
machine (`d294b97`) keeps `_ParserState` between `write` calls, decodes
UTF-8 inline with cross-chunk carry, and fast-paths pure-ASCII chunks
zero-copy to the buffer. The rollback pattern is where upstream xterm.dart
lost ~36% on text-heavy streams.

## 5. Cap repaints at the display, not at the producer

PTY output can arrive far faster than the display updates. Coalesce into
one paint per frame interval (`_minOutputPaintInterval`), and let DEC mode
2026 (BSU/ESU) collapse a whole TUI frame into one repaint with a 150 ms
failsafe for stalled syncs. A 120 Hz panel must not double paint cost for
text that is unreadable above ~30 fps anyway.

## 6. Pools and scratch buffers (XRecycler style)

Allocation on the hot path is GC pressure is jank. Reuse:

- typed-array scratch buffers for sprite batches, refilled per line;
- op objects recycled through per-type pools when cache entries are evicted;
- one mutable `Paint`, one `CellData`, one `StringBuffer` per painter —
  the canvas records paint attributes synchronously, so mutation between
  calls is safe.

Bound the pools (capacity caps) so one huge batch cannot pin memory.

## 7. Reserve the glyph atlas per style variant, tint at draw time

Rasterize each glyph **once** (white, per bold/italic/underline variant)
into an atlas; apply terminal colors as a draw-time tint
(`BlendMode.modulate` via `drawRawAtlas`). This is why theme changes must
never invalidate the atlas — only font-affecting changes do. Discover
missing glyphs frame-wide and rebuild the atlas at most once per frame,
never per line.

## 8. State carried across widget rebuilds must survive re-attach

Any baseline you keep (scroll deltas, cached offsets, "last value seen")
is invalid the moment the widget subtree is disposed and rebuilt — even if
the logical object behind it persists. Reset baselines on lifecycle events
(alt-buffer switches rebuild the scrollable; its fresh `ScrollPosition`
starts at zero — `e095fa2`). Symptom of the bug class: works, then quietly
stops working after a view switch.

## 9. Do not fight the framework

- vsync, scheduling, raster caching: use `SchedulerBinding`,
  `RepaintBoundary`, `setIsComplexHint`. Do not build your own timer queue.
- Flutter has no partial-surface present, no persistent GPU buffers, no
  per-column damage API worth having — the recorded-op replay is the
  idiomatic equivalent, and it is enough.
- Native-GL techniques (kitty's `glMapBufferRange`, alacritty's damage
  rects) are research material, not porting targets. Check the portability
  table in PERFORMANCE.md §2/§4.5 before trying.

## 10. Guard rails

- `flutter analyze` + full suite (~1400 tests) + crap4dart CRAP ratchet
  (threshold 61) on every commit. Performance debt is complexity debt —
  the ratchet keeps it from growing back.
- Perf contracts live in tests as counters (`debugPaintCount`,
  `debugLineBuildCount`, `debugFramePictureRebuilds`,
  `debugGlyphScanCount`), not as timing assertions — CI machines are noisy,
  work counts are not.

---

## Reproducing / measuring

- Package benchmarks: `flutter test test/src/ui/perf_benchmark_test.dart`
  `test/src/ui/draw_ops_bench_test.dart` (close the app first; numbers are
  load-sensitive).
- AOT parser microbench: `dart run script/benchmark.dart`.
- Live CPU on the running app: `ps -o %cpu= -p <pid>` sampled once a
  second; idle should sit near 0% on a quiet board.
- Always A/B against the previous commit (`git stash` / measure / `git
  stash pop`) — single-run numbers lie, medians of 3 do not.
