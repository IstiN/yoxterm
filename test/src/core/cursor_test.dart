import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('CursorStyle defaults', () {
    test('starts with zeroed fields', () {
      final style = CursorStyle();

      expect(style.foreground, 0);
      expect(style.background, 0);
      expect(style.attrs, 0);
    });

    test('empty is a zeroed shared instance', () {
      expect(CursorStyle.empty.foreground, 0);
      expect(CursorStyle.empty.background, 0);
      expect(CursorStyle.empty.attrs, 0);
    });

    test('accepts initial field values', () {
      final style = CursorStyle(foreground: 1, background: 2, attrs: 3);

      expect(style.foreground, 1);
      expect(style.background, 2);
      expect(style.attrs, 3);
    });
  });

  group('CursorStyle attributes', () {
    test('set and unset toggle individual attribute bits', () {
      final style = CursorStyle();

      style.setBold();
      expect(style.isBold, isTrue);
      expect(style.attrs, CellAttr.bold);

      style.setBold();
      expect(style.attrs, CellAttr.bold, reason: 'set is idempotent');

      style.unsetBold();
      expect(style.isBold, isFalse);
      expect(style.attrs, 0);

      style.unsetBold();
      expect(style.attrs, 0, reason: 'unset is idempotent');
    });

    test('faint', () {
      final style = CursorStyle()..setFaint();
      expect(style.isFaint, isTrue);
      style.unsetFaint();
      expect(style.isFaint, isFalse);
    });

    test('italic', () {
      final style = CursorStyle()..setItalic();
      expect(style.isItalis, isTrue);
      style.unsetItalic();
      expect(style.isItalis, isFalse);
    });

    test('underline', () {
      final style = CursorStyle()..setUnderline();
      expect(style.isUnderline, isTrue);
      style.unsetUnderline();
      expect(style.isUnderline, isFalse);
    });

    test('blink', () {
      final style = CursorStyle()..setBlink();
      expect(style.isBlink, isTrue);
      style.unsetBlink();
      expect(style.isBlink, isFalse);
    });

    test('inverse', () {
      final style = CursorStyle()..setInverse();
      expect(style.isInverse, isTrue);
      style.unsetInverse();
      expect(style.isInverse, isFalse);
    });

    test('invisible', () {
      final style = CursorStyle()..setInvisible();
      expect(style.isInvisible, isTrue);
      style.unsetInvisible();
      expect(style.isInvisible, isFalse);
    });

    test('strikethrough has a setter but no getter', () {
      final style = CursorStyle()..setStrikethrough();
      expect(style.attrs & CellAttr.strikethrough, isNonZero);
      style.unsetStrikethrough();
      expect(style.attrs & CellAttr.strikethrough, 0);
    });

    test('attributes are independent of each other', () {
      final style = CursorStyle()
        ..setBold()
        ..setItalic()
        ..setInverse();

      style.unsetItalic();

      expect(style.isBold, isTrue);
      expect(style.isItalis, isFalse);
      expect(style.isInverse, isTrue);
    });

    test('getters are false on a fresh style', () {
      final style = CursorStyle();

      expect(style.isBold, isFalse);
      expect(style.isFaint, isFalse);
      expect(style.isItalis, isFalse);
      expect(style.isUnderline, isFalse);
      expect(style.isBlink, isFalse);
      expect(style.isInverse, isFalse);
      expect(style.isInvisible, isFalse);
    });
  });

  group('CursorStyle foreground colors', () {
    test('setForegroundColor16 stores a named color', () {
      final style = CursorStyle()..setForegroundColor16(5);

      expect(style.foreground, 5 | CellColor.named);
      expect(style.foreground & CellColor.typeMask, CellColor.named);
      expect(style.foreground & CellColor.valueMask, 5);
    });

    test('setForegroundColor256 stores a palette color', () {
      final style = CursorStyle()..setForegroundColor256(200);

      expect(style.foreground, 200 | CellColor.palette);
      expect(style.foreground & CellColor.typeMask, CellColor.palette);
      expect(style.foreground & CellColor.valueMask, 200);
    });

    test('setForegroundColorRgb stores an rgb color', () {
      final style = CursorStyle()..setForegroundColorRgb(0x12, 0x34, 0x56);

      expect(style.foreground, (0x12 << 16) | (0x34 << 8) | 0x56 | CellColor.rgb);
      expect(style.foreground & CellColor.typeMask, CellColor.rgb);
      expect(style.foreground & CellColor.valueMask, 0x123456);
    });

    test('resetForegroundColor clears the foreground', () {
      final style = CursorStyle()..setForegroundColorRgb(1, 2, 3);

      style.resetForegroundColor();

      expect(style.foreground, 0);
    });
  });

  group('CursorStyle background colors', () {
    test('setBackgroundColor16 stores a named color', () {
      final style = CursorStyle()..setBackgroundColor16(5);

      expect(style.background, 5 | CellColor.named);
    });

    test('setBackgroundColor256 stores a palette color', () {
      final style = CursorStyle()..setBackgroundColor256(200);

      expect(style.background, 200 | CellColor.palette);
    });

    test('setBackgroundColorRgb stores an rgb color', () {
      final style = CursorStyle()..setBackgroundColorRgb(0x12, 0x34, 0x56);

      expect(style.background, 0x123456 | CellColor.rgb);
    });

    test('resetBackgroundColor clears the background', () {
      final style = CursorStyle()..setBackgroundColor16(5);

      style.resetBackgroundColor();

      expect(style.background, 0);
    });

    test('foreground and background are independent', () {
      final style = CursorStyle()
        ..setForegroundColor16(1)
        ..setBackgroundColor16(2);

      style.resetForegroundColor();

      expect(style.foreground, 0);
      expect(style.background, 2 | CellColor.named);
    });
  });

  group('CursorStyle.reset()', () {
    test('clears colors and attributes', () {
      final style = CursorStyle()
        ..setBold()
        ..setInverse()
        ..setForegroundColor256(100)
        ..setBackgroundColorRgb(1, 2, 3);

      style.reset();

      expect(style.foreground, 0);
      expect(style.background, 0);
      expect(style.attrs, 0);
    });
  });

  group('CursorPosition', () {
    test('stores x and y', () {
      final position = CursorPosition(3, 7);

      expect(position.x, 3);
      expect(position.y, 7);

      position.x = 4;
      position.y = 8;

      expect(position.x, 4);
      expect(position.y, 8);
    });
  });
}
