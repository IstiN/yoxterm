# yoxterm

<p>
  <a href="https://github.com/IstiN/yoxterm/actions/workflows/ci.yml">
    <img alt="CI" src="https://github.com/IstiN/yoxterm/actions/workflows/ci.yml/badge.svg">
  </a>
  <a href="https://pub.dev/packages/yoxterm">
    <img alt="pub" src="https://img.shields.io/pub/v/yoxterm?color=blue&include_prereleases">
  </a>
  <img alt="CRAP score (max)" src="badges/crap.svg">
</p>

**yoxterm** is a high-performance terminal emulator for Flutter — a
performance-focused fork of [xterm.dart](https://github.com/TerminalStudio/xterm.dart)
(MIT, © xuty). It keeps the upstream API and feature set (VT100/xterm
emulation, CJK & emoji, IME, shortcuts, mobile and desktop) and rebuilds the
hot paths: parsing, painting and scrolling.

> Requires Flutter >= 3.33.0

## Why yoxterm over xterm.dart

Measured by `flutter test test/src/ui/perf_benchmark_test.dart` and
`test/src/ui/draw_ops_bench_test.dart`, plus AOT microbenchmarks in
`script/benchmark.dart` (Apple Silicon; absolute numbers are
machine-dependent, the deltas are not):

| Hot path | upstream-style | yoxterm | |
|---|---|---|---|
| Plain-text parse flood | 73.9 MB/s (byte-at-a-time parser) | **103 MB/s** (+39%) | persistent byte parser + zero-copy fast path |
| Parser, text-heavy runs (AOT) | rollback re-parse per chunk | **−36%** vs yoxterm 4.0.2 | state survives across chunks |
| Parser, CJK runs (AOT) | per-chunk `utf8.decode` + re-scan | **−35%** vs yoxterm 4.0.2 | inline incremental UTF-8 decode |
| End-to-end `writeBytes` (64 KiB chunks) | `utf8.decode` + String write | **−16%** | one decode+parse pass per flush |
| Canvas ops per htop frame (1920 cells) | 1714 (218 rects + 1496 paragraphs) | **49** (~35× fewer) | run merging + glyph atlas |
| Frame paint under output flood | — | **50 µs/frame** | atlas hits, no layout |
| Idle frame repaint | — | **36 µs/frame** | recorded-op replay, zero rebuilds |
| Partial damage (2/24 lines changed) | — | **37 µs/frame** | version-based line damage |
| TUI frame (neovim/btop, mode 2026) | repaint per PTY chunk | **1 repaint per TUI frame** | BSU/ESU + 150 ms failsafe |

What changed under the hood:

- **Byte-level input path** — `Terminal.writeBytes(Uint8List)` decodes UTF-8
  inline with cross-chunk carry (split multibyte sequences parse once), the
  escape parser is a persistent state machine with no rollback re-parse, and
  clean ASCII chunks reach the buffer zero-copy.
- **Synchronized output (DEC mode 2026)** — BSU/ESU-wrapped TUI frames
  (neovim, btop, helix, bubbletea) produce exactly one repaint per frame
  instead of one per PTY chunk; a 150 ms failsafe aborts stalled syncs.
- **Glyph-atlas renderer** — glyphs are rasterized once into a texture atlas
  and emitted as batched `drawRawAtlas` sprite calls instead of one
  `Paragraph` per text run. Missing glyphs are collected across the whole
  frame and the atlas is rebuilt at most once per frame. Box-drawing
  characters are painted procedurally.
- **Pooled paint ops** — per-line paint operations are recorded once and
  replayed for unchanged lines; evicted ops are recycled through an object
  pool (XRecycler-style) instead of being re-allocated every frame.
- **Parser bypass fast path** — plain-text chunks without control characters
  skip the escape parser entirely; scrollback lines are recycled rather than
  re-allocated, and line resets only touch the occupied prefix
  (alacritty-style high-water mark).
- **Listener fast paths** — observable terminal notifications avoid
  allocation and iteration overhead when nothing is subscribed.
- **Output paint throttle** — painting is capped at display refresh instead
  of repainting on every PTY read, so a 120 Hz ProMotion display does not
  double the paint work.
- **Quality ratchet** — CI and a pre-commit hook enforce `flutter analyze`,
  the full test suite (~1400 tests) and a
  [crap4dart](https://github.com/IstiN/crap4dart) CRAP gate
  (threshold 61, current max 59) so performance debt cannot grow back.

## Screenshots

<table>
  <tr>
    <td>
      <img width="200px" src="https://raw.githubusercontent.com/IstiN/yoxterm/main/media/demo-shell.png">
    </td>
    <td>
      <img width="200px" src="https://raw.githubusercontent.com/IstiN/yoxterm/main/media/demo-vim.png">
    </td>
  </tr>
  <tr>
    <td>
      <img width="200px" src="https://raw.githubusercontent.com/IstiN/yoxterm/main/media/demo-htop.png">
    </td>
    <td>
      <img width="200px" src="https://raw.githubusercontent.com/IstiN/yoxterm/main/media/demo-dialog.png">
    </td>
  </tr>
</table>

## Performance

- 📊 [Performance history, current state, and roadmap](docs/PERFORMANCE.md) —
  every change from `xterm.dart 4.0.0` to `yoxterm 4.1.0` with measured
  impact, an Alacritty portability table, and a cross-terminal research
  summary (ghostty, kitty, Rio, WezTerm, iTerm2, Contour, st) with the
  five Flutter-feasible ports we have not yet shipped.

## Features

- 📦 **Works out of the box** — no special configuration required.
- 🚀 **Fast** — glyph-atlas rendering, pooled paint ops, parser fast paths.
- 😀 **Wide character support** — CJK and emojis.
- ✂️ **Customizable** — themes, terminal text style, shortcuts.
- ✔ **Frontend independent** — the terminal core works without the Flutter
  frontend (headless testing, server-side emulation).
- 📱 **Mobile and desktop** — IME integration, keyboard shortcuts, pointer
  input.

## Getting started

**1.** Add the dependency:

```yml
dependencies:
  yoxterm: ^4.0.0
```

**2.** Create the terminal:

```dart
import 'package:yoxterm/xterm.dart';

terminal = Terminal();

terminal.onOutput = (output) {
  print('output: $output');
};
```

**3.** Attach a view:

```dart
child: TerminalView(terminal),
```

**4.** Write to the terminal:

```dart
terminal.write('Hello, world!');
```

**Done!**

## More examples

- A simple terminal in ~100 lines of code:
  https://github.com/IstiN/yoxterm/blob/main/example/lib/main.dart

- An SSH client in ~100 lines of code with [dartssh2]:
  https://github.com/IstiN/yoxterm/blob/main/example/lib/ssh.dart

  <img width="400px" src="https://raw.githubusercontent.com/IstiN/yoxterm/main/media/example-ssh.png">

yoxterm powers the terminal panels of [YoLoIT](https://github.com/IstiN/yoloit),
a CLI-first desktop workspace — that is where the performance work originates.

## Contributing

Feature requests and bugs: [issue tracker](https://github.com/IstiN/yoxterm/issues).

Development setup:

```bash
git config core.hooksPath scripts   # enables the pre-commit gate
flutter test
flutter test test/src/ui/perf_benchmark_test.dart  # throughput numbers
```

The pre-commit hook runs `flutter analyze`, `flutter test --coverage` and the
crap4dart CRAP ratchet. If a change legitimately improves the max CRAP score,
lower the threshold in `crap4dart.yaml` — never raise it to make a regression
pass.

## License

MIT. Based on [xterm.dart](https://github.com/TerminalStudio/xterm.dart)
by xuty and the TerminalStudio contributors.

[dartssh2]: https://pub.dev/packages/dartssh2
