import 'package:yoxterm/xterm.dart';

/// An [EscapeHandler] that records every invocation as a string in [calls],
/// e.g. `resize(80, 24)`. Tests assert on the exact sequence of calls, which
/// makes ordering and argument mistakes visible without a mocking framework.
class RecordingEscapeHandler implements EscapeHandler {
  final calls = <String>[];

  void _record(String name, [List<Object?> args = const []]) {
    calls.add('$name(${args.join(', ')})');
  }

  @override
  void writeChar(int char) => _record('writeChar', [char]);

  /* SBC */

  @override
  void bell() => _record('bell');

  @override
  void backspaceReturn() => _record('backspaceReturn');

  @override
  void tab() => _record('tab');

  @override
  void lineFeed() => _record('lineFeed');

  @override
  void carriageReturn() => _record('carriageReturn');

  @override
  void shiftOut() => _record('shiftOut');

  @override
  void shiftIn() => _record('shiftIn');

  @override
  void unknownSBC(int char) => _record('unknownSBC', [char]);

  /* ANSI sequence */

  @override
  void saveCursor() => _record('saveCursor');

  @override
  void restoreCursor() => _record('restoreCursor');

  @override
  void index() => _record('index');

  @override
  void nextLine() => _record('nextLine');

  @override
  void setTapStop() => _record('setTapStop');

  @override
  void reverseIndex() => _record('reverseIndex');

  @override
  void designateCharset(int charset, int name) =>
      _record('designateCharset', [charset, name]);

  @override
  void unkownEscape(int char) => _record('unkownEscape', [char]);

  /* CSI */

  @override
  void repeatPreviousCharacter(int n) => _record('repeatPreviousCharacter', [n]);

  @override
  void setCursor(int x, int y) => _record('setCursor', [x, y]);

  @override
  void setCursorX(int x) => _record('setCursorX', [x]);

  @override
  void setCursorY(int y) => _record('setCursorY', [y]);

  @override
  void sendPrimaryDeviceAttributes() => _record('sendPrimaryDeviceAttributes');

  @override
  void clearTabStopUnderCursor() => _record('clearTabStopUnderCursor');

  @override
  void clearAllTabStops() => _record('clearAllTabStops');

  @override
  void moveCursorX(int offset) => _record('moveCursorX', [offset]);

  @override
  void moveCursorY(int n) => _record('moveCursorY', [n]);

  @override
  void sendSecondaryDeviceAttributes() =>
      _record('sendSecondaryDeviceAttributes');

  @override
  void sendTertiaryDeviceAttributes() => _record('sendTertiaryDeviceAttributes');

  @override
  void sendOperatingStatus() => _record('sendOperatingStatus');

  @override
  void sendCursorPosition() => _record('sendCursorPosition');

  @override
  void setMargins(int i, [int? bottom]) => _record('setMargins', [i, bottom]);

  @override
  void cursorNextLine(int amount) => _record('cursorNextLine', [amount]);

  @override
  void cursorPrecedingLine(int amount) =>
      _record('cursorPrecedingLine', [amount]);

  @override
  void eraseDisplayBelow() => _record('eraseDisplayBelow');

  @override
  void eraseDisplayAbove() => _record('eraseDisplayAbove');

  @override
  void eraseDisplay() => _record('eraseDisplay');

  @override
  void eraseScrollbackOnly() => _record('eraseScrollbackOnly');

  @override
  void eraseLineRight() => _record('eraseLineRight');

  @override
  void eraseLineLeft() => _record('eraseLineLeft');

  @override
  void eraseLine() => _record('eraseLine');

  @override
  void insertLines(int amount) => _record('insertLines', [amount]);

  @override
  void deleteLines(int amount) => _record('deleteLines', [amount]);

  @override
  void deleteChars(int amount) => _record('deleteChars', [amount]);

  @override
  void scrollUp(int amount) => _record('scrollUp', [amount]);

  @override
  void scrollDown(int amount) => _record('scrollDown', [amount]);

  @override
  void eraseChars(int amount) => _record('eraseChars', [amount]);

  @override
  void insertBlankChars(int amount) => _record('insertBlankChars', [amount]);

  @override
  void unknownCSI(int finalByte) => _record('unknownCSI', [finalByte]);

  /* Modes */

  @override
  void setInsertMode(bool enabled) => _record('setInsertMode', [enabled]);

  @override
  void setLineFeedMode(bool enabled) => _record('setLineFeedMode', [enabled]);

  @override
  void setUnknownMode(int mode, bool enabled) =>
      _record('setUnknownMode', [mode, enabled]);

  /* DEC Private modes */

  @override
  void setCursorKeysMode(bool enabled) => _record('setCursorKeysMode', [enabled]);

  @override
  void setReverseDisplayMode(bool enabled) =>
      _record('setReverseDisplayMode', [enabled]);

  @override
  void setOriginMode(bool enabled) => _record('setOriginMode', [enabled]);

  @override
  void setColumnMode(bool enabled) => _record('setColumnMode', [enabled]);

  @override
  void setAutoWrapMode(bool enabled) => _record('setAutoWrapMode', [enabled]);

  @override
  void setMouseMode(MouseMode mode) => _record('setMouseMode', [mode.name]);

  @override
  void setCursorBlinkMode(bool enabled) =>
      _record('setCursorBlinkMode', [enabled]);

  @override
  void setCursorVisibleMode(bool enabled) =>
      _record('setCursorVisibleMode', [enabled]);

  @override
  void useAltBuffer() => _record('useAltBuffer');

  @override
  void useMainBuffer() => _record('useMainBuffer');

  @override
  void clearAltBuffer() => _record('clearAltBuffer');

  @override
  void setAppKeypadMode(bool enabled) => _record('setAppKeypadMode', [enabled]);

  @override
  void setReportFocusMode(bool enabled) =>
      _record('setReportFocusMode', [enabled]);

  @override
  void setMouseReportMode(MouseReportMode mode) =>
      _record('setMouseReportMode', [mode.name]);

  @override
  void setAltBufferMouseScrollMode(bool enabled) =>
      _record('setAltBufferMouseScrollMode', [enabled]);

  @override
  void setBracketedPasteMode(bool enabled) =>
      _record('setBracketedPasteMode', [enabled]);

  @override
  void setSyncOutputMode(bool enabled) =>
      _record('setSyncOutputMode', [enabled]);

  @override
  void setUnknownDecMode(int mode, bool enabled) =>
      _record('setUnknownDecMode', [mode, enabled]);

  @override
  void resize(int cols, int rows) => _record('resize', [cols, rows]);

  @override
  void sendSize() => _record('sendSize');

  /* Select Graphic Rendition (SGR) */

  @override
  void resetCursorStyle() => _record('resetCursorStyle');

  @override
  void setCursorBold() => _record('setCursorBold');

  @override
  void setCursorFaint() => _record('setCursorFaint');

  @override
  void setCursorItalic() => _record('setCursorItalic');

  @override
  void setCursorUnderline() => _record('setCursorUnderline');

  @override
  void setCursorBlink() => _record('setCursorBlink');

  @override
  void setCursorInverse() => _record('setCursorInverse');

  @override
  void setCursorInvisible() => _record('setCursorInvisible');

  @override
  void setCursorStrikethrough() => _record('setCursorStrikethrough');

  @override
  void unsetCursorBold() => _record('unsetCursorBold');

  @override
  void unsetCursorFaint() => _record('unsetCursorFaint');

  @override
  void unsetCursorItalic() => _record('unsetCursorItalic');

  @override
  void unsetCursorUnderline() => _record('unsetCursorUnderline');

  @override
  void unsetCursorBlink() => _record('unsetCursorBlink');

  @override
  void unsetCursorInverse() => _record('unsetCursorInverse');

  @override
  void unsetCursorInvisible() => _record('unsetCursorInvisible');

  @override
  void unsetCursorStrikethrough() => _record('unsetCursorStrikethrough');

  @override
  void setForegroundColor16(int color) => _record('setForegroundColor16', [color]);

  @override
  void setForegroundColor256(int index) =>
      _record('setForegroundColor256', [index]);

  @override
  void setForegroundColorRgb(int r, int g, int b) =>
      _record('setForegroundColorRgb', [r, g, b]);

  @override
  void resetForeground() => _record('resetForeground');

  @override
  void setBackgroundColor16(int color) => _record('setBackgroundColor16', [color]);

  @override
  void setBackgroundColor256(int index) =>
      _record('setBackgroundColor256', [index]);

  @override
  void setBackgroundColorRgb(int r, int g, int b) =>
      _record('setBackgroundColorRgb', [r, g, b]);

  @override
  void resetBackground() => _record('resetBackground');

  @override
  void unsupportedStyle(int param) => _record('unsupportedStyle', [param]);

  /* OSC */

  @override
  void setTitle(String name) => _record('setTitle', [name]);

  @override
  void setIconName(String name) => _record('setIconName', [name]);

  @override
  void unknownOSC(String code, List<String> args) =>
      _record('unknownOSC', [code, args.join('|')]);
}
