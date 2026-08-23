import 'package:test/test.dart';
import 'package:yoxterm/src/core/input/keys.dart';
import 'package:yoxterm/src/core/input/keytab/keytab_record.dart';

KeytabRecord record({
  String qtKeyName = 'Tab',
  TerminalKey key = TerminalKey.tab,
  KeytabAction? action,
  bool? alt,
  bool? ctrl,
  bool? shift,
  bool? anyModifier,
  bool? ansi,
  bool? appScreen,
  bool? keyPad,
  bool? appCursorKeys,
  bool? appKeyPad,
  bool? newLine,
  bool? macos,
}) {
  return KeytabRecord(
    qtKeyName: qtKeyName,
    key: key,
    action: action ?? KeytabAction(KeytabActionType.input, 'X'),
    alt: alt,
    ctrl: ctrl,
    shift: shift,
    anyModifier: anyModifier,
    ansi: ansi,
    appScreen: appScreen,
    keyPad: keyPad,
    appCursorKeys: appCursorKeys,
    appKeyPad: appKeyPad,
    newLine: newLine,
    macos: macos,
  );
}

void main() {
  group('KeytabAction', () {
    test('input actions are unescaped by unescapedValue()', () {
      final action = KeytabAction(KeytabActionType.input, r'\E[1;*H');
      expect(action.unescapedValue(), '\x1b[1;*H');
    });

    test('shortcut actions are returned verbatim by unescapedValue()', () {
      final action = KeytabAction(KeytabActionType.shortcut, r'scroll\E');
      expect(action.unescapedValue(), r'scroll\E');
    });

    test('input actions are quoted by toString()', () {
      final action = KeytabAction(KeytabActionType.input, r'\t');
      expect(action.toString(), r'"\t"');
    });

    test('shortcut actions are unquoted in toString()', () {
      final action = KeytabAction(KeytabActionType.shortcut, 'scrollPageUp');
      expect(action.toString(), 'scrollPageUp');
    });
  });

  group('KeytabRecord.toString()', () {
    test('key name without modes or action decoration', () {
      expect(record().toString(), 'key Tab  : "X"');
    });

    test('positive modes are prefixed with +', () {
      expect(
        record(shift: true).toString(),
        'key Tab +Shift : "X"',
      );
    });

    test('negative modes are prefixed with -', () {
      expect(
        record(shift: false).toString(),
        'key Tab -Shift : "X"',
      );
    });

    test('all modes are rendered in a fixed order', () {
      final text = record(
        alt: true,
        ctrl: false,
        shift: true,
        anyModifier: false,
        ansi: true,
        appScreen: false,
        keyPad: true,
        appCursorKeys: false,
        appKeyPad: true,
        newLine: false,
        macos: true,
      ).toString();

      expect(
        text,
        'key Tab '
        '+Alt-Control+Shift-AnyMod+Ansi-AppScreen+KeyPad-AppCuKeys'
        '+AppKeyPad-NewLine+Mac'
        ' : "X"',
      );
    });

    test('shortcut actions are rendered without quotes', () {
      final text = record(
        qtKeyName: 'Up',
        key: TerminalKey.arrowUp,
        action: KeytabAction(KeytabActionType.shortcut, 'scrollLineUp'),
        shift: true,
      ).toString();

      expect(text, 'key Up +Shift : scrollLineUp');
    });
  });
}
