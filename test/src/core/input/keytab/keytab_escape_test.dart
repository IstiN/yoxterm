import 'package:test/test.dart';
import 'package:xterm/src/core/input/keytab/keytab_escape.dart';

void main() {
  group('keytabUnescape()', () {
    test('leaves plain text untouched', () {
      expect(keytabUnescape('hello world'), 'hello world');
    });

    test(r'\E is the escape character', () {
      expect(keytabUnescape(r'\E'), '\x1b');
      expect(keytabUnescape(r'\E[A'), '\x1b[A');
    });

    test(r'\\ is a literal backslash', () {
      expect(keytabUnescape(r'\\'), r'\');
    });

    test(r'\" is a literal quote', () {
      expect(keytabUnescape(r'\"'), '"');
    });

    test('control character shortcuts', () {
      expect(keytabUnescape(r'\t'), '\t');
      expect(keytabUnescape(r'\r'), '\r');
      expect(keytabUnescape(r'\n'), '\n');
      expect(keytabUnescape(r'\b'), '\b');
    });

    test(r'\xNN hex escapes are decoded', () {
      expect(keytabUnescape(r'\x00'), '\x00');
      expect(keytabUnescape(r'\x7f'), '\x7f');
      expect(keytabUnescape(r'\x41'), 'A');
    });

    test('hex escapes accept uppercase digits', () {
      expect(keytabUnescape(r'\x1B'), '\x1b');
      expect(keytabUnescape(r'\xAF'), '\xaf');
    });

    test('multiple escapes in one string', () {
      expect(keytabUnescape(r'\E[1;*H'), '\x1b[1;*H');
      expect(keytabUnescape(r'a\tb\x43c'), 'a\tbCc');
    });

    test('unknown escapes are preserved as-is', () {
      expect(keytabUnescape(r'\q'), r'\q');
    });

    test('incomplete hex escape is preserved as-is', () {
      // A single hex digit does not match the two-digit pattern.
      expect(keytabUnescape(r'\x1'), r'\x1');
    });

    test(r'\\ prevents the following escape from being decoded', () {
      // `\\` is replaced first, so `\x41` here is a literal backslash
      // followed by x41... except the hex pass runs afterwards on the
      // already-unescaped text. `\\x41` becomes `\x41` after the backslash
      // replacement, and the hex pass then decodes it.
      expect(keytabUnescape(r'\\x41'), 'A');
    });
  });
}
