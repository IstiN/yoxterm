import 'package:test/test.dart';
import 'package:yoxterm/src/core/charset.dart';

void main() {
  group('asciiTranslator', () {
    test('returns the code point unchanged', () {
      expect(asciiTranslator(0), 0);
      expect(asciiTranslator(0x41), 0x41);
      expect(asciiTranslator(0xFFFF), 0xFFFF);
    });
  });

  group('decSpecGraphicsTranslator', () {
    test('maps DEC special graphics characters', () {
      expect(decSpecGraphicsTranslator(0x5F), 0x00A0); // NO-BREAK SPACE
      expect(decSpecGraphicsTranslator(0x60), 0x25C6); // BLACK DIAMOND
      expect(decSpecGraphicsTranslator(0x61), 0x2592); // MEDIUM SHADE
      expect(decSpecGraphicsTranslator(0x6A), 0x2518); // BOX UP AND LEFT
      expect(decSpecGraphicsTranslator(0x71), 0x2500); // BOX HORIZONTAL
      expect(decSpecGraphicsTranslator(0x78), 0x2502); // BOX VERTICAL
      expect(decSpecGraphicsTranslator(0x7B), 0x03C0); // GREEK PI
      expect(decSpecGraphicsTranslator(0x7E), 0x00B7); // MIDDLE DOT
    });

    test('passes unmapped characters below 127 through unchanged', () {
      expect(decSpecGraphicsTranslator(0x41), 0x41); // 'A'
      expect(decSpecGraphicsTranslator(0x30), 0x30); // '0'
      expect(decSpecGraphicsTranslator(0x20), 0x20); // ' '
    });

    test('passes characters at or above 127 through unchanged', () {
      expect(decSpecGraphicsTranslator(127), 127);
      expect(decSpecGraphicsTranslator(0xE9), 0xE9);
      expect(decSpecGraphicsTranslator(0x1F600), 0x1F600);
    });

    test('the lookup table covers the documented range 0x5F-0x7E', () {
      for (var i = 0x5F; i <= 0x7E; i++) {
        expect(decSpecGraphics.containsKey(i), isTrue,
            reason: 'missing mapping for 0x${i.toRadixString(16)}');
      }
    });
  });

  group('Charset', () {
    test('translates with ASCII by default', () {
      final charset = Charset();

      expect(charset.translate(0x71), 0x71);
    });

    test('use() without designate() falls back to ASCII', () {
      final charset = Charset();

      charset.use(1);

      expect(charset.translate(0x71), 0x71);
    });

    test('designate() + use() activates the DEC special graphics charset', () {
      final charset = Charset();

      charset.designate(0, '0'.codeUnitAt(0));
      charset.use(0);

      expect(charset.translate(0x71), 0x2500);
      expect(charset.translate(0x41), 0x41);
    });

    test('designate() with an unknown charset name is ignored', () {
      final charset = Charset();

      charset.designate(0, 'X'.codeUnitAt(0));
      charset.use(0);

      expect(charset.translate(0x71), 0x71);
    });

    test('designate() supports the ASCII charset name B', () {
      final charset = Charset();

      charset.designate(0, 'B'.codeUnitAt(0));
      charset.use(0);

      expect(charset.translate(0x71), 0x71);
    });

    test('slots are independent and use() switches between them', () {
      final charset = Charset();

      charset.designate(0, '0'.codeUnitAt(0));
      charset.designate(1, 'B'.codeUnitAt(0));

      charset.use(0);
      expect(charset.translate(0x71), 0x2500);

      charset.use(1);
      expect(charset.translate(0x71), 0x71);

      charset.use(0);
      expect(charset.translate(0x71), 0x2500);
    });

    test('designating a slot that is in use takes effect immediately', () {
      final charset = Charset();

      charset.use(0);
      expect(charset.translate(0x71), 0x71);

      charset.designate(0, '0'.codeUnitAt(0));
      expect(charset.translate(0x71), 0x2500);
    });

    test('save() and restore() preserve the map and the active slot', () {
      final charset = Charset();

      charset.designate(1, '0'.codeUnitAt(0));
      charset.use(1);
      charset.save();

      // Change both the map and the active slot.
      charset.designate(1, 'B'.codeUnitAt(0));
      charset.use(0);
      expect(charset.translate(0x71), 0x71);

      charset.restore();
      expect(charset.translate(0x71), 0x2500);
    });

    test('restore() without save() returns to the initial state', () {
      final charset = Charset();

      charset.designate(0, '0'.codeUnitAt(0));
      charset.use(0);
      expect(charset.translate(0x71), 0x2500);

      charset.restore();
      expect(charset.translate(0x71), 0x71);
    });

    test('mutations after save() do not leak into the saved state', () {
      final charset = Charset();

      charset.save();
      charset.designate(0, '0'.codeUnitAt(0));
      charset.restore();

      // Slot 0 must still be undesignated in the restored map.
      charset.use(0);
      expect(charset.translate(0x71), 0x71);
    });
  });
}
