import 'package:test/test.dart';
import 'package:xterm/src/core/input/keys.dart';
import 'package:xterm/src/core/input/keytab/keytab.dart';

void main() {
  group('Keytab.parse()', () {
    test('parses the keyboard name', () {
      final keytab = Keytab.parse('keyboard "test"\nkey Tab : "\\t"');
      expect(keytab.name, 'test');
    });

    test('name is null when not declared', () {
      final keytab = Keytab.parse(r'key Tab : "\t"');
      expect(keytab.name, isNull);
    });

    test('parses all records', () {
      final keytab = Keytab.parse('''
key Tab : "\\t"
key Up : "\\E[A"
key Down : "\\EB"
''');
      expect(keytab.records, hasLength(3));
      expect(keytab.records[0].key, TerminalKey.tab);
      expect(keytab.records[1].key, TerminalKey.arrowUp);
      expect(keytab.records[2].key, TerminalKey.arrowDown);
    });
  });

  group('Keytab.find()', () {
    test('returns null when the key is not in the keytab', () {
      final keytab = Keytab.parse(r'key Tab : "\t"');
      expect(keytab.find(TerminalKey.home), isNull);
    });

    test('matches a record without any mode requirements', () {
      final keytab = Keytab.parse(r'key Tab : "\t"');
      final record = keytab.find(TerminalKey.tab, ctrl: true, shift: true);
      expect(record!.action.unescapedValue(), '\t');
    });

    test('required modifier must be pressed', () {
      final keytab = Keytab.parse(r'key Tab +Control : "X"');
      expect(keytab.find(TerminalKey.tab, ctrl: true), isNotNull);
      expect(keytab.find(TerminalKey.tab), isNull);
    });

    test('excluded modifier must not be pressed', () {
      final keytab = Keytab.parse(r'key Tab -Shift : "X"');
      expect(keytab.find(TerminalKey.tab), isNotNull);
      expect(keytab.find(TerminalKey.tab, shift: true), isNull);
    });

    test('unrelated modifiers do not affect matching', () {
      final keytab = Keytab.parse(r'key Tab +Control : "X"');
      expect(keytab.find(TerminalKey.tab, ctrl: true, alt: true), isNotNull);
    });

    test('+AnyMod requires at least one modifier', () {
      final keytab = Keytab.parse(r'key Home +AnyMod : "X"');
      expect(keytab.find(TerminalKey.home), isNull);
      expect(keytab.find(TerminalKey.home, ctrl: true), isNotNull);
      expect(keytab.find(TerminalKey.home, shift: true), isNotNull);
      expect(keytab.find(TerminalKey.home, alt: true), isNotNull);
    });

    test('-AnyMod requires no modifiers at all', () {
      final keytab = Keytab.parse(r'key Home -AnyMod : "X"');
      expect(keytab.find(TerminalKey.home), isNotNull);
      expect(keytab.find(TerminalKey.home, ctrl: true), isNull);
      expect(keytab.find(TerminalKey.home, shift: true), isNull);
      expect(keytab.find(TerminalKey.home, alt: true), isNull);
    });

    test('+AnyMod relaxes modifiers the record does not mention', () {
      // The record mentions no specific modifier, so AnyMod relaxes all of
      // them: any non-empty modifier combination matches.
      final keytab = Keytab.parse(r'key Home +AnyMod : "X"');
      expect(
        keytab.find(TerminalKey.home, ctrl: true, shift: true, alt: true),
        isNotNull,
      );
    });

    test('explicit -Shift is honored even when +AnyMod is set', () {
      final keytab = Keytab.parse(r'key Up -Shift+AnyMod : "X"');
      expect(keytab.find(TerminalKey.arrowUp, ctrl: true), isNotNull);
      expect(keytab.find(TerminalKey.arrowUp, shift: true), isNull);
    });

    test('explicit +Control is honored even when +AnyMod is set', () {
      final keytab = Keytab.parse(r'key Up +Control+AnyMod : "X"');
      expect(
        keytab.find(TerminalKey.arrowUp, ctrl: true, shift: true),
        isNotNull,
      );
      expect(keytab.find(TerminalKey.arrowUp, shift: true), isNull);
    });

    test('+AnyMod records are a fallback for more specific records', () {
      // Konsole semantics: a record that mentions its modifiers explicitly
      // wins over a +AnyMod catch-all, even when the catch-all is declared
      // earlier in the keytab.
      final keytab = Keytab.parse('''
key Up +AnyMod : "any"
key Up +Shift : "shift"
''');
      expect(
        keytab.find(TerminalKey.arrowUp, ctrl: true)!.action.unescapedValue(),
        'any',
      );
      expect(
        keytab.find(TerminalKey.arrowUp, shift: true)!.action.unescapedValue(),
        'shift',
      );
    });

    test('NewLine mode gates the record', () {
      final keytab = Keytab.parse(r'key Enter +NewLine : "\r\n"');
      expect(keytab.find(TerminalKey.enter, newLineMode: true), isNotNull);
      expect(keytab.find(TerminalKey.enter), isNull);
    });

    test('AppCuKeys mode gates the record', () {
      final keytab = Keytab.parse(r'key Up +AppCuKeys : "\EOA"');
      expect(keytab.find(TerminalKey.arrowUp, appCursorKeys: true), isNotNull);
      expect(keytab.find(TerminalKey.arrowUp), isNull);
    });

    test('AppKeyPad mode gates the record', () {
      final keytab = Keytab.parse(r'key Up +AppKeyPad : "X"');
      expect(keytab.find(TerminalKey.arrowUp, appKeyPad: true), isNotNull);
      expect(keytab.find(TerminalKey.arrowUp), isNull);
    });

    test('KeyPad mode gates the record', () {
      final keytab = Keytab.parse(r'key Up -KeyPad : "X"');
      expect(keytab.find(TerminalKey.arrowUp), isNotNull);
      expect(keytab.find(TerminalKey.arrowUp, keyPad: true), isNull);
    });

    test('AppScreen mode gates the record', () {
      final keytab = Keytab.parse(r'key Up +AppScreen : "X"');
      expect(keytab.find(TerminalKey.arrowUp, appScreen: true), isNotNull);
      expect(keytab.find(TerminalKey.arrowUp), isNull);
    });

    test('Mac mode gates the record', () {
      final keytab = Keytab.parse(r'key Right +Mac : "\Ef"');
      expect(keytab.find(TerminalKey.arrowRight, macos: true), isNotNull);
      expect(keytab.find(TerminalKey.arrowRight), isNull);
    });

    test('-Ansi records are never matched (VT52 is not supported)', () {
      final keytab = Keytab.parse(r'key Up -Ansi : "\EA"');
      expect(keytab.find(TerminalKey.arrowUp), isNull);
    });

    test('the first matching record wins', () {
      final keytab = Keytab.parse('''
key Up : "first"
key Up : "second"
''');
      expect(
        keytab.find(TerminalKey.arrowUp)!.action.unescapedValue(),
        'first',
      );
    });

    test('later records are used when earlier ones do not match', () {
      final keytab = Keytab.parse('''
key Up +Control : "ctrl"
key Up : "plain"
''');
      expect(
        keytab.find(TerminalKey.arrowUp)!.action.unescapedValue(),
        'plain',
      );
      expect(
        keytab.find(TerminalKey.arrowUp, ctrl: true)!.action.unescapedValue(),
        'ctrl',
      );
    });

    test('multiple modes must all be satisfied', () {
      final keytab =
          Keytab.parse(r'key Right -Shift+Alt-Control+Ansi-Mac : "X"');

      // All conditions satisfied.
      expect(keytab.find(TerminalKey.arrowRight, alt: true), isNotNull);

      // Each single violation rejects the record.
      expect(
        keytab.find(TerminalKey.arrowRight, alt: true, shift: true),
        isNull,
      );
      expect(keytab.find(TerminalKey.arrowRight), isNull);
      expect(
        keytab.find(TerminalKey.arrowRight, alt: true, ctrl: true),
        isNull,
      );
      expect(
        keytab.find(TerminalKey.arrowRight, alt: true, macos: true),
        isNull,
      );
    });
  });

  group('Keytab.toString()', () {
    test('contains the keyboard header and one line per record', () {
      final keytab = Keytab.parse('''
keyboard "test"
key Tab -Shift : "\\t"
key Up : scrollLineUp
''');

      final text = keytab.toString();
      final lines = text.trim().split('\n');

      expect(lines, hasLength(3));
      expect(lines[0], 'keyboard "test"');
      expect(lines[1], 'key Tab -Shift : "\\t"');
      // Note the double space: the key name is always followed by a space
      // even when no modes are present.
      expect(lines[2], 'key Up  : scrollLineUp');
    });

    test('output can be parsed back into an equivalent keytab', () {
      final keytab = Keytab.parse('''
keyboard "test"
key Tab -Shift : "\\t"
key Up +Shift-AppScreen : scrollLineUp
key Home +AnyMod : "\\E[1;*H"
''');

      final reparsed = Keytab.parse(keytab.toString());

      expect(reparsed.name, keytab.name);
      expect(reparsed.records, hasLength(keytab.records.length));
      for (var i = 0; i < keytab.records.length; i++) {
        expect(reparsed.records[i].key, keytab.records[i].key);
        expect(reparsed.records[i].toString(), keytab.records[i].toString());
      }
    });
  });
}
