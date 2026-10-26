import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/xterm.dart';

/// Regression tests for same-size [Terminal.resize].
///
/// Views re-apply their viewport dimensions on every (re)attach (board /
/// panel remounts). A same-size resize must not mutate emulator state:
/// resetting DECSTBM margins or clearing alt-buffer scrollback without a
/// matching PTY SIGWINCH desynchronizes differential TUIs (mixed old/new
/// frames until a manual resize forces a full redraw).
void main() {
  test('same-size resize preserves DECSTBM margins and content', () {
    final t = Terminal();
    t.write('\x1b[?1049h'); // alternate buffer
    t.write('\x1b[2;20r'); // DECSTBM rows 2..20 -> margins 1..19
    t.write('\x1b[5;3Hhello');
    final cursorX = t.buffer.cursorX;
    final cursorY = t.buffer.cursorY;
    final lineText = t.buffer.lines[4].getText();

    var resizeEvents = 0;
    t.onResize = (_, __, ___, ____) => resizeEvents++;

    t.resize(80, 24);

    expect(t.buffer.marginTop, 1);
    expect(t.buffer.marginBottom, 19);
    expect(t.buffer.lines[4].getText(), lineText);
    expect(t.buffer.cursorX, cursorX);
    expect(t.buffer.cursorY, cursorY);
    expect(
      resizeEvents,
      1,
      reason:
          'onResize must still fire so hosts can re-sync their backend '
          'dimensions after a remount',
    );
  });

  test('same-size resize preserves main-buffer margins too', () {
    final t = Terminal();
    t.write('\x1b[3;18r');
    expect(t.buffer.marginTop, 2);
    expect(t.buffer.marginBottom, 17);

    t.resize(80, 24);

    expect(t.buffer.marginTop, 2);
    expect(t.buffer.marginBottom, 17);
  });

  test('same-size resize does not clear alt-buffer scrollback', () {
    final t = Terminal();
    t.write('\x1b[?1049h');
    // Shrink with the cursor at the bottom: Buffer.resize keeps extra
    // lines above the viewport, which Terminal.resize then trims via
    // clearScrollback. Grow back so the alt buffer again holds scrollback.
    t.write('\x1b[24;1Hbottom');
    t.resize(80, 20);
    t.resize(80, 24);

    final heightBefore = t.buffer.height;
    final textBefore = [
      for (var i = 0; i < t.buffer.lines.length; i++)
        t.buffer.lines[i].getText(),
    ];

    t.resize(80, 24);

    expect(t.buffer.height, heightBefore);
    expect(
      [
        for (var i = 0; i < t.buffer.lines.length; i++)
          t.buffer.lines[i].getText(),
      ],
      textBefore,
      reason: 'a same-size resize must not trim or shift alt-buffer lines',
    );
  });

  test('real resize still resets margins (unchanged legacy behavior)', () {
    final t = Terminal();
    t.write('\x1b[?1049h');
    t.write('\x1b[2;20r');

    t.resize(80, 30);

    expect(t.buffer.marginTop, 0);
    expect(t.buffer.marginBottom, 29);
  });
}
