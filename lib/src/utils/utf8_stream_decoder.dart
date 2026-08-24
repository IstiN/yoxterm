import 'dart:typed_data';

/// Incremental UTF-8 decoder for a byte stream that arrives in chunks.
///
/// Unlike `utf8.decode`, which decodes one chunk in isolation and replaces a
/// multibyte sequence split across two chunks with U+FFFD on both sides, this
/// decoder carries the incomplete tail of a sequence over to the next
/// [decodeInto] call and reassembles it — a sequence split across chunk
/// boundaries is never re-scanned and never corrupted.
///
/// Malformed input is replaced with U+FFFD following the same "maximal
/// subpart" rule as `utf8.decode(bytes, allowMalformed: true)`: the longest
/// valid prefix of an ill-formed sequence yields a single replacement
/// character and decoding resumes at the offending byte.
class Utf8StreamDecoder {
  static const _replacement = 0xFFFD;

  /// Bytes of an incomplete multibyte sequence carried over from the previous
  /// chunk. At most 3 bytes can be pending: the 4th byte of a sequence always
  /// completes it, so a pending sequence holds lead + up to 2 continuations.
  /// (A 4th slot exists only to stage the completing byte before combining.)
  final _pending = Uint8List(4);

  var _pendingCount = 0;

  var _sequenceLength = 0;

  /// Whether the decoder is holding back bytes of an incomplete multibyte
  /// sequence, waiting for the continuation bytes in the next chunk.
  bool get hasPendingBytes => _pendingCount != 0;

  /// Whether the last [decodeInto] call produced at least one code point that
  /// the escape parser must dispatch on: a C0 control character
  /// (U+0000–U+001F, including ESC) or DEL (U+007F). This folds the
  /// parser-or-fast-path pre-scan into the decode pass, so plain text costs
  /// exactly one pass over the input.
  bool get lastChunkHasControlChars => _lastChunkHasControlChars;

  var _lastChunkHasControlChars = false;

  /// Decodes [bytes], appending the resulting Unicode code points to [out].
  ///
  /// [out] is not cleared first — the caller decides when to reset it, so the
  /// same list can be reused across calls without per-chunk allocation.
  void decodeInto(Uint8List bytes, List<int> out) {
    _lastChunkHasControlChars = false;

    for (var i = 0; i < bytes.length; i++) {
      final byte = bytes[i];

      if (_pendingCount == 0) {
        if (byte < 0x80) {
          if (byte < 0x20 || byte == 0x7F) {
            _lastChunkHasControlChars = true;
          }
          out.add(byte);
          continue;
        }

        final length = _sequenceLengthOf(byte);
        if (length == 0) {
          // Lone continuation byte, overlong lead (0xC0/0xC1) or a lead above
          // 0xF4: invalid, replace it on its own.
          out.add(_replacement);
          continue;
        }

        _pending[0] = byte;
        _pendingCount = 1;
        _sequenceLength = length;
        continue;
      }

      if (_isValidContinuation(byte)) {
        _pending[_pendingCount++] = byte;
        if (_pendingCount == _sequenceLength) {
          out.add(_combinePending());
          _pendingCount = 0;
        }
        continue;
      }

      // Invalid continuation: the pending bytes form the longest valid prefix
      // of the ill-formed sequence, which is replaced by a single U+FFFD. The
      // offending byte is reprocessed as the start of a new sequence.
      out.add(_replacement);
      _pendingCount = 0;
      i--;
    }
  }

  /// The total length in bytes of the sequence introduced by [lead], or 0 if
  /// [lead] cannot start a sequence.
  static int _sequenceLengthOf(int lead) {
    if (lead >= 0xC2 && lead <= 0xDF) return 2;
    if (lead >= 0xE0 && lead <= 0xEF) return 3;
    if (lead >= 0xF0 && lead <= 0xF4) return 4;
    return 0;
  }

  bool _isValidContinuation(int byte) {
    if (byte < 0x80 || byte > 0xBF) return false;

    // The second byte of a sequence has a restricted range that excludes
    // overlong encodings, UTF-16 surrogates and code points above U+10FFFF.
    if (_pendingCount == 1) {
      final lead = _pending[0];
      if (lead == 0xE0) return byte >= 0xA0;
      if (lead == 0xED) return byte <= 0x9F;
      if (lead == 0xF0) return byte >= 0x90;
      if (lead == 0xF4) return byte <= 0x8F;
    }
    return true;
  }

  /// Combines the completed pending sequence into its code point. Only called
  /// after all continuation bytes have been range-checked, so the result is
  /// always a valid, non-overlong Unicode scalar value.
  int _combinePending() {
    final lead = _pending[0];
    switch (_sequenceLength) {
      case 2:
        return ((lead & 0x1F) << 6) | (_pending[1] & 0x3F);
      case 3:
        return ((lead & 0x0F) << 12) |
            ((_pending[1] & 0x3F) << 6) |
            (_pending[2] & 0x3F);
      default:
        return ((lead & 0x07) << 18) |
            ((_pending[1] & 0x3F) << 12) |
            ((_pending[2] & 0x3F) << 6) |
            (_pending[3] & 0x3F);
    }
  }

  /// Discards any incomplete sequence held back from previous chunks.
  void reset() {
    _pendingCount = 0;
  }
}
