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
`test/src/ui/draw_ops_bench_test.dart` (Apple Silicon; absolute numbers are
machine-dependent, the deltas are not):

| Hot path | upstream-style | yoxterm | |
|---|---|---|---|
| Plain-text parse flood | 73.9 MB/s (byte-at-a-time parser) | **98.3 MB/s** (+33%) | parser bypass fast path |
| Canvas ops per htop frame (1920 cells) | 1714 (218 rects + 1496 paragraphs) | **49** (~35× fewer) | run merging + glyph atlas |
| Frame paint under output flood | — | **49 µs/frame** | atlas hits, no layout |
| Idle frame repaint | — | **45 µs/frame** | recorded-op replay, zero rebuilds |

What changed under the hood:

- **Glyph-atlas renderer** — glyphs are rasterized once into a texture atlas
  and emitted as batched `drawRawAtlas` sprite calls instead of one
  `Paragraph` per text run. Box-drawing characters are painted procedurally.
- **Pooled paint ops** — per-line paint operations are recorded once and
  replayed for unchanged lines; evicted ops are recycled through an object
  pool (XRecycler-style) instead of being re-allocated every frame.
- **Parser bypass fast path** — plain-text chunks without control characters
  skip the escape parser entirely; scrollback lines are recycled rather than
  re-allocated.
- **Listener fast paths** — observable terminal notifications avoid
  allocation and iteration overhead when nothing is subscribed.
- **Output paint throttle** — painting is capped at display refresh instead
  of repainting on every PTY read, so a 120 Hz ProMotion display does not
  double the paint work.
- **Quality ratchet** — CI and a pre-commit hook enforce `flutter analyze`,
  the full test suite (~1300 tests) and a
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
