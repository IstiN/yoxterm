import 'package:test/test.dart';
import 'package:yoxterm/src/utils/ascii.dart';

void main() {
  group('Ascii.isNonPrintable', () {
    test('all C0 control characters are non-printable', () {
      for (var c = 0; c < 32; c++) {
        expect(Ascii.isNonPrintable(c), isTrue, reason: 'char $c');
      }
    });

    test('printable ASCII range is printable', () {
      for (var c = 32; c < 127; c++) {
        expect(Ascii.isNonPrintable(c), isFalse, reason: 'char $c');
      }
    });

    test('DEL is non-printable', () {
      expect(Ascii.isNonPrintable(127), isTrue);
    });

    test('values above 127 are treated as printable', () {
      // Documents current behavior: the check only covers the ASCII range.
      expect(Ascii.isNonPrintable(128), isFalse);
      expect(Ascii.isNonPrintable(0x10FFFF), isFalse);
    });
  });

  group('Ascii constants', () {
    test('control character constants match their code points', () {
      final expected = <String, int>{
        '\x00': Ascii.NULL,
        '\x01': Ascii.SOH,
        '\x02': Ascii.STX,
        '\x03': Ascii.ETX,
        '\x04': Ascii.EOT,
        '\x05': Ascii.ENQ,
        '\x06': Ascii.ACK,
        '\x07': Ascii.BEL,
        '\x08': Ascii.BS,
        '\x09': Ascii.HT,
        '\x0a': Ascii.LF,
        '\x0b': Ascii.VT,
        '\x0c': Ascii.FF,
        '\x0d': Ascii.CR,
        '\x0e': Ascii.SO,
        '\x0f': Ascii.SI,
        '\x10': Ascii.DLE,
        '\x11': Ascii.DC1,
        '\x12': Ascii.DC2,
        '\x13': Ascii.DC3,
        '\x14': Ascii.DC4,
        '\x15': Ascii.NAK,
        '\x16': Ascii.SYN,
        '\x17': Ascii.ETB,
        '\x18': Ascii.CAN,
        '\x19': Ascii.EM,
        '\x1a': Ascii.SUB,
        '\x1b': Ascii.ESC,
        '\x1c': Ascii.FS,
        '\x1d': Ascii.GS,
        '\x1e': Ascii.RS,
        '\x1f': Ascii.US,
        '\x7f': Ascii.DEL,
      };
      expected.forEach((char, constant) {
        expect(constant, char.codeUnitAt(0), reason: 'mismatch for $constant');
      });
    });

    test('printable character constants match their code points', () {
      final expected = <String, int>{
        ' ': Ascii.space,
        '!': Ascii.exclamationMark,
        '"': Ascii.doubleQuotes,
        '#': Ascii.numberSign,
        '\$': Ascii.dollarSign,
        '%': Ascii.percentSign,
        '&': Ascii.ampersand,
        '\'': Ascii.singleQuote,
        '(': Ascii.openParentheses,
        ')': Ascii.closeParentheses,
        '*': Ascii.asterisk,
        '+': Ascii.plus,
        ',': Ascii.comma,
        '-': Ascii.minus,
        '.': Ascii.dot,
        '/': Ascii.slash,
        '0': Ascii.num0,
        '1': Ascii.num1,
        '2': Ascii.num2,
        '3': Ascii.num3,
        '4': Ascii.num4,
        '5': Ascii.num5,
        '6': Ascii.num6,
        '7': Ascii.num7,
        '8': Ascii.num8,
        '9': Ascii.num9,
        ':': Ascii.colon,
        ';': Ascii.semicolon,
        '<': Ascii.lessThan,
        '=': Ascii.equal,
        '>': Ascii.greaterThan,
        '?': Ascii.questionMark,
        '@': Ascii.atSign,
        '[': Ascii.openBracket,
        '\\': Ascii.backslash,
        ']': Ascii.closeBracket,
        '^': Ascii.caret,
        '_': Ascii.underscore,
        '`': Ascii.graveAccent,
        '{': Ascii.openBrace,
        '|': Ascii.verticalBar,
        '}': Ascii.closeBrace,
        '~': Ascii.tilde,
      };
      expected.forEach((char, constant) {
        expect(constant, char.codeUnitAt(0), reason: 'mismatch for $char');
      });
    });

    test('letter constants match their code points', () {
      const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
      final constants = [
        Ascii.A, Ascii.B, Ascii.C, Ascii.D, Ascii.E, Ascii.F, Ascii.G, //
        Ascii.H, Ascii.I, Ascii.J, Ascii.K, Ascii.L, Ascii.M, Ascii.N,
        Ascii.O, Ascii.P, Ascii.Q, Ascii.R, Ascii.S, Ascii.T, Ascii.U,
        Ascii.V, Ascii.W, Ascii.X, Ascii.Y, Ascii.Z,
        Ascii.a, Ascii.b, Ascii.c, Ascii.d, Ascii.e, Ascii.f, Ascii.g,
        Ascii.h, Ascii.i, Ascii.j, Ascii.k, Ascii.l, Ascii.m, Ascii.n,
        Ascii.o, Ascii.p, Ascii.q, Ascii.r, Ascii.s, Ascii.t, Ascii.u,
        Ascii.v, Ascii.w, Ascii.x, Ascii.y, Ascii.z,
      ];
      for (var i = 0; i < letters.length; i++) {
        expect(
          constants[i],
          letters.codeUnitAt(i),
          reason: 'mismatch for ${letters[i]}',
        );
      }
    });
  });
}
