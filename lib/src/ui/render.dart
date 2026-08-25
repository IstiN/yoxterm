import 'dart:async';
import 'dart:math' show max;
import 'dart:ui';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:yoxterm/src/core/buffer/cell_offset.dart';
import 'package:yoxterm/src/core/buffer/range.dart';
import 'package:yoxterm/src/core/buffer/segment.dart';
import 'package:yoxterm/src/core/mouse/button.dart';
import 'package:yoxterm/src/core/mouse/button_state.dart';
import 'package:yoxterm/src/terminal.dart';
import 'package:yoxterm/src/ui/controller.dart';
import 'package:yoxterm/src/ui/cursor_type.dart';
import 'package:yoxterm/src/ui/painter.dart';
import 'package:yoxterm/src/ui/selection_mode.dart';
import 'package:yoxterm/src/ui/terminal_size.dart';
import 'package:yoxterm/src/ui/terminal_text_style.dart';
import 'package:yoxterm/src/ui/terminal_theme.dart';

typedef EditableRectCallback = void Function(Rect rect, Rect caretRect);

class RenderTerminal extends RenderBox with RelayoutWhenSystemFontsChangeMixin {
  RenderTerminal({
    required Terminal terminal,
    required TerminalController controller,
    required ViewportOffset offset,
    required EdgeInsets padding,
    required bool autoResize,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
    required TerminalTheme theme,
    required FocusNode focusNode,
    required TerminalCursorType cursorType,
    required bool alwaysShowCursor,
    EditableRectCallback? onEditableRect,
    ValueGetter<bool>? inputConnectionOpen,
    String? composingText,
  })  : _terminal = terminal,
        _controller = controller,
        _offset = offset,
        _padding = padding,
        _autoResize = autoResize,
        _focusNode = focusNode,
        _cursorType = cursorType,
        _alwaysShowCursor = alwaysShowCursor,
        _onEditableRect = onEditableRect,
        _inputConnectionOpen = inputConnectionOpen,
        _composingText = composingText,
        _painter = TerminalPainter(
          theme: theme,
          textStyle: textStyle,
          textScaler: textScaler,
        );

  bool _layoutPending = false;

  /// Pending size when a resize is debounced (alt-buffer or large scrollback).
  Timer? _altResizeDebounce;
  TerminalSize? _pendingViewportSize;

  /// Output-driven repaints are capped at ~60fps. On 120Hz ProMotion
  /// displays the engine would otherwise repaint the whole visible buffer on
  /// every vsync while output streams, doubling UI-thread, raster and GC cost
  /// with no perceptible benefit (terminal text is unreadable above ~30fps
  /// anyway). The throttle keys off actual [paint] timestamps, so it stays
  /// inert on 60Hz displays (vsync already spaces paints by ~16.7ms) and in
  /// widget tests (pumps are farther apart than the interval, so
  /// [markNeedsPaint] is always called synchronously there).
  static const _minOutputPaintInterval = Duration(milliseconds: 16);
  DateTime _lastOutputPaint = DateTime.fromMillisecondsSinceEpoch(0);

  /// Set when a paint is scheduled for the current frame via
  /// [_scheduleOutputPaint]. Cleared at the very end of the
  /// [paint] pass — a different lifecycle than the previous
  /// `_outputPaintScheduled`, which was cleared inside the frame callback.
  /// Holding the flag past the transientCallbacks/layout/paint phases
  /// guarantees the writes that land in any of those synchronous phases
  /// still see "scheduled" and noop instead of re-arming another
  /// frame callback.
  bool _paintScheduled = false;

  /// Two-phase paint (ghostty beginUpdate/endUpdate port): the static text
  /// layer of the viewport — background fill plus every visible line — is
  /// recorded into a single [Picture] and replayed with one `drawPicture`
  /// call, while only the dynamic overlay (cursor, composing text,
  /// selection, highlights) is re-drawn from Dart on each repaint. A repaint
  /// that changes nothing below the overlay (cursor blink, selection drag,
  /// focus change) then costs exactly one native picture dispatch instead of
  /// a per-line walk.
  Picture? _framePicture;

  /// Scroll offset the frame picture was recorded at.
  double _framePictureScroll = 0;

  /// Set when a repaint arrives with a terminal/controller change that can
  /// alter line content (any terminal notification, theme, or resize). The
  /// next [paint] re-records the frame picture after replaying the lines
  /// once to refresh the painter's per-line cache.
  bool _framePictureDirty = true;

  /// Monotonic counters for tests (see render_frame_picture_test.dart).
  @visibleForTesting
  int debugFramePictureRebuilds = 0;
  @visibleForTesting
  int debugFramePictureHits = 0;

  /// Cumulative number of [paint] calls since the last
  /// [debugResetPaintCounter]. Exposed so throttle coalescing tests can
  /// observe actual paint cost without wiring a custom paint callback.
  @visibleForTesting
  int debugPaintCount = 0;

  /// Resets [debugPaintCount] to 0. Tests call this after the initial pump
  /// so the counter only reflects paints produced by the scenario under
  /// test, not the attach/layout pass.
  @visibleForTesting
  void debugResetPaintCounter() {
    debugPaintCount = 0;
  }

  /// Read-only view of the output-paint throttle interval. Exposed so
  /// tests can observe the period without tying to the private field.
  @visibleForTesting
  Duration get debugMinOutputPaintInterval => _minOutputPaintInterval;

  /// Number of scrollback lines above which main-buffer resizes are debounced.
  static const _largeScrollbackThreshold = 100;

  /// Reusable Paint for the per-frame background fill. Canvas records the
  /// paint's attributes synchronously, so one mutable instance is enough.
  final _backgroundPaint = Paint()..isAntiAlias = false;

  Terminal _terminal;
  set terminal(Terminal terminal) {
    if (_terminal == terminal) return;
    if (attached) _terminal.removeListener(_onTerminalChange);
    _terminal = terminal;
    if (attached) _terminal.addListener(_onTerminalChange);
    _framePictureDirty = true;
    _resizeTerminalIfNeeded();
    markNeedsLayout();
    markNeedsPaint();
  }

  TerminalController _controller;
  set controller(TerminalController controller) {
    if (_controller == controller) return;
    if (attached) _controller.removeListener(_onControllerUpdate);
    _controller = controller;
    if (attached) _controller.addListener(_onControllerUpdate);
    markNeedsLayout();
    markNeedsPaint();
  }

  ViewportOffset _offset;
  set offset(ViewportOffset value) {
    if (value == _offset) return;
    if (attached) _offset.removeListener(_onScroll);
    _offset = value;
    if (attached) _offset.addListener(_onScroll);
    markNeedsLayout();
  }

  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  bool _autoResize;
  set autoResize(bool value) {
    if (value == _autoResize) return;
    _autoResize = value;
    markNeedsLayout();
  }

  set textStyle(TerminalStyle value) {
    if (value == _painter.textStyle) return;
    _painter.textStyle = value;
    _framePictureDirty = true;
    markNeedsLayout();
  }

  set textScaler(TextScaler value) {
    if (value == _painter.textScaler) return;
    _painter.textScaler = value;
    _framePictureDirty = true;
    markNeedsLayout();
  }

  set theme(TerminalTheme value) {
    if (value == _painter.theme) return;
    _painter.theme = value;
    _framePictureDirty = true;
    markNeedsPaint();
  }

  FocusNode _focusNode;
  set focusNode(FocusNode value) {
    if (value == _focusNode) return;
    if (attached) _focusNode.removeListener(_onFocusChange);
    _focusNode = value;
    if (attached) _focusNode.addListener(_onFocusChange);
    markNeedsPaint();
  }

  TerminalCursorType _cursorType;
  set cursorType(TerminalCursorType value) {
    if (value == _cursorType) return;
    _cursorType = value;
    markNeedsPaint();
  }

  bool _alwaysShowCursor;
  set alwaysShowCursor(bool value) {
    if (value == _alwaysShowCursor) return;
    _alwaysShowCursor = value;
    markNeedsPaint();
  }

  EditableRectCallback? _onEditableRect;
  set onEditableRect(EditableRectCallback? value) {
    if (value == _onEditableRect) return;
    _onEditableRect = value;
    markNeedsLayout();
  }

  /// Whether an IME input connection is currently open. The editable-rect
  /// consumer ([_onEditableRect]) only forwards geometry to that connection,
  /// so when this reports false [_notifyEditableRect] skips its
  /// localToGlobal/Rect math entirely. A getter (queried per notify) rather
  /// than a plain bool because the connection opens and closes on focus
  /// changes without a render-object update. Null means "unknown" and keeps
  /// the geometry math (used by tests that drive [RenderTerminal] directly).
  ValueGetter<bool>? _inputConnectionOpen;
  set inputConnectionOpen(ValueGetter<bool>? value) {
    // Assignment only: this gates a side-channel callback, not layout/paint.
    _inputConnectionOpen = value;
  }

  String? _composingText;
  set composingText(String? value) {
    if (value == _composingText) return;
    _composingText = value;
    markNeedsPaint();
  }

  TerminalSize? _viewportSize;

  final TerminalPainter _painter;

  var _stickToBottom = true;

  void _onScroll() {
    // Half-line tolerance: landing a hair short of the live max (fractional
    // cell metrics, or a programmatic jump clamped to the framework-cached
    // extent while the buffer already grew) still counts as "at the bottom",
    // so follow mode re-engages instead of silently dropping out.
    _stickToBottom =
        _scrollOffset >= _maxScrollExtent - _painter.cellSize.height / 2;
    _framePictureDirty = true;
    markNeedsLayout();
    _notifyEditableRect();
  }

  void _onFocusChange() {
    markNeedsPaint();
  }

  void _scheduleLayout() {
    if (_layoutPending) return;
    _layoutPending = true;
    // Layout piggybacks on the same frame callback that fires
    // [_scheduleOutputPaint] (see [_runPendingLayoutAndPaint]). The previous
    // implementation scheduled a postFrame callback that called markNeedsLayout
    // on the NEXT frame, and that layout pass produced a second paint per
    // write burst via the repaint-boundary cascade. Combining layout and paint
    // into a single transientCallbacks phase keeps them in lockstep: the layout
    // pass runs in the same frame as the paint that needs the new geometry, so
    // no cascade paint is produced.
  }

  void _onTerminalChange() {
    _framePictureDirty = true;
    _scheduleLayout();
    _scheduleOutputPaint();
    _notifyEditableRect();
  }

  /// Rate-limits output-driven repaints (see [_minOutputPaintInterval]).
  /// Scroll, selection and other user-driven repaints bypass this throttle.
  void _scheduleOutputPaint() {
    if (_paintScheduled) return;
    _paintScheduled = true;
    final elapsed = DateTime.now().difference(_lastOutputPaint);
    if (elapsed >= _minOutputPaintInterval) {
      _runPendingLayoutAndPaint();
      return;
    }
    // A frame callback (not a Timer) keeps widget tests free of pending-timer
    // failures and piggybacks on the next scheduled frame instead of forcing
    // an extra one.
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _runPendingLayoutAndPaint();
    });
  }

  /// Mark both layout and paint dirty in a single transient-callback phase.
  /// The previous split (`_scheduleLayout`'s postFrame to `markNeedsLayout`,
  /// then a layout pass on the following frame) leaked an extra paint per
  /// write burst — see the cascade detection in
  /// `test/src/ui/render_paint_throttle_test.dart`. Bundling layout and paint
  /// into the same frame callback keeps them in lockstep: one paint per
  /// throttle cycle.
  void _runPendingLayoutAndPaint() {
    _paintScheduled = false;
    if (!attached) return;
    final hadPendingLayout = _layoutPending;
    _layoutPending = false;
    if (hadPendingLayout) markNeedsLayout();
    markNeedsPaint();
  }

  void _onControllerUpdate() {
    _scheduleLayout();
    markNeedsPaint();
  }

  @override
  final isRepaintBoundary = true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _offset.addListener(_onScroll);
    _terminal.addListener(_onTerminalChange);
    _controller.addListener(_onControllerUpdate);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void detach() {
    super.detach();
    _altResizeDebounce?.cancel();
    _altResizeDebounce = null;
    _framePicture?.dispose();
    _framePicture = null;
    _offset.removeListener(_onScroll);
    _terminal.removeListener(_onTerminalChange);
    _controller.removeListener(_onControllerUpdate);
    _focusNode.removeListener(_onFocusChange);
  }

  @override
  bool hitTestSelf(Offset position) {
    return true;
  }

  @override
  void systemFontsDidChange() {
    _painter.clearFontCache();
    _framePictureDirty = true;
    super.systemFontsDidChange();
  }

  @override
  void performLayout() {
    size = constraints.biggest;

    _framePictureDirty = true;
    _updateViewportSize();

    _updateScrollOffset();

    if (_stickToBottom) {
      _offset.correctBy(_maxScrollExtent - _scrollOffset);
    }
  }

  /// Total height of the terminal in pixels. Includes scrollback buffer.
  double get _terminalHeight =>
      _terminal.buffer.lines.length * _painter.cellSize.height;

  /// The distance from the top of the terminal to the top of the viewport.
  // double get _scrollOffset => _offset.pixels;
  double get _scrollOffset {
    // return _offset.pixels ~/ _painter.cellSize.height * _painter.cellSize.height;
    return _offset.pixels;
  }

  /// The height of a terminal line in pixels. This includes the line spacing.
  /// Height of the entire terminal is expected to be a multiple of this value.
  double get lineHeight => _painter.cellSize.height;

  /// Get the top-left corner of the cell at [cellOffset] in pixels.
  Offset getOffset(CellOffset cellOffset) {
    final row = cellOffset.y;
    final col = cellOffset.x;
    final x = col * _painter.cellSize.width;
    final y = row * _painter.cellSize.height;
    return Offset(x + _padding.left, y + _padding.top - _scrollOffset);
  }

  /// Get the [CellOffset] of the cell that [offset] is in.
  CellOffset getCellOffset(Offset offset) {
    final x = offset.dx - _padding.left;
    final y = offset.dy - _padding.top + _scrollOffset;
    final row = y ~/ _painter.cellSize.height;
    final col = x ~/ _painter.cellSize.width;
    return CellOffset(
      col.clamp(0, _terminal.viewWidth - 1),
      row.clamp(0, _terminal.buffer.lines.length - 1),
    );
  }

  /// Selects entire words in the terminal that contains [from] and [to].
  void selectWord(Offset from, [Offset? to]) {
    final fromOffset = getCellOffset(from);
    final fromBoundary = _terminal.buffer.getWordBoundary(fromOffset);
    if (fromBoundary == null) return;
    if (to == null) {
      _controller.setSelection(
        _terminal.buffer.createAnchorFromOffset(fromBoundary.begin),
        _terminal.buffer.createAnchorFromOffset(fromBoundary.end),
        mode: SelectionMode.line,
      );
    } else {
      final toOffset = getCellOffset(to);
      final toBoundary = _terminal.buffer.getWordBoundary(toOffset);
      if (toBoundary == null) return;
      final range = fromBoundary.merge(toBoundary);
      _controller.setSelection(
        _terminal.buffer.createAnchorFromOffset(range.begin),
        _terminal.buffer.createAnchorFromOffset(range.end),
        mode: SelectionMode.line,
      );
    }
  }

  /// Selects characters in the terminal that starts from [from] to [to].
  /// When [to] is omitted, a zero-cell caret selection is created at [from].
  /// When [to] is at or after [from], the end is extended by one cell, so at
  /// least one cell is selected even if [from] and [to] are the same.
  void selectCharacters(Offset from, [Offset? to]) {
    final fromPosition = getCellOffset(from);
    if (to == null) {
      _controller.setSelection(
        _terminal.buffer.createAnchorFromOffset(fromPosition),
        _terminal.buffer.createAnchorFromOffset(fromPosition),
      );
    } else {
      var toPosition = getCellOffset(to);
      if (toPosition.x >= fromPosition.x) {
        toPosition = CellOffset(toPosition.x + 1, toPosition.y);
      }
      _controller.setSelection(
        _terminal.buffer.createAnchorFromOffset(fromPosition),
        _terminal.buffer.createAnchorFromOffset(toPosition),
      );
    }
  }

  /// Send a mouse event at [offset] with [button] being currently in [buttonState].
  bool mouseEvent(
    TerminalMouseButton button,
    TerminalMouseButtonState buttonState,
    Offset offset,
  ) {
    final position = getCellOffset(offset);
    return _terminal.mouseInput(button, buttonState, position);
  }

  void _notifyEditableRect() {
    final onEditableRect = _onEditableRect;
    // Skip the localToGlobal/Rect math entirely when nobody is listening.
    if (onEditableRect == null) return;
    // The consumer only forwards the rect to an open IME input connection —
    // skip the geometry math while no connection is open.
    final inputConnectionOpen = _inputConnectionOpen;
    if (inputConnectionOpen != null && !inputConnectionOpen()) return;

    final cursor = localToGlobal(cursorOffset);

    final rect = Rect.fromLTRB(
      cursor.dx,
      cursor.dy,
      size.width,
      cursor.dy + _painter.cellSize.height,
    );

    final caretRect = cursor & _painter.cellSize;

    onEditableRect(rect, caretRect);
  }

  /// Update the viewport size in cells based on the current widget size in
  /// pixels.
  void _updateViewportSize() {
    if (size <= _painter.cellSize) {
      return;
    }

    final viewportSize = TerminalSize(
      size.width ~/ _painter.cellSize.width,
      _viewportHeight ~/ _painter.cellSize.height,
    );

    if (_viewportSize != viewportSize) {
      _viewportSize = viewportSize;
      _resizeTerminalIfNeeded();
    }
  }

  /// Notify the underlying terminal that the viewport size has changed.
  void _resizeTerminalIfNeeded() {
    if (!_autoResize || _viewportSize == null) return;
    final size = _viewportSize!;

    // Alt-buffer (full-screen TUI): debounce 200ms to avoid corrupting the TUI
    // layout during a panel drag.
    //
    // Main buffer with large scrollback: a short 60ms debounce keeps
    // continuous drag frames from triggering an O(maxLines) reflow each
    // layout, while making one-shot window/board-switch resizes settle
    // within a frame or two instead of leaving the panel visibly black
    // below the new viewport for 150ms+.
    // Sessions with <= _largeScrollbackThreshold lines of scrollback are
    // resized immediately (cheap: no reflow work).
    final scrollBack = _terminal.lines.length - _terminal.viewHeight;
    final needsDebounce =
        _terminal.isUsingAltBuffer || scrollBack > _largeScrollbackThreshold;

    if (needsDebounce) {
      _pendingViewportSize = size;
      _altResizeDebounce?.cancel();
      final delay = _terminal.isUsingAltBuffer
          ? const Duration(milliseconds: 200)
          : const Duration(milliseconds: 60);
      _altResizeDebounce = Timer(delay, () {
        final pending = _pendingViewportSize;
        _pendingViewportSize = null;
        if (pending != null) {
          _terminal.resize(
            pending.width,
            pending.height,
            _painter.cellSize.width.round(),
            _painter.cellSize.height.round(),
          );
        }
      });
      return;
    }

    _altResizeDebounce?.cancel();
    _altResizeDebounce = null;
    _terminal.resize(
      size.width,
      size.height,
      _painter.cellSize.width.round(),
      _painter.cellSize.height.round(),
    );
  }

  /// Re-applies the current viewport size to the terminal even when this
  /// render object's own size did not change. Needed when another widget
  /// attached to the same terminal resized it to different dimensions (e.g.
  /// a fullscreen view was closed and this widget became the active binding
  /// again): without this, the terminal keeps the other widget's dimensions
  /// and this viewport renders stale/clipped content until the next manual
  /// resize. Also re-clamps the scroll offset and requests a repaint.
  void forceResizeTerminal() {
    if (!_autoResize || _viewportSize == null) return;
    _altResizeDebounce?.cancel();
    _altResizeDebounce = null;
    _pendingViewportSize = null;
    _terminal.resize(
      _viewportSize!.width,
      _viewportSize!.height,
      _painter.cellSize.width.round(),
      _painter.cellSize.height.round(),
    );
    _framePictureDirty = true;
    _updateScrollOffset();
    markNeedsPaint();
  }

  /// Update the scroll offset based on the current terminal state. This should
  /// be called in [performLayout] after the viewport size has been updated.
  void _updateScrollOffset() {
    _offset.applyViewportDimension(_viewportHeight);
    _offset.applyContentDimensions(0, _maxScrollExtent);
  }

  bool get _isComposingText {
    return _composingText != null && _composingText!.isNotEmpty;
  }

  bool get _shouldShowCursor {
    return _terminal.cursorVisibleMode || _alwaysShowCursor || _isComposingText;
  }

  double get _viewportHeight {
    return size.height - _padding.vertical;
  }

  double get _maxScrollExtent {
    return max(_terminalHeight - _viewportHeight, 0.0);
  }

  /// The live maximum scroll extent, computed from the current buffer height.
  ///
  /// The framework-cached `ScrollPosition.maxScrollExtent` lags behind this
  /// value by at least a frame while output streams in, because terminal
  /// changes only mark layout dirty (applied on the next frame). Programmatic
  /// "scroll to bottom" jumps should target this value so they land at the
  /// real bottom and keep stick-to-bottom follow engaged.
  double get maxScrollExtentLive => hasSize ? _maxScrollExtent : 0.0;

  double get _lineOffset {
    return -_scrollOffset + _padding.top;
  }

  /// The offset of the cursor from the top left corner of this render object.
  Offset get cursorOffset {
    final dpr = PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
    final rawX = _terminal.buffer.cursorX * _painter.cellSize.width;
    final snappedX = dpr > 0 ? (rawX * dpr).roundToDouble() / dpr : rawX;
    return Offset(
      snappedX,
      _terminal.buffer.absoluteCursorY * _painter.cellSize.height + _lineOffset,
    );
  }

  Size get cellSize {
    return _painter.cellSize;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _lastOutputPaint = DateTime.now();
    debugPaintCount++;
    _paint(context, offset);
    // Hint that this picture is expensive to rasterize so the engine keeps it
    // in the raster cache while it is unchanged (board pan/zoom, overlays,
    // animations elsewhere). The will-change hint used here before permanently
    // disabled caching of this layer — it is a cache hint only and never
    // gated repaints: buffer changes still trigger markNeedsPaint via
    // _onTerminalChange, which produces a new picture that simply evicts the
    // stale cache entry.
    context.setIsComplexHint();
    // Mark the throttle as fully consumed: any synchronous terminal change
    // that landed after [_runPendingLayoutAndPaint] ran during
    // transientCallbacks now sees the flag false and can arm a new frame
    // callback. Resetting here (instead of inside the frame callback) keeps
    // the burst from re-arming mid-paint.
    _paintScheduled = false;
  }

  void _paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final paintBounds = offset & size;
    canvas.save();
    canvas.clipRect(paintBounds);

    final lines = _terminal.buffer.lines;
    final charHeight = _painter.cellSize.height;

    final firstLineOffset = _scrollOffset - _padding.top;
    final lastLineOffset = _scrollOffset + size.height + _padding.bottom;

    final firstLine = firstLineOffset ~/ charHeight;
    final lastLine = lastLineOffset ~/ charHeight;

    final effectFirstLine = firstLine.clamp(0, lines.length - 1);
    final effectLastLine = lastLine.clamp(0, lines.length - 1);

    // Phase 1 (record): when anything that feeds the static layer changed,
    // re-record background + every visible line into a single Picture. The
    // per-line painter cache stays warm inside the recording pass, so a
    // rebuild costs exactly the per-line walk plus the recording itself.
    final framePicture = _framePicture;
    if (_framePictureDirty ||
        framePicture == null ||
        _framePictureScroll != _scrollOffset) {
      _framePicture?.dispose();
      final recorder = PictureRecorder();
      final recordCanvas = Canvas(recorder);
      // Use isAntiAlias=false for solid background fills so they have sharp
      // pixel-perfect edges even when the board canvas has a fractional
      // scale.
      recordCanvas.drawRect(
        paintBounds,
        _backgroundPaint..color = _painter.theme.background,
      );
      // Collect missing glyphs across all visible lines and rebuild the
      // atlas at most once, before any line references the new tiles.
      _painter.prepareLineGlyphs(
          recordCanvas, lines, effectFirstLine, effectLastLine);
      for (var i = effectFirstLine; i <= effectLastLine; i++) {
        _painter.paintLine(
          recordCanvas,
          offset.translate(0, i * charHeight + _lineOffset),
          lines[i],
        );
      }
      _framePicture = recorder.endRecording();
      _framePictureScroll = _scrollOffset;
      _framePictureDirty = false;
      debugFramePictureRebuilds++;
    } else {
      debugFramePictureHits++;
    }

    // Phase 2 (replay + overlay): one native drawPicture for the whole
    // static text layer, then only the dynamic overlay from Dart (cursor,
    // composing text, selection, highlights).
    canvas.drawPicture(_framePicture!);

    if (_terminal.buffer.absoluteCursorY >= effectFirstLine &&
        _terminal.buffer.absoluteCursorY <= effectLastLine) {
      if (_isComposingText) {
        _paintComposingText(canvas, offset + cursorOffset);
      }

      if (_shouldShowCursor) {
        _painter.paintCursor(
          canvas,
          offset + cursorOffset,
          cursorType: _cursorType,
          hasFocus: _focusNode.hasFocus,
        );
      }
    }

    _paintHighlights(
      canvas,
      _controller.highlights,
      effectFirstLine,
      effectLastLine,
    );

    if (_controller.selection != null) {
      _paintSelection(
        canvas,
        _controller.selection!,
        effectFirstLine,
        effectLastLine,
      );
    }

    canvas.restore();
  }

  /// Paints the text that is currently being composed in IME to [canvas] at
  /// [offset]. [offset] is usually the cursor position.
  void _paintComposingText(Canvas canvas, Offset offset) {
    final composingText = _composingText;
    if (composingText == null) {
      return;
    }

    final style = _painter.textStyle.toTextStyle(
      color: _painter.resolveForegroundColor(_terminal.cursor.foreground),
      backgroundColor: _painter.theme.background,
      underline: true,
    );

    final builder = ParagraphBuilder(style.getParagraphStyle());
    builder.addPlaceholder(
      offset.dx,
      _painter.cellSize.height,
      PlaceholderAlignment.middle,
    );
    builder.pushStyle(
      style.getTextStyle(textScaler: _painter.textScaler),
    );
    builder.addText(composingText);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: size.width));

    canvas.drawParagraph(paragraph, Offset(0, offset.dy));
  }

  void _paintSelection(
    Canvas canvas,
    BufferRange selection,
    int firstLine,
    int lastLine,
  ) {
    for (final segment in selection.toSegments()) {
      if (segment.line >= _terminal.buffer.lines.length) {
        break;
      }

      if (segment.line < firstLine) {
        continue;
      }

      if (segment.line > lastLine) {
        break;
      }

      _paintSegment(canvas, segment, _painter.theme.selection);
    }
  }

  void _paintHighlights(
    Canvas canvas,
    List<TerminalHighlight> highlights,
    int firstLine,
    int lastLine,
  ) {
    for (var highlight in highlights) {
      final range = highlight.range?.normalized;

      if (range == null ||
          range.begin.y > lastLine ||
          range.end.y < firstLine) {
        continue;
      }

      for (var segment in range.toSegments()) {
        if (segment.line < firstLine) {
          continue;
        }

        if (segment.line > lastLine) {
          break;
        }

        _paintSegment(canvas, segment, highlight.color);
      }
    }
  }

  @pragma('vm:prefer-inline')
  void _paintSegment(Canvas canvas, BufferSegment segment, Color color) {
    final start = segment.start ?? 0;
    final end = segment.end ?? _terminal.viewWidth;

    final startOffset = Offset(
      start * _painter.cellSize.width,
      segment.line * _painter.cellSize.height + _lineOffset,
    );

    _painter.paintHighlight(canvas, startOffset, end - start, color);
  }
}
