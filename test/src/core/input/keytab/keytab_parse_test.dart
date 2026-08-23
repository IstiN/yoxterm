import 'package:test/test.dart';
import 'package:xterm/src/core/input/keytab/keytab_parse.dart';
import 'package:xterm/src/core/input/keytab/keytab_record.dart';
import 'package:xterm/src/core/input/keytab/keytab_token.dart';

KeytabToken token(KeytabTokenType type, [String value = '']) {
  return KeytabToken(type, value);
}

void main() {
  group('TokensReader', () {
    test('take() returns tokens in order and advances', () {
      final reader = TokensReader([
        token(KeytabTokenType.keyDefine, 'key'),
        token(KeytabTokenType.keyName, 'Tab'),
      ]);

      expect(reader.done, isFalse);
      expect(reader.take()!.value, 'key');
      expect(reader.take()!.value, 'Tab');
      expect(reader.done, isTrue);
    });

    test('peek() does not advance', () {
      final reader = TokensReader([token(KeytabTokenType.colon, ':')]);

      expect(reader.peek()!.type, KeytabTokenType.colon);
      expect(reader.peek()!.type, KeytabTokenType.colon);
      expect(reader.done, isFalse);
    });

    test('peek() and take() return null past the end', () {
      final reader = TokensReader([]);
      expect(reader.done, isTrue);
      expect(reader.peek(), isNull);
      expect(reader.take(), isNull);
    });
  });

  group('KeytabParser', () {
    test('parses the keyboard name', () {
      final parser = KeytabParser()
        ..addTokens([
          token(KeytabTokenType.keyboard, 'keyboard'),
          token(KeytabTokenType.input, 'test keyboard'),
        ]);

      expect(parser.result.name, 'test keyboard');
      expect(parser.result.records, isEmpty);
    });

    test('parses a minimal key define with an input action', () {
      final parser = KeytabParser()
        ..addTokens([
          token(KeytabTokenType.keyDefine, 'key'),
          token(KeytabTokenType.keyName, 'Tab'),
          token(KeytabTokenType.colon, ':'),
          token(KeytabTokenType.input, r'\t'),
        ]);

      final record = parser.result.records.single;
      expect(record.qtKeyName, 'Tab');
      expect(record.action.type, KeytabActionType.input);
      expect(record.action.unescapedValue(), '\t');
      expect(record.ctrl, isNull);
      expect(record.shift, isNull);
      expect(record.alt, isNull);
    });

    test('parses a key define with a shortcut action', () {
      final parser = KeytabParser()
        ..addTokens([
          token(KeytabTokenType.keyDefine, 'key'),
          token(KeytabTokenType.keyName, 'Up'),
          token(KeytabTokenType.colon, ':'),
          token(KeytabTokenType.shortcut, 'scrollLineUp'),
        ]);

      final record = parser.result.records.single;
      expect(record.action.type, KeytabActionType.shortcut);
      expect(record.action.value, 'scrollLineUp');
    });

    test('parses all supported modes', () {
      final parser = KeytabParser()
        ..addTokens([
          token(KeytabTokenType.keyDefine, 'key'),
          token(KeytabTokenType.keyName, 'Up'),
          token(KeytabTokenType.modeStatus, '+'),
          token(KeytabTokenType.mode, 'Alt'),
          token(KeytabTokenType.modeStatus, '-'),
          token(KeytabTokenType.mode, 'Control'),
          token(KeytabTokenType.modeStatus, '+'),
          token(KeytabTokenType.mode, 'Shift'),
          token(KeytabTokenType.modeStatus, '-'),
          token(KeytabTokenType.mode, 'AnyMod'),
          token(KeytabTokenType.modeStatus, '+'),
          token(KeytabTokenType.mode, 'Ansi'),
          token(KeytabTokenType.modeStatus, '-'),
          token(KeytabTokenType.mode, 'AppScreen'),
          token(KeytabTokenType.modeStatus, '+'),
          token(KeytabTokenType.mode, 'KeyPad'),
          token(KeytabTokenType.modeStatus, '-'),
          token(KeytabTokenType.mode, 'AppCuKeys'),
          token(KeytabTokenType.modeStatus, '+'),
          token(KeytabTokenType.mode, 'AppKeyPad'),
          token(KeytabTokenType.modeStatus, '-'),
          token(KeytabTokenType.mode, 'NewLine'),
          token(KeytabTokenType.modeStatus, '+'),
          token(KeytabTokenType.mode, 'Mac'),
          token(KeytabTokenType.colon, ':'),
          token(KeytabTokenType.input, 'X'),
        ]);

      final record = parser.result.records.single;
      expect(record.alt, isTrue);
      expect(record.ctrl, isFalse);
      expect(record.shift, isTrue);
      expect(record.anyModifier, isFalse);
      expect(record.ansi, isTrue);
      expect(record.appScreen, isFalse);
      expect(record.keyPad, isTrue);
      expect(record.appCursorKeys, isFalse);
      expect(record.appKeyPad, isTrue);
      expect(record.newLine, isFalse);
      expect(record.macos, isTrue);
    });

    test('addTokens can be called multiple times and accumulates', () {
      final parser = KeytabParser()
        ..addTokens([
          token(KeytabTokenType.keyDefine, 'key'),
          token(KeytabTokenType.keyName, 'Up'),
          token(KeytabTokenType.colon, ':'),
          token(KeytabTokenType.input, 'A'),
        ])
        ..addTokens([
          token(KeytabTokenType.keyDefine, 'key'),
          token(KeytabTokenType.keyName, 'Down'),
          token(KeytabTokenType.colon, ':'),
          token(KeytabTokenType.input, 'B'),
        ]);

      expect(parser.result.records, hasLength(2));
    });

    test('throws ParseError on an unexpected leading token', () {
      final parser = KeytabParser();
      expect(
        () => parser.addTokens([token(KeytabTokenType.input, 'x')]),
        throwsA(isA<ParseError>()),
      );
    });

    test('throws ParseError when keyboard name is not an input token', () {
      final parser = KeytabParser();
      expect(
        () => parser.addTokens([
          token(KeytabTokenType.keyboard, 'keyboard'),
          token(KeytabTokenType.keyName, 'Tab'),
        ]),
        throwsA(isA<ParseError>()),
      );
    });

    test('throws ParseError when key name token is missing', () {
      final parser = KeytabParser();
      expect(
        () => parser.addTokens([
          token(KeytabTokenType.keyDefine, 'key'),
          token(KeytabTokenType.colon, ':'),
        ]),
        throwsA(isA<ParseError>()),
      );
    });

    test('throws ParseError for an unknown qt key name', () {
      final parser = KeytabParser();
      expect(
        () => parser.addTokens([
          token(KeytabTokenType.keyDefine, 'key'),
          token(KeytabTokenType.keyName, 'NotARealKey'),
          token(KeytabTokenType.colon, ':'),
          token(KeytabTokenType.input, 'X'),
        ]),
        throwsA(isA<ParseError>()),
      );
    });

    test('throws ParseError for an invalid mode status', () {
      final parser = KeytabParser();
      expect(
        () => parser.addTokens([
          token(KeytabTokenType.keyDefine, 'key'),
          token(KeytabTokenType.keyName, 'Tab'),
          token(KeytabTokenType.modeStatus, '*'),
          token(KeytabTokenType.mode, 'Shift'),
          token(KeytabTokenType.colon, ':'),
          token(KeytabTokenType.input, 'X'),
        ]),
        throwsA(isA<ParseError>()),
      );
    });

    test('throws ParseError for an unknown mode name', () {
      final parser = KeytabParser();
      expect(
        () => parser.addTokens([
          token(KeytabTokenType.keyDefine, 'key'),
          token(KeytabTokenType.keyName, 'Tab'),
          token(KeytabTokenType.modeStatus, '+'),
          token(KeytabTokenType.mode, 'Bogus'),
          token(KeytabTokenType.colon, ':'),
          token(KeytabTokenType.input, 'X'),
        ]),
        throwsA(isA<ParseError>()),
      );
    });

    test('throws ParseError when a mode name does not follow a status', () {
      final parser = KeytabParser();
      expect(
        () => parser.addTokens([
          token(KeytabTokenType.keyDefine, 'key'),
          token(KeytabTokenType.keyName, 'Tab'),
          token(KeytabTokenType.modeStatus, '+'),
          token(KeytabTokenType.colon, ':'),
          token(KeytabTokenType.input, 'X'),
        ]),
        throwsA(isA<ParseError>()),
      );
    });

    test('throws ParseError when the colon is missing', () {
      final parser = KeytabParser();
      expect(
        () => parser.addTokens([
          token(KeytabTokenType.keyDefine, 'key'),
          token(KeytabTokenType.keyName, 'Tab'),
          token(KeytabTokenType.input, 'X'),
        ]),
        throwsA(isA<ParseError>()),
      );
    });

    test('throws ParseError when the action is not input or shortcut', () {
      final parser = KeytabParser();
      expect(
        () => parser.addTokens([
          token(KeytabTokenType.keyDefine, 'key'),
          token(KeytabTokenType.keyName, 'Tab'),
          token(KeytabTokenType.colon, ':'),
          token(KeytabTokenType.mode, 'Shift'),
        ]),
        throwsA(isA<ParseError>()),
      );
    });
  });
}
