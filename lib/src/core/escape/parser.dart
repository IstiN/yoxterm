import 'package:yoxterm/src/core/color.dart';
import 'package:yoxterm/src/core/mouse/mode.dart';
import 'package:yoxterm/src/core/escape/handler.dart';
import 'package:yoxterm/src/utils/ascii.dart';
import 'package:yoxterm/src/utils/byte_consumer.dart';
import 'package:yoxterm/src/utils/char_code.dart';
import 'package:yoxterm/src/utils/lookup_table.dart';

/// [EscapeParser] translates control characters and escape sequences into
/// function calls that the terminal can handle.
///
/// Design goals:
///  * Zero object allocation during processing.
///  * Persistent state: an escape sequence split across [write] calls is
///    parsed incrementally. The partially parsed state is kept between calls,
///    so the completed prefix is never rolled back and re-parsed.
class EscapeParser {
  final EscapeHandler handler;

  EscapeParser(this.handler)
      : _textRunHandler =
            handler is TextRunHandler ? handler as TextRunHandler : null;

  final _queue = ByteConsumer();

  /// [handler] cast to [TextRunHandler] when it supports bulk text delivery,
  /// null otherwise.
  final TextRunHandler? _textRunHandler;

  /// Parser state persisted across [write] calls. Anything but
  /// [_ParserState.ground] means an escape sequence is only partially
  /// consumed and will be continued by the next chunk.
  var _state = _ParserState.ground;

  /// Start of sequence or character being processed. Useful for debugging.
  var tokenBegin = 0;

  /// Start of the escape sequence currently being accumulated, used to keep
  /// [tokenBegin]/[tokenEnd] pointing at the whole sequence once it completes.
  var _sequenceBegin = 0;

  /// End of sequence or character being processed. Useful for debugging.
  /// While a sequence is incomplete this stays at the sequence start, so a
  /// held-back sequence does not advance the token position.
  int get tokenEnd =>
      _state == _ParserState.ground ? _queue.totalConsumed : _sequenceBegin;

  /// Whether the parser is holding back input from previous [write] calls:
  /// an incomplete escape sequence or the high half of a surrogate pair
  /// split across chunks. While this is true, new input must go through the
  /// parser so the held-back bytes are not reordered behind it.
  bool get hasPendingInput =>
      _state != _ParserState.ground ||
      _queue.isNotEmpty ||
      _queue.hasPendingSurrogate;

  void write(String chunk) {
    _queue.unrefConsumedBlocks();
    _queue.add(chunk);
    _process();
  }

  /// Feeds already-decoded Unicode code points into the parser, taking
  /// ownership of [codepoints]: the caller must not mutate or reuse the list
  /// afterwards. This is the entry point of the byte-level input path
  /// ([Terminal.writeBytes]), where UTF-8 decoding happens upstream of the
  /// parser and no String materializes at all.
  void writeCodepoints(List<int> codepoints) {
    _queue.unrefConsumedBlocks();
    _queue.addCodepoints(codepoints);
    _process();
  }

  void _process() {
    while (true) {
      switch (_state) {
        case _ParserState.ground:
          if (_queue.isEmpty) return;

          final runHandler = _textRunHandler;
          if (runHandler != null) {
            // Bulk path: scan the maximal run of literal text in the head
            // block and deliver it in one call, without per-character
            // consume bookkeeping. Only characters with a parser-level
            // dispatch — C0 controls below 0x10 and ESC — stop a run;
            // everything else (including DEL, C1 and 0x10–0x1A, which
            // _processChar forwards to writeChar) is text.
            final head = _queue.headBlock;
            final start = _queue.headOffset;
            var end = start;
            while (end < head.length) {
              final next = head[end];
              if (next <= 0x0F || next == Ascii.ESC) break;
              end++;
            }
            if (end > start) {
              tokenBegin = _queue.totalConsumed;
              _queue.advance(end - start);
              runHandler.writeChars(head, start, end);
              break;
            }

            // The head character is a C0 control or ESC: dispatch it
            // directly — the scan already read it.
            tokenBegin = _queue.totalConsumed;
            if (start < head.length) {
              final char = head[start];
              _queue.advance(1);
              _dispatchGroundChar(char);
            } else {
              // The head block was exhausted by consume()-based sequence
              // parsing (consume() pops blocks lazily); let consume() move
              // to the next block.
              _dispatchGroundChar(_queue.consume());
            }
            break;
          }

          tokenBegin = _queue.totalConsumed;
          final char = _queue.consume();
          _dispatchGroundChar(char);
          break;
        case _ParserState.esc:
          if (_queue.isEmpty) return;
          _processEscapeChar(_queue.consume());
          break;
        case _ParserState.csi:
          if (!_processCsiState()) return;
          break;
        case _ParserState.osc:
          if (!_consumeOsc()) return;
          _finishSequence();
          _dispatchOsc();
          break;
        case _ParserState.charset0:
          if (_queue.isEmpty) return;
          final name = _queue.consume();
          _finishSequence();
          handler.designateCharset(0, name);
          break;
        case _ParserState.charset1:
          if (_queue.isEmpty) return;
          final name = _queue.consume();
          _finishSequence();
          handler.designateCharset(1, name);
          break;
      }
    }
  }

  /// Marks the current escape sequence as fully processed and returns the
  /// parser to the ground state. Called before the sequence's handler
  /// callback runs, so callbacks that inspect [tokenBegin]/[tokenEnd] see the
  /// completed sequence's range.
  void _finishSequence() {
    tokenBegin = _sequenceBegin;
    _state = _ParserState.ground;
  }

  /// Dispatches a single character consumed in the ground state: [Ascii.ESC]
  /// enters the escape state, everything else goes to [_processChar].
  void _dispatchGroundChar(int char) {
    if (char == Ascii.ESC) {
      _sequenceBegin = tokenBegin;
      _state = _ParserState.esc;
    } else {
      _processChar(char);
    }
  }

  void _processChar(int char) {
    if (char > _sbcHandlers.maxIndex) {
      handler.writeChar(char);
      return;
    }

    final sbcHandler = _sbcHandlers[char];
    if (sbcHandler == null) {
      handler.unkownEscape(char);
      return;
    }

    sbcHandler();
  }

  /// Dispatches the character following an escape character to the
  /// corresponding handler. Handlers either complete the sequence (via
  /// [_finishSequence]) or switch [_state] to keep parsing with the next
  /// chunk.
  void _processEscapeChar(int escapeChar) {
    final escapeHandler = _escHandlers[escapeChar];

    if (escapeHandler == null) {
      _finishSequence();
      handler.unkownEscape(escapeChar);
      return;
    }

    escapeHandler();
  }

  late final _sbcHandlers = FastLookupTable<_SbcHandler>({
    0x07: handler.bell,
    0x08: handler.backspaceReturn,
    0x09: handler.tab,
    0x0a: handler.lineFeed,
    0x0b: handler.lineFeed,
    0x0c: handler.lineFeed,
    0x0d: handler.carriageReturn,
    0x0e: handler.shiftOut,
    0x0f: handler.shiftIn,
  });

  late final _escHandlers = FastLookupTable<_EscHandler>({
    '['.charCode: _escHandleCSI,
    ']'.charCode: _escHandleOSC,
    '7'.charCode: _escHandleSaveCursor,
    '8'.charCode: _escHandleRestoreCursor,
    'D'.charCode: _escHandleIndex,
    'E'.charCode: _escHandleNextLine,
    'H'.charCode: _escHandleTabSet,
    'M'.charCode: _escHandleReverseIndex,
    // 'P'.charCode: _unsupportedHandler, // Sixel
    // 'c'.charCode: _unsupportedHandler,
    // '#'.charCode: _unsupportedHandler,
    '('.charCode: _escHandleDesignateCharset0, //  SCS - G0
    ')'.charCode: _escHandleDesignateCharset1, //  SCS - G1
    // '*'.charCode: _voidHandler(1), // TODO: G2 (vt220)
    // '+'.charCode: _voidHandler(1), // TODO: G3 (vt220)
    '>'.charCode: _escHandleResetAppKeypadMode, // TODO: Normal Keypad
    '='.charCode: _escHandleSetAppKeypadMode, // TODO: Application Keypad
  });

  /// `ESC 7` Save Cursor (DECSC)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_a7/
  void _escHandleSaveCursor() {
    _finishSequence();
    handler.saveCursor();
  }

  /// `ESC 8` Restore Cursor (DECRC)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_a8/
  void _escHandleRestoreCursor() {
    _finishSequence();
    handler.restoreCursor();
  }

  /// `ESC D` Index (IND)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_cd/
  void _escHandleIndex() {
    _finishSequence();
    handler.index();
  }

  /// `ESC E` Next Line (NEL)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_ce/
  void _escHandleNextLine() {
    _finishSequence();
    handler.nextLine();
  }

  /// `ESC H` Horizontal Tab Set (HTS)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_ch/
  void _escHandleTabSet() {
    _finishSequence();
    handler.setTapStop();
  }

  /// `ESC M` Reverse Index (RI)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_cm/
  void _escHandleReverseIndex() {
    _finishSequence();
    handler.reverseIndex();
  }

  void _escHandleDesignateCharset0() {
    // The charset name arrives with the next input; see the charset0 state.
    _state = _ParserState.charset0;
  }

  void _escHandleDesignateCharset1() {
    // The charset name arrives with the next input; see the charset1 state.
    _state = _ParserState.charset1;
  }

  /// `ESC =` Set Application Keypad Mode (DECKPAM)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_x3d_equals/
  void _escHandleSetAppKeypadMode() {
    _finishSequence();
    handler.setAppKeypadMode(true);
  }

  /// `ESC >` Reset Application Keypad Mode (DECKPNM)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_x3c_greater_than/
  void _escHandleResetAppKeypadMode() {
    _finishSequence();
    handler.setAppKeypadMode(false);
  }

  void _escHandleCSI() {
    // Reset the accumulated CSI state and keep parsing in the csi state,
    // possibly across chunk boundaries.
    _csi.params.clear();
    _csi.prefix = null;
    _csiPrefixParsed = false;
    _csiParam = 0;
    _csiHasParam = false;
    _state = _ParserState.csi;
  }

  /// The last parsed [_Csi]. This is a mutable singletion by design to reduce
  /// object allocations.
  final _csi = _Csi(finalByte: 0, params: []);

  /// Whether the optional prefix (`:`..`?`) of the CSI being accumulated has
  /// been inspected yet.
  var _csiPrefixParsed = false;

  /// The parameter currently being accumulated. Digits are folded into it as
  /// they arrive; it is flushed to [_Csi.params] on `;` or the final byte.
  var _csiParam = 0;

  /// Whether any digit of the current parameter has been seen. Deliberately
  /// not reset on `;`: once true, empty parameters are flushed as implicit 0.
  var _csiHasParam = false;

  /// Continues the CSI at the head of the queue and dispatches it when
  /// complete. Returns false — leaving the parser in the csi state — when
  /// more input is needed.
  bool _processCsiState() {
    if (!_consumeCsi()) return false;
    _finishSequence();
    _dispatchCsi();
    return true;
  }

  /// Dispatches the completed [_csi] to its handler.
  void _dispatchCsi() {
    final csiHandler = _csiHandlers[_csi.finalByte];

    if (csiHandler == null) {
      handler.unknownCSI(_csi.finalByte);
    } else {
      csiHandler();
    }
  }

  /// Consumes more of the CSI at the head of the queue, continuing where the
  /// previous chunk left off. Returns false if the CSI isn't complete yet; in
  /// that case the partially parsed state is kept so the completed prefix is
  /// never re-parsed. After a CSI is successfully parsed, [_csi] is updated.
  bool _consumeCsi() {
    // Test whether the csi is a `CSI ? Ps ...` or `CSI Ps ...`. Done once per
    // sequence, not once per chunk.
    if (!_csiPrefixParsed) {
      if (_queue.isEmpty) {
        return false;
      }
      _csiPrefixParsed = true;
      final prefix = _queue.peek();
      if (prefix >= Ascii.colon && prefix <= Ascii.questionMark) {
        _csi.prefix = prefix;
        _queue.consume();
      }
    }

    while (true) {
      // The sequence isn't complete yet; wait for more input.
      if (_queue.isEmpty) {
        return false;
      }

      final char = _queue.consume();

      if (char == Ascii.semicolon) {
        if (_csiHasParam) {
          _csi.params.add(_csiParam);
        }
        _csiParam = 0;
        continue;
      }

      if (char >= Ascii.num0 && char <= Ascii.num9) {
        _csiHasParam = true;
        _csiParam *= 10;
        _csiParam += char - Ascii.num0;
        continue;
      }

      if (char > Ascii.NULL && char < Ascii.num0) {
        // intermediates.add(char);
        continue;
      }

      if (char >= Ascii.atSign && char <= Ascii.tilde) {
        if (_csiHasParam) {
          _csi.params.add(_csiParam);
        }

        _csi.finalByte = char;
        return true;
      }
    }
  }

  late final _csiHandlers = FastLookupTable<_CsiHandler>({
    // 'a'.codeUnitAt(0): _csiHandleCursorHorizontalRelative,
    'b'.codeUnitAt(0): _csiHandleRepeatPreviousCharacter,
    'c'.codeUnitAt(0): _csiHandleSendDeviceAttributes,
    'd'.codeUnitAt(0): _csiHandleLinePositionAbsolute,
    'f'.codeUnitAt(0): _csiHandleCursorPosition,
    'g'.codeUnitAt(0): _csiHandelClearTabStop,
    'h'.codeUnitAt(0): _csiHandleMode,
    'l'.codeUnitAt(0): _csiHandleMode,
    'm'.codeUnitAt(0): _csiHandleSgr,
    'n'.codeUnitAt(0): _csiHandleDeviceStatusReport,
    'r'.codeUnitAt(0): _csiHandleSetMargins,
    't'.codeUnitAt(0): _csiWindowManipulation,
    'A'.codeUnitAt(0): _csiHandleCursorUp,
    'B'.codeUnitAt(0): _csiHandleCursorDown,
    'C'.codeUnitAt(0): _csiHandleCursorForward,
    'D'.codeUnitAt(0): _csiHandleCursorBackward,
    'E'.codeUnitAt(0): _csiHandleCursorNextLine,
    'F'.codeUnitAt(0): _csiHandleCursorPrecedingLine,
    'G'.codeUnitAt(0): _csiHandleCursorHorizontalAbsolute,
    'H'.codeUnitAt(0): _csiHandleCursorPosition,
    'J'.codeUnitAt(0): _csiHandleEraseDisplay,
    'K'.codeUnitAt(0): _csiHandleEraseLine,
    'L'.codeUnitAt(0): _csiHandleInsertLines,
    'M'.codeUnitAt(0): _csiHandleDeleteLines,
    'P'.codeUnitAt(0): _csiHandleDelete,
    'S'.codeUnitAt(0): _csiHandleScrollUp,
    'T'.codeUnitAt(0): _csiHandleScrollDown,
    'X'.codeUnitAt(0): _csiHandleEraseCharacters,
    '@'.codeUnitAt(0): _csiHandleInsertBlankCharacters,
  });

  /// `ESC [ Ps a` Cursor Horizontal Position Relative (HPR)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sa/
  // void _csiHandleCursorHorizontalRelative() {
  //   if (_csi.params.isEmpty) {
  //     handler.cursorHorizontal(1);
  //   } else {
  //     handler.cursorHorizontal(_csi.params[0]);
  //   }
  // }

  /// `ESC [ Ps b` Repeat Previous Character (REP)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sb/
  void _csiHandleRepeatPreviousCharacter() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.repeatPreviousCharacter(amount);
  }

  /// `ESC [ Ps c` Device Attributes (DA)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sc/
  void _csiHandleSendDeviceAttributes() {
    switch (_csi.prefix) {
      case Ascii.greaterThan:
        return handler.sendSecondaryDeviceAttributes();
      case Ascii.equal:
        return handler.sendTertiaryDeviceAttributes();
      default:
        handler.sendPrimaryDeviceAttributes();
    }
  }

  /// `ESC [ Ps d` Cursor Vertical Position Absolute (VPA)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sd/
  void _csiHandleLinePositionAbsolute() {
    var y = 1;

    if (_csi.params.isNotEmpty) {
      y = _csi.params[0];
      if (y == 0) y = 1;
    }

    handler.setCursorY(y - 1);
  }

  /// `ESC [ Ps ; Ps f` Alias: Set Cursor Position
  ///
  /// https://terminalguide.namepad.de/seq/csi_sf/
  void _csiHandleCursorPosition() {
    var row = 1;
    var col = 1;

    if (_csi.params.length == 2) {
      row = _csi.params[0];
      col = _csi.params[1];
    } else if (_csi.params.length == 1) {
      // A single param specifies the row; the column defaults to 1.
      row = _csi.params[0];
    }

    if (row == 0) row = 1;
    if (col == 0) col = 1;

    handler.setCursor(col - 1, row - 1);
  }

  /// `ESC [ Ps g` Tab Clear (TBC)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sg/
  void _csiHandelClearTabStop() {
    var cmd = 0;

    if (_csi.params.length == 1) {
      cmd = _csi.params[0];
    }

    switch (cmd) {
      case 0:
        return handler.clearTabStopUnderCursor();
      default:
        return handler.clearAllTabStops();
    }
  }

  /// - `ESC [ [ Pm ] h Set Mode (SM)` https://terminalguide.namepad.de/seq/csi_sm/
  /// - `ESC [ ? [ Pm ] h` Set Mode (?) (SM) https://terminalguide.namepad.de/seq/csi_sh__p/
  /// - `ESC [ [ Pm ] l` Reset Mode (RM) https://terminalguide.namepad.de/seq/csi_rm/
  /// - `ESC [ ? [ Pm ] l` Reset Mode (?) (RM) https://terminalguide.namepad.de/seq/csi_sl__p/
  void _csiHandleMode() {
    final isEnabled = _csi.finalByte == Ascii.h;

    final isDecModes = _csi.prefix == Ascii.questionMark;

    if (isDecModes) {
      for (var mode in _csi.params) {
        _setDecMode(mode, isEnabled);
      }
    } else {
      for (var mode in _csi.params) {
        _setMode(mode, isEnabled);
      }
    }
  }

  /// `ESC [ [ Ps ] m` Select Graphic Rendition (SGR)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sm/
  void _csiHandleSgr() {
    final params = _csi.params;

    if (params.isEmpty) {
      return handler.resetCursorStyle();
    }

    // This is a workaround for a bug in the analyzer.
    // ignore: dead_code
    for (var i = 0; i < _csi.params.length; i++) {
      final param = params[i];
      switch (param) {
        case 0:
          handler.resetCursorStyle();
          continue;
        case 1:
          handler.setCursorBold();
          continue;
        case 2:
          handler.setCursorFaint();
          continue;
        case 3:
          handler.setCursorItalic();
          continue;
        case 4:
          handler.setCursorUnderline();
          continue;
        case 5:
          handler.setCursorBlink();
          continue;
        case 7:
          handler.setCursorInverse();
          continue;
        case 8:
          handler.setCursorInvisible();
          continue;
        case 9:
          handler.setCursorStrikethrough();
          continue;

        case 21:
          handler.unsetCursorBold();
          continue;
        case 22:
          handler.unsetCursorFaint();
          continue;
        case 23:
          handler.unsetCursorItalic();
          continue;
        case 24:
          handler.unsetCursorUnderline();
          continue;
        case 25:
          handler.unsetCursorBlink();
          continue;
        case 27:
          handler.unsetCursorInverse();
          continue;
        case 28:
          handler.unsetCursorInvisible();
          continue;
        case 29:
          handler.unsetCursorStrikethrough();
          continue;

        case 30:
          handler.setForegroundColor16(NamedColor.black);
          continue;
        case 31:
          handler.setForegroundColor16(NamedColor.red);
          continue;
        case 32:
          handler.setForegroundColor16(NamedColor.green);
          continue;
        case 33:
          handler.setForegroundColor16(NamedColor.yellow);
          continue;
        case 34:
          handler.setForegroundColor16(NamedColor.blue);
          continue;
        case 35:
          handler.setForegroundColor16(NamedColor.magenta);
          continue;
        case 36:
          handler.setForegroundColor16(NamedColor.cyan);
          continue;
        case 37:
          handler.setForegroundColor16(NamedColor.white);
          continue;
        case 38:
          final consumedFg = _consumeExtendedColor(params, i, foreground: true);
          if (consumedFg < 0) return;
          i += consumedFg;
          continue;
        case 39:
          handler.resetForeground();
          continue;

        case 40:
          handler.setBackgroundColor16(NamedColor.black);
          continue;
        case 41:
          handler.setBackgroundColor16(NamedColor.red);
          continue;
        case 42:
          handler.setBackgroundColor16(NamedColor.green);
          continue;
        case 43:
          handler.setBackgroundColor16(NamedColor.yellow);
          continue;
        case 44:
          handler.setBackgroundColor16(NamedColor.blue);
          continue;
        case 45:
          handler.setBackgroundColor16(NamedColor.magenta);
          continue;
        case 46:
          handler.setBackgroundColor16(NamedColor.cyan);
          continue;
        case 47:
          handler.setBackgroundColor16(NamedColor.white);
          continue;
        case 48:
          final consumedBg = _consumeExtendedColor(params, i, foreground: false);
          if (consumedBg < 0) return;
          i += consumedBg;
          continue;
        case 49:
          handler.resetBackground();
          continue;

        case 90:
          handler.setForegroundColor16(NamedColor.brightBlack);
          continue;
        case 91:
          handler.setForegroundColor16(NamedColor.brightRed);
          continue;
        case 92:
          handler.setForegroundColor16(NamedColor.brightGreen);
          continue;
        case 93:
          handler.setForegroundColor16(NamedColor.brightYellow);
          continue;
        case 94:
          handler.setForegroundColor16(NamedColor.brightBlue);
          continue;
        case 95:
          handler.setForegroundColor16(NamedColor.brightMagenta);
          continue;
        case 96:
          handler.setForegroundColor16(NamedColor.brightCyan);
          continue;
        case 97:
          handler.setForegroundColor16(NamedColor.brightWhite);
          continue;

        case 100:
          handler.setBackgroundColor16(NamedColor.brightBlack);
          continue;
        case 101:
          handler.setBackgroundColor16(NamedColor.brightRed);
          continue;
        case 102:
          handler.setBackgroundColor16(NamedColor.brightGreen);
          continue;
        case 103:
          handler.setBackgroundColor16(NamedColor.brightYellow);
          continue;
        case 104:
          handler.setBackgroundColor16(NamedColor.brightBlue);
          continue;
        case 105:
          handler.setBackgroundColor16(NamedColor.brightMagenta);
          continue;
        case 106:
          handler.setBackgroundColor16(NamedColor.brightCyan);
          continue;
        case 107:
          handler.setBackgroundColor16(NamedColor.brightWhite);
          continue;

        default:
          handler.unsupportedStyle(param);
          continue;
      }
    }
  }

  /// Consumes the extended color spec (256-color or RGB) following an
  /// SGR 38/48 parameter at index [i] in [params].
  ///
  /// Returns the number of extra params consumed (0 for an unknown color
  /// mode, which leaves the mode to be interpreted as a regular SGR param),
  /// or -1 for a truncated sequence — the caller aborts the whole SGR in
  /// that case instead of indexing past the parameter list.
  int _consumeExtendedColor(
    List<int> params,
    int i, {
    required bool foreground,
  }) {
    if (i + 1 >= params.length) return -1;

    switch (params[i + 1]) {
      case 2:
        if (i + 4 >= params.length) return -1;
        final r = params[i + 2];
        final g = params[i + 3];
        final b = params[i + 4];
        if (foreground) {
          handler.setForegroundColorRgb(r, g, b);
        } else {
          handler.setBackgroundColorRgb(r, g, b);
        }
        return 4;
      case 5:
        if (i + 2 >= params.length) return -1;
        final index = params[i + 2];
        if (foreground) {
          handler.setForegroundColor256(index);
        } else {
          handler.setBackgroundColor256(index);
        }
        return 2;
    }
    return 0;
  }

  /// `ESC [ Ps n` Device Status Report [Dispatch] (DSR)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sn/
  void _csiHandleDeviceStatusReport() {
    if (_csi.params.isEmpty) return;

    switch (_csi.params[0]) {
      case 5:
        return handler.sendOperatingStatus();
      case 6:
        return handler.sendCursorPosition();
    }
  }

  /// `ESC [ Ps ; Ps r` Set Top and Bottom Margins (DECSTBM)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sr/
  void _csiHandleSetMargins() {
    var top = 1;
    int? bottom;

    if (_csi.params.length > 2) return;

    if (_csi.params.isNotEmpty) {
      top = _csi.params[0];

      if (_csi.params.length == 2) {
        bottom = _csi.params[1] - 1;
      }
    }

    handler.setMargins(top - 1, bottom);
  }

  /// `ESC [ Ps t` Window operations [DISPATCH]
  ///
  /// https://terminalguide.namepad.de/seq/csi_st/
  void _csiWindowManipulation() {
    // The sequence needs at least one parameter.
    if (_csi.params.isEmpty) {
      return;
    }
    // Most the commands in this group are either of the scope of this package,
    // or should be disabled for security risks.
    switch (_csi.params.first) {
      // Window handling is currently not in the scope of the package.
      case 1: // Restore Terminal Window (show window if minimized)
      case 2: // Minimize Terminal Window
      case 3: // Set Terminal Window Position
      case 4: // Set Terminal Window Size in Pixels
      case 5: // Raise Terminal Window
      case 6: // Lower Terminal Window
      case 7: // Refresh/Redraw Terminal Window
        return;
      case 8: // Set Terminal Window Size (in characters)
        // This CSI contains 2 more parameters: width and height.
        if (_csi.params.length != 3) {
          return;
        }
        final rows = _csi.params[1];
        final cols = _csi.params[2];
        handler.resize(cols, rows);
        return;
      // Window handling is currently no in the scope of the package.
      case 9: // Maximize Terminal Window
      case 10: // Alias: Maximize Terminal Window
      case 11: // Report Terminal Window State
      case 13: // Report Terminal Window Position
      case 14: // Report Terminal Window Size in Pixels
      case 15: // Report Screen Size in Pixels
      case 16: // Report Cell Size in Pixels
        return;
      case 18: // Report Terminal Size (in characters)
        handler.sendSize();
        return;
      // Screen handling is currently no in the scope of the package.
      case 19: // Report Screen Size (in characters)
      // Disabled as these can a security risk.
      case 20: // Get Icon Title
      case 21: // Get Terminal Title
      // Not implemented.
      case 22: // Push Terminal Title
      case 23: // Pop Terminal Title
        return;
      // Unknown CSI.
      default:
        return;
    }
  }

  /// `ESC [ Ps A` Cursor Up (CUU)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ca/
  void _csiHandleCursorUp() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorY(-amount);
  }

  /// `ESC [ Ps B` Cursor Down (CUD)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cb/
  void _csiHandleCursorDown() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorY(amount);
  }

  /// `ESC [ Ps C` Cursor Right (CUF)
  ///
  /// Cursor Right (CUF)
  void _csiHandleCursorForward() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorX(amount);
  }

  /// `ESC [ Ps D` Cursor Left (CUB)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cd/
  void _csiHandleCursorBackward() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorX(-amount);
  }

  /// `ESC [ Ps E` Cursor Next Line (CNL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ce/
  void _csiHandleCursorNextLine() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.cursorNextLine(amount);
  }

  /// `ESC [ Ps F` Cursor Previous Line (CPL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cf/
  void _csiHandleCursorPrecedingLine() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.cursorPrecedingLine(amount);
  }

  void _csiHandleCursorHorizontalAbsolute() {
    var x = 1;

    if (_csi.params.isNotEmpty) {
      x = _csi.params[0];
      if (x == 0) x = 1;
    }

    handler.setCursorX(x - 1);
  }

  /// ESC [ Ps J Erase Display [Dispatch] (ED)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cj/
  void _csiHandleEraseDisplay() {
    var cmd = 0;

    if (_csi.params.length == 1) {
      cmd = _csi.params[0];
    }

    switch (cmd) {
      case 0:
        return handler.eraseDisplayBelow();
      case 1:
        return handler.eraseDisplayAbove();
      case 2:
        return handler.eraseDisplay();
      case 3:
        return handler.eraseScrollbackOnly();
    }
  }

  /// `ESC [ Ps K` Erase Line [Dispatch] (EL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ck/
  void _csiHandleEraseLine() {
    var cmd = 0;

    if (_csi.params.length == 1) {
      cmd = _csi.params[0];
    }

    switch (cmd) {
      case 0:
        return handler.eraseLineRight();
      case 1:
        return handler.eraseLineLeft();
      case 2:
        return handler.eraseLine();
    }
  }

  /// `ESC [ Ps L` Insert Line (IL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cl/
  void _csiHandleInsertLines() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.insertLines(amount);
  }

  /// ESC [ Ps M Delete Line (DL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cm/
  void _csiHandleDeleteLines() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.deleteLines(amount);
  }

  /// ESC [ Ps P Delete Character (DCH)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cp/
  void _csiHandleDelete() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.deleteChars(amount);
  }

  /// `ESC [ Ps S` Scroll Up (SU)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cs/
  void _csiHandleScrollUp() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.scrollUp(amount);
  }

  /// `ESC [ Ps T `Scroll Down (SD)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ct_1param/
  void _csiHandleScrollDown() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.scrollDown(amount);
  }

  /// `ESC [ Ps X` Erase Character (ECH)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cx/
  void _csiHandleEraseCharacters() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.eraseChars(amount);
  }

  /// `ESC [ Ps @` Insert Blanks (ICH)
  ///
  /// https://terminalguide.namepad.de/seq/csi_x40_at/
  ///
  /// Inserts amount spaces at current cursor position moving existing cell
  /// contents to the right. The contents of the amount right-most columns in
  /// the scroll region are lost. The cursor position is not changed.
  void _csiHandleInsertBlankCharacters() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.insertBlankChars(amount);
  }

  void _setMode(int mode, bool enabled) {
    switch (mode) {
      case 4:
        return handler.setInsertMode(enabled);
      case 20:
        return handler.setLineFeedMode(enabled);
      default:
        return handler.setUnknownMode(mode, enabled);
    }
  }

  void _setDecMode(int mode, bool enabled) {
    switch (mode) {
      case 1:
        return handler.setCursorKeysMode(enabled);
      case 3:
        return handler.setColumnMode(enabled);
      case 5:
        return handler.setReverseDisplayMode(enabled);
      case 6:
        return handler.setOriginMode(enabled);
      case 7:
        return handler.setAutoWrapMode(enabled);
      case 9:
        return enabled
            ? handler.setMouseMode(MouseMode.clickOnly)
            : handler.setMouseMode(MouseMode.none);
      case 12:
      case 13:
        return handler.setCursorBlinkMode(enabled);
      case 25:
        return handler.setCursorVisibleMode(enabled);
      case 47:
        if (enabled) {
          return handler.useAltBuffer();
        } else {
          return handler.useMainBuffer();
        }
      case 66:
        return handler.setAppKeypadMode(enabled);
      case 1000:
      case 10061000:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScroll)
            : handler.setMouseMode(MouseMode.none);
      case 1001:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScroll)
            : handler.setMouseMode(MouseMode.none);
      case 1002:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScrollDrag)
            : handler.setMouseMode(MouseMode.none);
      case 1003:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScrollMove)
            : handler.setMouseMode(MouseMode.none);
      case 1004:
        return handler.setReportFocusMode(enabled);
      case 1005:
        return enabled
            ? handler.setMouseReportMode(MouseReportMode.utf)
            : handler.setMouseReportMode(MouseReportMode.normal);
      case 1006:
        return enabled
            ? handler.setMouseReportMode(MouseReportMode.sgr)
            : handler.setMouseReportMode(MouseReportMode.normal);
      case 1007:
        return handler.setAltBufferMouseScrollMode(enabled);
      case 1015:
        return enabled
            ? handler.setMouseReportMode(MouseReportMode.urxvt)
            : handler.setMouseReportMode(MouseReportMode.normal);
      case 1047:
        if (enabled) {
          handler.useAltBuffer();
        } else {
          handler.clearAltBuffer();
          handler.useMainBuffer();
        }
        return;
      case 1048:
        if (enabled) {
          return handler.saveCursor();
        } else {
          return handler.restoreCursor();
        }
      case 1049:
        if (enabled) {
          handler.saveCursor();
          handler.clearAltBuffer();
          handler.useAltBuffer();
        } else {
          handler.useMainBuffer();
        }
        return;
      case 2004:
        return handler.setBracketedPasteMode(enabled);
      case 2026:
        return handler.setSyncOutputMode(enabled);
      default:
        return handler.setUnknownDecMode(mode, enabled);
    }
  }

  void _escHandleOSC() {
    // Reset the accumulated OSC state and keep parsing in the osc state,
    // possibly across chunk boundaries.
    _osc.clear();
    _oscParam.clear();
    _oscSawEsc = false;
    _state = _ParserState.osc;
  }

  /// Handles the completed [_osc] parameter list.
  void _dispatchOsc() {
    if (_osc.isEmpty) {
      return;
    }

    // Common OSCs
    if (_osc.length >= 2) {
      final ps = _osc[0];
      final pt = _osc[1];

      switch (ps) {
        case '0':
          handler.setTitle(pt);
          handler.setIconName(pt);
          return;
        case '1':
          handler.setIconName(pt);
          return;
        case '2':
          handler.setTitle(pt);
          return;
      }
    }

    // Private extensions
    handler.unknownOSC(_osc[0], _osc.sublist(1));
  }

  final _osc = <String>[];

  /// The OSC parameter currently being accumulated.
  final _oscParam = StringBuffer();

  /// Whether the last consumed character was an ESC, which may turn out to be
  /// the ST terminator if a backslash follows.
  var _oscSawEsc = false;

  /// Consumes more of the OSC at the head of the queue, continuing where the
  /// previous chunk left off. Returns false if the OSC isn't terminated yet;
  /// in that case the partially parsed state is kept so the completed prefix
  /// is never re-parsed.
  bool _consumeOsc() {
    while (true) {
      if (_oscSawEsc) {
        if (_queue.isEmpty) {
          return false;
        }
        _oscSawEsc = false;

        /// OSC terminates with ST
        if (_queue.consume() == Ascii.backslash) {
          _flushOscParam();
          return true;
        }

        // ESC followed by anything else still terminates the OSC. Emit the
        // pending parameter and push the character back so it is
        // re-processed as regular input.
        _flushOscParam();
        _queue.rollback();
        return true;
      }

      if (_queue.isEmpty) {
        return false;
      }

      final char = _queue.consume();

      // OSC terminates with BEL
      if (char == Ascii.BEL) {
        _flushOscParam();
        return true;
      }

      if (char == Ascii.ESC) {
        _oscSawEsc = true;
        continue;
      }

      /// Parse next parameter
      if (char == Ascii.semicolon) {
        _flushOscParam();
        continue;
      }

      _oscParam.writeCharCode(char);
    }
  }

  void _flushOscParam() {
    _osc.add(_oscParam.toString());
    _oscParam.clear();
  }
}

/// Parser states that persist across [EscapeParser.write] calls, so an
/// escape sequence split across chunks is parsed incrementally instead of
/// being rolled back and re-parsed.
enum _ParserState {
  /// Regular input; the next character is either written or starts a
  /// sequence.
  ground,

  /// An ESC was consumed; the next character designates the sequence type.
  esc,

  /// Inside a CSI sequence; [EscapeParser._csi] holds the parsed prefix.
  csi,

  /// Inside an OSC sequence; [EscapeParser._osc] holds the parsed params.
  osc,

  /// `ESC (` was consumed; the next character designates the G0 charset.
  charset0,

  /// `ESC )` was consumed; the next character designates the G1 charset.
  charset1,
}

class _Csi {
  _Csi({
    required this.params,
    required this.finalByte,
    // required this.intermediates,
  });

  int? prefix;

  List<int> params;

  int finalByte;
  // final List<int> intermediates;

  @override
  String toString() {
    return params.join(';') + String.fromCharCode(finalByte);
  }
}

/// Function that handles a sequence of characters that starts with an escape.
/// The handler either completes the sequence via `EscapeParser._finishSequence`
/// or switches the parser into a state that continues with the next chunk.
typedef _EscHandler = void Function();

typedef _SbcHandler = void Function();

typedef _CsiHandler = void Function();
