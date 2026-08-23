import 'package:xterm/src/core/cursor.dart';
import 'package:xterm/src/core/mouse/mode.dart';
import 'package:xterm/src/core/state.dart';

/// A mutable [TerminalState] implementation for input and mouse handler tests.
///
/// All modes default to their "reset" values; individual tests override only
/// the fields relevant to the scenario under test.
class FakeTerminalState implements TerminalState {
  @override
  int viewWidth = 80;

  @override
  int viewHeight = 24;

  @override
  CursorStyle cursor = CursorStyle();

  @override
  bool reflowEnabled = false;

  @override
  bool insertMode = false;

  @override
  bool lineFeedMode = false;

  @override
  bool cursorKeysMode = false;

  @override
  bool reverseDisplayMode = false;

  @override
  bool originMode = false;

  @override
  bool autoWrapMode = false;

  @override
  MouseMode mouseMode = MouseMode.none;

  @override
  MouseReportMode mouseReportMode = MouseReportMode.normal;

  @override
  bool cursorBlinkMode = false;

  @override
  bool cursorVisibleMode = true;

  @override
  bool appKeypadMode = false;

  @override
  bool reportFocusMode = false;

  @override
  bool altBufferMouseScrollMode = false;

  @override
  bool bracketedPasteMode = false;
}
