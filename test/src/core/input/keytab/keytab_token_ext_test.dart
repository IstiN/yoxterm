import 'package:test/test.dart';
import 'package:yoxterm/src/core/input/keytab/keytab_token.dart';

void main() {
  group('KeytabToken', () {
    test('toString() renders type and value', () {
      final token = KeytabToken(KeytabTokenType.keyName, 'Tab');
      expect(token.toString(), 'KeytabTokenType.keyName<Tab>');
    });
  });

  group('LineReader', () {
    test('take() and peek() read single characters by default', () {
      final reader = LineReader('abc');
      expect(reader.peek(), 'a');
      expect(reader.take(), 'a');
      expect(reader.take(), 'b');
      expect(reader.take(), 'c');
      expect(reader.done, isTrue);
      expect(reader.peek(), isNull);
      expect(reader.take(), isNull);
    });

    test('take(count) and peek(count) read multiple characters', () {
      final reader = LineReader('abcdef');
      expect(reader.peek(3), 'abc');
      expect(reader.take(2), 'ab');
      expect(reader.take(3), 'cde');
      expect(reader.done, isFalse);
      // Fewer characters than requested are returned at the end.
      expect(reader.take(5), 'f');
      expect(reader.done, isTrue);
    });

    test('skipWhitespace() skips spaces and tabs', () {
      final reader = LineReader(' \t x');
      reader.skipWhitespace();
      expect(reader.take(), 'x');
    });

    test('readString() reads word characters and underscores', () {
      final reader = LineReader('PageUp+');
      expect(reader.readString(), 'PageUp');
      expect(reader.take(), '+');
    });

    test('readUntil() stops before the pattern by default', () {
      final reader = LineReader('ab"cd');
      expect(reader.readUntil('"'), 'ab');
      expect(reader.peek(), '"');
    });

    test('readUntil(inclusive: true) consumes the terminator', () {
      final reader = LineReader('ab"cd');
      expect(reader.readUntil('"', inclusive: true), 'ab"');
      expect(reader.peek(), 'c');
    });

    test('readUntil() reads to the end when the pattern is absent', () {
      final reader = LineReader('abc');
      expect(reader.readUntil('"'), 'abc');
      expect(reader.done, isTrue);
    });
  });

  group('tokenize()', () {
    test('parses a keyboard name declaration', () {
      final tokens = tokenize('keyboard "Default (XFree 4)"').toList();
      expect(tokens, hasLength(2));
      expect(tokens[0].type, KeytabTokenType.keyboard);
      expect(tokens[1].type, KeytabTokenType.input);
      expect(tokens[1].value, 'Default (XFree 4)');
    });

    test('parses a simple key define', () {
      final tokens = tokenize(r'key Tab : "\t"').toList();
      expect(tokens.map((t) => t.type), [
        KeytabTokenType.keyDefine,
        KeytabTokenType.keyName,
        KeytabTokenType.colon,
        KeytabTokenType.input,
      ]);
      expect(tokens[1].value, 'Tab');
      expect(tokens[3].value, r'\t');
    });

    test('parses modes with + and - prefixes', () {
      final tokens = tokenize(r'key Tab -Shift+Control+Ansi : "\t"').toList();
      expect(tokens.map((t) => t.type), [
        KeytabTokenType.keyDefine,
        KeytabTokenType.keyName,
        KeytabTokenType.modeStatus,
        KeytabTokenType.mode,
        KeytabTokenType.modeStatus,
        KeytabTokenType.mode,
        KeytabTokenType.modeStatus,
        KeytabTokenType.mode,
        KeytabTokenType.colon,
        KeytabTokenType.input,
      ]);
      expect(tokens[2].value, '-');
      expect(tokens[3].value, 'Shift');
      expect(tokens[4].value, '+');
      expect(tokens[5].value, 'Control');
      expect(tokens[6].value, '+');
      expect(tokens[7].value, 'Ansi');
    });

    test('parses unquoted actions as shortcuts', () {
      final tokens = tokenize('key Up +Shift-AppScreen : scrollLineUp').toList();
      expect(tokens.last.type, KeytabTokenType.shortcut);
      expect(tokens.last.value, 'scrollLineUp');
    });

    test('comment lines and blank lines are ignored', () {
      final tokens = tokenize('''
# a comment

   # an indented comment
key Tab : "\\t" # trailing comment
''').toList();

      expect(tokens.map((t) => t.type), [
        KeytabTokenType.keyDefine,
        KeytabTokenType.keyName,
        KeytabTokenType.colon,
        KeytabTokenType.input,
      ]);
    });

    test('unrecognized lines are silently ignored', () {
      expect(tokenize('this is not a keytab line').toList(), isEmpty);
      expect(tokenize('keyboardx "name"').toList(), isEmpty);
      expect(tokenize('keys Tab : "x"').toList(), isEmpty);
    });

    test('quoted input values may contain spaces and escapes', () {
      final tokens = tokenize(r'key Space : "\x00 \E"').toList();
      expect(tokens.last.type, KeytabTokenType.input);
      expect(tokens.last.value, r'\x00 \E');
    });

    test('multiple lines produce a flat token stream', () {
      final tokens = tokenize('''
keyboard "a"
key Tab : "\\t"
key Up : "\\EA"
''').toList();

      expect(tokens, hasLength(2 + 4 + 4));
    });

    test('throws TokenizeError when the keyboard name is not quoted', () {
      expect(() => tokenize('keyboard default').toList(),
          throwsA(isA<TokenizeError>()));
    });

    test('throws TokenizeError when the colon is missing', () {
      expect(() => tokenize(r'key Tab "\t"').toList(),
          throwsA(isA<TokenizeError>()));
    });

    test('throws TokenizeError when a mode has no +/- prefix', () {
      expect(() => tokenize(r'key Tab Shift : "\t"').toList(),
          throwsA(isA<TokenizeError>()));
    });

    test('unterminated quoted input is tolerated', () {
      // The tokenizer reads to the end of the line when the closing quote
      // is missing; no error is raised.
      final tokens = tokenize(r'key Tab : "\t').toList();
      expect(tokens.last.type, KeytabTokenType.input);
      expect(tokens.last.value, r'\t');
    });
  });
}
