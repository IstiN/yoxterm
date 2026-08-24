import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yoxterm/src/utils/utf8_stream_decoder.dart';

List<int> decodeAll(Utf8StreamDecoder decoder, Uint8List bytes) {
  final out = <int>[];
  decoder.decodeInto(bytes, out);
  return out;
}

void main() {
  group('Utf8StreamDecoder', () {
    late Utf8StreamDecoder decoder;

    setUp(() {
      decoder = Utf8StreamDecoder();
    });

    group('single chunk', () {
      test('decodes ASCII passthrough', () {
        expect(
          decodeAll(decoder, Uint8List.fromList('hello'.codeUnits)),
          'hello'.codeUnits,
        );
        expect(decoder.hasPendingBytes, isFalse);
        expect(decoder.lastChunkHasControlChars, isFalse);
      });

      test('decodes 2-byte, 3-byte and 4-byte sequences', () {
        final bytes = utf8.encode('é中😀');
        expect(
          decodeAll(decoder, Uint8List.fromList(bytes)),
          [0xE9, 0x4E2D, 0x1F600],
        );
        expect(decoder.hasPendingBytes, isFalse);
      });

      test('flags C0 control characters and DEL for the parser', () {
        decodeAll(decoder, Uint8List.fromList([0x61, 0x1B, 0x62]));
        expect(decoder.lastChunkHasControlChars, isTrue);

        decodeAll(decoder, Uint8List.fromList([0x61, 0x7F]));
        expect(decoder.lastChunkHasControlChars, isTrue);

        decodeAll(decoder, Uint8List.fromList([0x61, 0x62]));
        expect(decoder.lastChunkHasControlChars, isFalse);
      });

      test('does not flag C1 controls produced by multibyte sequences', () {
        // U+0085 (NEL) is C1, but the parser treats it as a regular
        // character — identical to the String fast path.
        decodeAll(decoder, Uint8List.fromList(utf8.encode('\u0085')));
        expect(decoder.lastChunkHasControlChars, isFalse);
      });

      test('empty chunk decodes to nothing and keeps the flag cleared', () {
        decodeAll(decoder, Uint8List.fromList([0x1B]));
        expect(decodeAll(decoder, Uint8List(0)), isEmpty);
        expect(decoder.lastChunkHasControlChars, isFalse);
      });
    });

    group('sequences split across chunks', () {
      final cases = {
        'é (2-byte)': 'é',
        '中 (3-byte)': '中',
        '😀 (4-byte)': '😀',
      };

      cases.forEach((label, char) {
        final bytes = utf8.encode(char);
        for (var split = 1; split < bytes.length; split++) {
          test('$label split after byte $split is reassembled', () {
            decoder.decodeInto(
              Uint8List.fromList(bytes.sublist(0, split)),
              <int>[],
            );
            expect(decoder.hasPendingBytes, isTrue);

            final out = decodeAll(
              decoder,
              Uint8List.fromList(bytes.sublist(split)),
            );
            expect(out, [char.runes.single]);
            expect(decoder.hasPendingBytes, isFalse);
          });
        }
      });

      test('a sequence split across three chunks is reassembled', () {
        final bytes = utf8.encode('😀'); // 4 bytes
        final out = <int>[];
        for (final byte in bytes) {
          decoder.decodeInto(Uint8List.fromList([byte]), out);
        }
        expect(out, [0x1F600]);
      });

      test('text before and after a split sequence stays ordered', () {
        final bytes = utf8.encode('a😀b');
        final out = decodeAll(
          decoder,
          Uint8List.fromList(bytes.sublist(0, 3)),
        );
        expect(out, [0x61]);
        out.addAll(decodeAll(decoder, Uint8List.fromList(bytes.sublist(3))));
        expect(out, [0x61, 0x1F600, 0x62]);
      });

      test('a split sequence followed by more text in the same chunk', () {
        final bytes = utf8.encode('中ab');
        decoder.decodeInto(Uint8List.fromList(bytes.sublist(0, 1)), <int>[]);
        expect(
          decodeAll(decoder, Uint8List.fromList(bytes.sublist(1))),
          [0x4E2D, 0x61, 0x62],
        );
      });

      test('incomplete sequence at chunk end is held back, not replaced', () {
        expect(decodeAll(decoder, Uint8List.fromList([0xF0, 0x9F])), isEmpty);
        expect(decoder.hasPendingBytes, isTrue);
      });
    });

    group('malformed input', () {
      // Every case ends with an ASCII byte so dart:convert (which flushes a
      // truncated sequence at chunk end) and the streaming decoder (which
      // holds it back) agree: the trailing byte always resolves the pending
      // prefix one way or the other.
      final malformed = <List<int>>[
        [0xC3, 0x28], // truncated 2-byte, then '('
        [0xE2, 0x82, 0x28], // maximal subpart of a 3-byte sequence
        [0xF0, 0x9F, 0x28], // maximal subpart of a 4-byte sequence
        [0xF0, 0x28], // bad second byte of a 4-byte sequence
        [0xED, 0xA0, 0x80], // UTF-16 surrogate encoding
        [0x80], // lone continuation
        [0x80, 0x80],
        [0xC0, 0xAF], // overlong '/'
        [0xC1, 0xBF],
        [0xF5, 0x80, 0x80, 0x80], // lead above U+10FFFF
        [0xF4, 0x90, 0x80, 0x80], // U+110000, out of range
        [0xE0, 0x80, 0x80], // overlong 3-byte
        [0xFE], // never valid
        [0xFF],
        [0x61, 0xC3, 0x62], // lead byte followed by ASCII
        [0xE4, 0xB8, 0x1B], // ESC interrupts a 3-byte sequence
      ];

      for (final bytes in malformed) {
        test('${bytes.map((b) => b.toRadixString(16)).join(' ')} matches '
            'utf8.decode(allowMalformed: true)', () {
          final input = Uint8List.fromList([...bytes, 0x78]);
          final expected = utf8
              .decode(input, allowMalformed: true)
              .runes
              .toList();
          expect(decodeAll(decoder, input), expected);
        });
      }

      test('matches dart:convert on random byte soup', () {
        final random = Random(42);
        const pool = [
          0x00, 0x1B, 0x61, 0x7F, // ascii & controls
          0x80, 0xBF, // continuations
          0xC0, 0xC2, 0xDF, // 2-byte leads (incl. overlong)
          0xE0, 0xED, 0xEF, // 3-byte leads
          0xF0, 0xF4, 0xF5, // 4-byte leads
          0xFE, 0xFF, // invalid
        ];
        for (var round = 0; round < 200; round++) {
          final bytes = Uint8List.fromList([
            for (var i = 0; i < 1 + random.nextInt(12); i++)
              pool[random.nextInt(pool.length)],
            0x78, // resolve any pending prefix (see above)
          ]);
          final expected =
              utf8.decode(bytes, allowMalformed: true).runes.toList();
          expect(
            decodeAll(Utf8StreamDecoder(), bytes),
            expected,
            reason: 'input: ${bytes.join(', ')}',
          );
        }
      });

      test('a pending prefix interrupted by the next chunk yields one U+FFFD',
          () {
        // F0 9F is a maximal subpart; 'a' cannot continue it.
        decoder.decodeInto(Uint8List.fromList([0xF0, 0x9F]), <int>[]);
        expect(decodeAll(decoder, Uint8List.fromList([0x61])), [0xFFFD, 0x61]);
      });

      test('reset discards a pending sequence', () {
        decoder.decodeInto(Uint8List.fromList([0xF0, 0x9F]), <int>[]);
        decoder.reset();
        expect(decoder.hasPendingBytes, isFalse);
        expect(decodeAll(decoder, Uint8List.fromList([0x61])), [0x61]);
      });
    });

    group('decodeInto appends without clearing', () {
      test('output list is reused across calls', () {
        final out = <int>[];
        decoder.decodeInto(Uint8List.fromList([0x61]), out);
        decoder.decodeInto(Uint8List.fromList([0x62]), out);
        expect(out, [0x61, 0x62]);
      });
    });
  });
}
