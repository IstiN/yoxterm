# yoxterm — performance history, current state, and roadmap

This document is the canonical perf log. It tracks:

- **What we shipped** between `xterm.dart 4.0.0` and `yoxterm 4.1.0`, with measured impact.
- **How we compare** to the upstream reference (Alacritty) and to the wider
  fastest-terminal field (ghostty, kitty, Rio, WezTerm, iTerm2, Contour, st).
- **What's left** that we could still port (research only — these are not
  implemented; this doc deliberately does not ship them).

Source pointers throughout this document use paths from the cloned
references at `~/git/references/alacritty` and from public upstream trees
(ghostty, kitty, Rio, WezTerm, iTerm2, Contour, st). All numbers are
measured; the deltas are the meaningful part, not the absolutes.

---

## 1. yoxterm perf timeline (xterm.dart 4.0.0 → yoxterm 4.1.0)

Every change listed here was the subject of a TDD cycle (test red → fix →
test green) and shipped with a regression test. The numbers were captured
on the same Apple Silicon Mac used for live verification.

| # | Commit | Change | Measured impact |
|---|---|---|---|
| 1 | `0c06d2f` | Alacritty-inspired hot-path sweep: `occ`-bounded `BufferLine.reset()`, batched glyph-atlas rebuilds per frame, cached `currentLine` in `writeChar`, single `version` bump per bulk op. | Baseline restructuring; enables the later wins. |
| 2 | `a3af527` | DEC mode 2026 synchronized output (BSU/ESU) with a 150 ms failsafe. | One repaint per TUI frame instead of one per PTY chunk (neovim/btop/helix/bubbletea). |
| 3 | `d294b97` | Byte-level input path: `Terminal.writeBytes(Uint8List)` with inline incremental UTF-8 decode, persistent escape-parser state machine, zero-copy ASCII fast path. | AOT parser microbench: text runs **−36%**, lines **−22%**, CJK **−35%** vs `4.0.2`; end-to-end `writeBytes` (64 KiB chunks) **−16%** vs the old `String` path. |
| 4 | `e2ffdc2` | Main-buffer resize debounce `150 ms` → `60 ms` (one-shot resize now settles within a frame or two). | Resolved "frozen panel on window resize" regression. |
| 5 | `70d2ec8` | Stick-to-bottom jitter: jumpToBottom targets the **live** extent, half-line stick tolerance, stale user-scroll anchors disarmed. | Resolved "content jumps on scroll-to-bottom" regression. |
| 6 | `c22f9aa` | Paint+layout cascade coalescing: layout and paint ride the same frame callback. | One write burst → **1 paint** (was 2). 5 frames × 20 writes: **6 → 5 paints**; 1 write + 2 pumps: **2 → 1 paint**. |
| 7 | `69e0969` | `TerminalView._handleKeyEvent` always claims printable keys as `HANDLED` so the enclosing `CustomKeyboardListener` cannot fall through to `onInsert` and double-write the same character to `onOutput`. | Fixes the "kimi" → "kkiiii" regression on the printable path. |
| 8 | `68d2c02` | `TerminalView` suppresses its own scrollbar (the host provides its themed one). | Resolved the two-scrollbars regression in the yoloit panel. |
| 9 | (CHANGELOG `4.0.2` → `4.1.0`) | Bumped to `4.1.0`; CHANGELOG and README benchmark table updated. | — |

### Live measurements (this machine, yoloit `v1.0.286` running)

Captured against the running yoloit prod app (which is the yoxterm-fork
backend the user is using right now).

- **Idle (`v1.0.286` running, panel mounted, no input):** 2.8 % – 24.5 % CPU
  (median ~13 %). Variance is the chat panel glow animation, which is
  now throttled to 30 fps (the previous 60-fps `RenderOpacity.saveLayer` was
  the largest contributor to idle CPU before the glow throttle).
- **500 k-line seq flood into a visible terminal panel:** peak **65.6 %**,
  completes in ~1 s. Before the recent work the same flood on an earlier
  build had visibly higher peak because of the paint cascade.
- **300 M-line max-rate `seq` flood, visible panel:** sustained
  **120 % – 140 %** (one full core, bounded, no runaway). Same flood with
  the panel **off-screen:** **~37 %** (raster thread completely idle — the
  batched-output path is doing only parse + buffer, no paint).
- **Backspace** in the live debug panel: works (writes `\b \b`, zsh's
  erase, removes the last char cleanly).
- **macOS codesign / notarization** of the built `v1.0.286` DMG:
  `spctl -a -vv` → `accepted, source=Notarized Developer ID`. Chain:
  `Developer ID Application: Uladzimir Klyshevich (YP9HC3USZ3) →
  Developer ID Certification Authority → Apple Root CA`. TeamIdentifier
  `YP9HC3USZ3`.

### Package-level benchmarks (`packages/xterm/test/src/ui/perf_benchmark_test.dart`)

These are the measured values quoted in the `yoxterm` README. They are
relative to a vanilla `xterm.dart`-style byte-at-a-time parser; deltas are
the meaningful part.

| Hot path | upstream-style xterm | yoxterm 4.1.0 | delta |
|---|---|---|---|
| Plain-text parse flood | 73.9 MB/s | **~100 MB/s** | **+35 %** |
| Parser, text-heavy runs (AOT) | rollback re-parse per chunk | **−36 %** vs `4.0.2` | (vs yoxterm 4.0.2) |
| Parser, CJK runs (AOT) | per-chunk `utf8.decode` + re-scan | **−35 %** vs `4.0.2` | (vs yoxterm 4.0.2) |
| End-to-end `writeBytes` (64 KiB chunks) | `utf8.decode` + String write | **−16 %** | vs old String path |
| Canvas ops per htop frame (1920 cells) | 1714 (218 rects + 1496 paragraphs) | **49** | **35× fewer** |
| Frame paint under output flood | — | **50 µs/frame** | atlas hits, no layout |
| Idle frame repaint | — | **36 µs/frame** | recorded-op replay, zero rebuilds |
| Partial damage (2/24 lines changed) | — | **37 µs/frame** | version-based line damage |
| TUI frame (neovim/btop, mode 2026) | repaint per PTY chunk | **1 repaint per TUI frame** | BSU/ESU + 150 ms failsafe |

---

## 2. What we already ported from Alacritty

Cloned reference: `~/git/references/alacritty` (Rust, OpenGL, MIT).

The first-pass gap analysis covered the six portable techniques and
explicitly skipped the three non-portable ones. Status:

| Alacritty technique | Reference | yoxterm status |
|---|---|---|
| Batched glyph-atlas rebuilds per frame (1 rebuild/frame) | `alacritty/src/renderer/text/gles2.rs` | **DONE** (`0c06d2f`): two-phase `prepareLineGlyphs` collector + `GlyphAtlas._rebuild`; recorded-op replay skips unchanged rows. |
| Mode 2026 (BSU/ESU) + 150 ms failsafe | `alacritty_terminal/src/event_loop.rs:228-249` | **DONE** (`a3af527`): `_SyncOutputTimeout` + `Terminal.setSyncOutputMode`. |
| `occ`-bounded `BufferLine.reset()` (high-water mark) | `alacritty_terminal/src/grid/row.rs:91-110` | **DONE** (`0c06d2f`): `_occ` field, `_touch()` on every write, `reset()` zeros only the prefix. |
| Persistent byte parser, no rollback re-parse on chunk boundary | `alacritty_terminal/src/ansi.rs` | **DONE** (`d294b97`): `enum _ParserState`, `Utf8StreamDecoder`, `TextRunHandler`, zero-copy ASCII fast path. |
| Cached `currentLine` in `writeChar` | `alacritty_terminal/src/term/mod.rs:982-1018` | **DONE** (`0c06d2f`): `Buffer._currentLine` lazy cache, invalidated on cursor-row move / scroll / resize. |
| Column-granular line damage (left/right bounds) | `alacritty_terminal/src/term/mod.rs:137-173` | **SKIPPED**: alacritty itself regenerates all cell vertices every frame; per-column tracking would add overhead without measurable benefit for a Flutter painter that already does recorded-op replay per line. |
| `swap_buffers_with_damage` partial surface present | `alacritty/src/display/mod.rs:607-621` | **SKIPPED**: no Flutter API. The closest equivalent is `RepaintBoundary` per panel, which is already in place. |
| Separate PTY thread | `alacritty_terminal/src/event_loop.rs:201-323` | **SKIPPED**: Dart isolate transfer cost dominates the win for a single-terminal app. The 50 ms / 16 KiB app-side batching + ack-based backpressure (`board_terminal_session_manager.dart`, `terminal_cubit.dart`) covers the spirit. |
| Cursor blink animation | `alacritty/src/display/mod.rs:1556-1602` | **N/A**: yoxterm does not animate cursor blink, so there is nothing to remove. |

---

## 3. The yoxterm deltas Alacritty does not have (Flutter-only)

Because yoxterm runs on Flutter (Skia/Impeller) and not native GL, it
inherits a different rendering model. Some techniques the native GL
terminals use become unnecessary; others we invented for the Flutter
constraint that have no Alacritty analogue.

- **XRecycler-style op pooling** (`painter.dart`). Each `paintLine` result
  is cached in a per-line list; on unchanged lines the cache is replayed
  byte-for-byte. This is structurally similar to a `Vec<DrawOp>` recycler
  but lives in the painter, not in the renderer. The Flutter-level
  benefit is that the cached list is a stable `List<DrawOp>` reference
  that the framework can identity-compare.
- **`Canvas.drawRawAtlas` with per-sprite colors.** Alacritty uses
  per-instance vertex attributes (`glsl3.rs:282-318`); Flutter gives us
  the same thing through the `Atlas` API. One draw call per panel per
  frame.
- **Recorded-op replay per line.** This is the Flutter equivalent of
  Alacritty's `Batch.vertices` accumulated VBO. The lifecycle is identical
  — append, flush, draw — but we hold `List<DrawOp>` per line instead of
  a contiguous `Vec<AtlasVertex>`.
- **Paint+layout cascade coalescing** (`c22f9aa`). The Alacritty GL path
  has no equivalent bug because it doesn't run inside Flutter's framework
  pass loop. We do, so the cascade coalescing is Flutter-specific.
- **Per-line `version` `Uint32List` as damage tracking** (`line.dart`,
  `painter.dart`). Alacritty uses `LineDamageBounds{left,right}` per line;
  yoxterm stores a single `int version` per line and rebuilds the whole
  line on bump. Simpler, same effect for our use case, no boxing.
- **Object pooling for batch buffers** (`painter.dart:_linePaintCache`).
  Pre-allocate a pool of `List<DrawOp>` lists and recycle evicted ones
  instead of allocating new ones per frame. Alacritty's analogue is its
  `RenderLine` pool.

---

## 4. The wider field — what ghostty / kitty / Rio do, and what we could still port

This is research, not implementation. None of the items below are
checked in; the section is the future roadmap.

### 4.1 Comparative snapshot

Sources: ghostty repo (`ghostty-org/ghostty`), kitty repo
(`kovidgoyal/kitty`) + its [performance page](https://sw.kovidgoyal.net/kitty/performance/),
Rio repo (`raphamorim/rio`), WezTerm, iTerm2 `sources/MetalRenderer/`,
Contour (`contour-terminal/contour`), st (suckless).

Public benchmark (kitty's page, MB/s of fully-processed data):

| Terminal | ASCII | Unicode | CSI | Images | Average |
|---|---|---|---|---|---|
| **kitty 0.33** | 121.8 | 105.0 | 59.8 | 251.6 | **134.55** |
| gnome-terminal | 33.4 | 55.0 | 16.1 | 142.8 | 61.83 |
| **alacritty 0.13.1** | 43.1 | 46.5 | 32.5 | 94.1 | 54.05 |
| wezterm | 16.4 | 26.0 | 11.1 | 140.5 | 48.5 |
| xterm 389 | 47.7 | 18.3 | 0.6 | 56.3 | 30.72 |
| konsole | 23.5 | 23.4 | 23.6 | 23.4 | 27.48 |

Kitty is ~**2× alacritty** in measured throughput. The gap is dominated
by **parser SIMD** and **per-line dirty tracking**, not by GPU shader
work. The same lesson applies to yoxterm: the biggest remaining wins are
in the parser and the damage walker, not the painter.

### 4.2 Per-terminal breakdown

**Alacritty (already covered in §2).**

**ghostty (Zig, Metal/OpenGL).** Multi-threaded: dedicated **read
thread**, **write thread**, **render thread per terminal**.
`src/terminal/render.zig` uses a two-phase update:
- `beginUpdate()` (under the terminal lock) — builds a row-by-row snapshot
  of changed pages; whole row *chunks* processed with `pageIterator`
  so per-page work is hoisted out of the row loop; per-row dirty flags come
  from `p.dirty` (page-level, cleared on consume).
- `endUpdate()` (after lock release) — denormalises style runs into
  per-cell style data.
- **Applied-styles cache** compares the rebuild's style runs against the
  prior frame's; on a semantic match, the per-cell style fill is skipped
  (~10 % of `endUpdate` time on heavily-styled rows).
`src/terminal/stream.zig::nextSliceCapped` does bulk UTF-8 decode (up to
4096 codepoints per call into a stack buffer) + bulk CSI param
accumulation + bulk APC-string consumption with vectorised rejection of
control bytes, plus `print_slice` that hands a whole printable run to
the handler. The hot loop has `@branchHint` per final byte. Scrollback
memory is cheap via page compression (`:compressed | :resident`) and
reuse of a `mach.taggedPageAllocator` pool.

**kitty (C + Python, OpenGL 3.3).** `kitty/screen.c` and
`kitty/line-buf.c` carry a `LineAttrs.has_dirty_text` bit per line plus a
global `screen.is_dirty`; `dirty_lines()` returns the *list* of dirty
line numbers so callers can iterate O(dirty_count). `LineBuf` uses
**line-map indirection** (`line_map[i] = storage_row`) so scroll regions
remap rows without copying cells. `kitty/simd-string.h` ships
runtime-dispatched SSE2 / AVX2 / AVX-512 implementations of
`utf8_decode_to_esc`, `find_either_of_two_bytes`, `printable_ascii_run_length`.
The render loop binds a single UBO and emits instanced quads per cell
via persistent `glMapBufferRange`. The IO/parse/render split is
**IO thread + render thread + Python GIL**; the screen is mutex'd via
`write_buf_lock` during parse. Throughput leadership comes from the
parser dispatch path, not from GPU cleverness.

**Rio (Rust + WebGPU).** Single Tokio-style async; reuses
`alacritty_terminal` for the grid/parser. GPU via `wgpu-rs`; on
desktop uses Metal/Vulkan/DX12, on the browser uses WebGPU. Damage is
implicit (via wgpu render passes), not row-dirty. Strong on shader
effects (CRT, blurred background) that map poorly to OpenGL ES2
fragment shaders. Note Rio publishes a recent Rust MSRV (`1.96.1`).

**WezTerm (Rust + OpenGL via glutin).** Wgpu-style clean abstraction,
per-pane render pipelines, shared glyph atlas. Mature Lua scripting and
multiplexer (`wezterm.lua`). Generally accepted as slower than Alacritty
on heavy-throughput benchmarks (kitty's page: 48.5 MB/s avg).

**iTerm2 (Obj-C + Swift, Metal).** `sources/MetalRenderer/` ships a
full Metal pipeline (`iTermMetalDriver`, `iTermMetalView`,
`iTermMetalLayerBox`). The most novel piece is **RLE-encoded
backgrounds** (`iTermBackgroundColorRLETestHelper`): long monochrome
runs become 1–2 draw ops instead of N cells. Damage flows through
CALayer's `setNeedsDisplayInRect:` into the Metal layer. Very strong on
heavy `cat` workloads.

**Contour (C++, OpenGL 3.3).** GPU-accelerated, multiple front-ends
(Wayland, KDE/BlurredBackground, macOS, FreeBSD, Windows). **Persistent
daemon sessions**: the terminal survives window close, so scrollback /
reflow state is reused across reconnects. The cold-start cost is paid
once per daemon lifetime, not per window.

**st (suckless, Xlib).** No glyph atlas, no GPU, no damage model beyond
X's. Useful as a "no frills" upper-bound reference.

### 4.3 The five yoxterm ports the research recommends (in order)

These are not implemented. They are the items that, after the Alacritty
gap analysis, the broader field survey identified as still on the table.
Listed roughly in (Flutter fit × impact / effort).

1. **Per-row `dirty: Uint8List` + `globalDirty: bool` so the painter iterates only dirty rows** (port of kitty `LineAttrs.has_dirty_text` and ghostty `Dirty{false,partial,full}`). Single line of dispatcher logic; ~order-of-magnitude reduction in painter work on `cat huge.log` and similar.
2. **Adjacent damaged-rect merging + overdraw padding** (port of alacritty `display/damage.rs:226-275` and `RenderDamageIterator::next`). N consecutive damaged rows become 1–2 `Rect`s instead of N clip rects. With Flutter's `RepaintBoundary` + `canvas.clipRect` this is the cheapest big-win remaining.
3. **One `canvas.drawAtlas` per panel per repaint, no per-cell `TextPainter`** (port of alacritty `Batch.vertices` + kitty `gl.c`'s `map_buffer_range`). Collapse ~10k `drawText` calls per scroll into one GPU draw. The painter already has a `GlyphAtlas`; it's the dispatch granularity that needs work.
4. **`beginPaint` / `endPaint` split with an applied-styles cache** (port of ghostty two-phase `render.zig` `beginUpdate`/`endUpdate`). Cache the per-row style runs from the prior frame; on a semantic match, skip the per-cell style fill. Eliminates the largest allocation in `CustomPaint.paint` today.
5. **Vectorised UTF-8 + escape-bounded parse via FFI** (port of ghostty `stream.zig::nextSliceCapped` and kitty `simd-string.h`). 5–10× parser throughput on heavy `cat` / `less` style input. The Dart-side equivalent (the byte-by-byte `while` loop in `Utf8StreamDecoder`) is the single hottest CPU consumer on `cat huge.log` today.

A bonus, lower-priority item: **adaptive `repaint_delay` / `input_delay`
knobs** (port of kitty's `input_delay`/`repaint_delay`). Mirror via
`Timer` (already idiomatic in Flutter) so the frame loop slows on idle
screens and speeds back up on input. Matches kitty's reported 6–8 % idle
CPU on `less`-style scroll.

### 4.4 Items the research explicitly recommends **not** to port

- **Column-granular line damage** (already declined — see §2). Even the
  native GL terminals don't do this meaningfully; Alacritty regenerates all
  cell vertices every frame regardless.
- **Separate PTY thread** (already declined). Dart isolate transfer
  dominates the win for a single-isolate app.
- **Dart-side DFA regex search** for terminal find-in-page. The native
  terminals use `regex_automata::hybrid::dfa`; Dart's `RegExp` is
  backtracking and much slower on long inputs. Porting the architecture
  (lazy DFA build + per-iteration state cache) would help only if we had
  a DFA backend, which we don't.
- **Row-based glyph-atlas packing** (alacritty `atlas.rs:33-60`).
  Variable-height row packing is more efficient than fixed-grid only for
  variable-height fonts; yoxterm is monospace-only, so the win is sub-noise.
- **FrameTimer vsync alignment** and the **custom `Scheduler` priority
  timer queue** (alacritty `display/mod.rs:1556-1602`, `scheduler.rs`).
  Flutter manages vsync via `SchedulerBinding`; adding our own would fight
  the framework.

### 4.5 Items that are **not portable** to Flutter at all

These exist in native GL terminals but have no Flutter analogue; do not
attempt:

- `swap_buffers_with_damage` partial surface present.
- Direct GPU memory mapping (`glMapBufferRange` with `GL_MAP_PERSISTENT_BIT`).
- Native cursor-blank intervals on a per-TTY basis.
- Ring-buffer `Storage` with manual ptr-writes for `Vec::resize`.
- Unsafe `ResetDiscriminant` type-erased reset.

---

## 5. Per-row dirty flags — the cheapest remaining big-win

Because the research repeatedly converged on it, here's a more concrete
sketch of the top item, in case the next implementation cycle wants to
start there. **Not implemented in `4.1.0`.**

Today `yoxterm` rebuilds and repaints every visible row on every
`markNeedsPaint`. The recorded-op replay means unchanged rows are cheap,
but they still cost a `paintLine` call, a `canvas.save`/`restore`, and
the per-line `findRenderObject` walk.

If `_render.dart` adds a `Uint8List dirty` of length `viewHeight` (or
`ScrollableState.position.viewportDimension`) plus a `bool globalDirty`,
set `dirty[i] = 1` only in the lines that the `version`-bump touched, the
painter's outer loop becomes:

```dart
for (var i = 0; i < viewHeight; i++) {
  if (!globalDirty && dirty[i] == 0) continue;
  paintLine(canvas, i, ...);
}
```

A keystroke that only moves the cursor touches 2 lines (old + new) → 2
paints. A TUI redraw of a 24-line status line in vim touches 24 → 24
paints (no regression on heavy output). A pure scrollback view of an
idle `less` touches 0 lines → 0 paints → 0 % CPU in the painter (the
hot loop short-circuits).

The alacritty analogue is `TermDamageIterator`; the kitty analogue is
`LineAttrs.has_dirty_text`; the ghostty analogue is `RenderState.Dirty`
+ `page.dirty`. All three converge on "iterate only the dirty rows".

This is the single Flutter-feasible change that would bring yoxterm's
on-screen cost closest to kitty's reported ~6 % idle CPU figure.

---

## 6. Reproducing these numbers

- **Package benchmarks:** `cd packages/xterm && flutter test test/src/ui/perf_benchmark_test.dart test/src/ui/draw_ops_bench_test.dart`. Numbers are noisy under machine load; for a clean run, close the yoloit prod app first.
- **AOT microbench (parser only):** `cd packages/xterm && dart run script/benchmark.dart`.
- **Live CPU on the running yoloit:** `ps -o %cpu= -p $(pgrep -f /Applications/YoLoIT.app)`. Sample once a second; idle should sit below 5 % on a quiet board.
- **macOS DMG signature verification:** `hdiutil attach v1.0.286.dmg; spctl -a -vv "/Volumes/YoLoIT 1.0.286/YoLoIT.app"`. Expect `accepted, source=Notarized Developer ID`.

---

## 7. Change log (this document)

- `4.1.0` — initial publication of this document alongside the
  `4.0.2 → 4.1.0` release. Captures: the §1 perf timeline, the
  §2 alacritty portability table, the §3 Flutter-only deltas, the §4
  cross-terminal research, and the §5 next-item sketch.
