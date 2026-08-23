import 'package:test/test.dart';
import 'package:yoxterm/src/core/input/keytab/keytab.dart';
import 'package:yoxterm/src/core/input/keytab/keytab_default.dart'
    as keytab_default;
import 'package:yoxterm/src/core/input/keytab/keytab_default.dart';
import 'package:yoxterm/src/core/input/keytab/keytab_record.dart';
import 'package:yoxterm/src/core/input/keys.dart';

String? actionOf(
  TerminalKey key, {
  bool ctrl = false,
  bool alt = false,
  bool shift = false,
  bool newLineMode = false,
  bool appCursorKeys = false,
  bool appKeyPad = false,
  bool keyPad = false,
  bool appScreen = false,
  bool macos = false,
}) {
  final record = Keytab.defaultKeytab.find(
    key,
    ctrl: ctrl,
    alt: alt,
    shift: shift,
    newLineMode: newLineMode,
    appCursorKeys: appCursorKeys,
    appKeyPad: appKeyPad,
    keyPad: keyPad,
    appScreen: appScreen,
    macos: macos,
  );
  return record?.action.unescapedValue();
}

void main() {
  group('kDefaultKeytab', () {
    test('parses without errors', () {
      final keytab = Keytab.parse(kDefaultKeytab);
      expect(keytab.name, 'Default (XFree 4)');
    });

    test('the bundled debug main() prints the parsed keytab', () {
      // keytab_default.dart ships a dev-only main() that tokenizes and
      // prints the default keytab; make sure it keeps working.
      expect(keytab_default.main, returnsNormally);
    });

    test('every non-comment "key" line becomes a record', () {
      final declared = kDefaultKeytab
          .split('\n')
          .map((line) => line.replaceFirst(RegExp('#.*'), '').trim())
          .where((line) => line.startsWith('key '))
          .length;

      expect(Keytab.defaultKeytab.records, hasLength(declared));
    });

    test('every record resolves to a known key', () {
      for (final record in Keytab.defaultKeytab.records) {
        expect(record.qtKeyName, isNotEmpty);
        // TerminalKey.none would indicate a lookup failure.
        expect(record.key, isNot(TerminalKey.none));
      }
    });
  });

  group('default keytab: common keys', () {
    test('escape', () {
      expect(actionOf(TerminalKey.escape), '\x1b');
    });

    test('tab and shift+tab', () {
      expect(actionOf(TerminalKey.tab), '\t');
      expect(actionOf(TerminalKey.tab, shift: true), '\x1b[Z');
      expect(actionOf(TerminalKey.backtab), '\x1b[Z');
    });

    test('return honors the newline mode', () {
      expect(actionOf(TerminalKey.returnKey), '\r');
      expect(actionOf(TerminalKey.returnKey, newLineMode: true), '\r\n');
      expect(actionOf(TerminalKey.returnKey, shift: true), '\x1bOM');
    });

    test('enter and numpad enter honor the newline mode', () {
      expect(actionOf(TerminalKey.enter), '\r');
      expect(actionOf(TerminalKey.enter, newLineMode: true), '\r\n');
      expect(actionOf(TerminalKey.numpadEnter), '\r');
      expect(actionOf(TerminalKey.numpadEnter, newLineMode: true), '\r\n');
    });

    test('backspace', () {
      expect(actionOf(TerminalKey.backspace), '\x7f');
      expect(actionOf(TerminalKey.backspace, ctrl: true), '\x08');
      expect(actionOf(TerminalKey.backspace, alt: true), '\x17');
    });

    test('ctrl+space is NUL', () {
      expect(actionOf(TerminalKey.space, ctrl: true), '\x00');
    });
  });

  group('default keytab: arrow keys', () {
    test('plain arrows use normal cursor mode sequences', () {
      expect(actionOf(TerminalKey.arrowUp), '\x1b[A');
      expect(actionOf(TerminalKey.arrowDown), '\x1b[B');
      expect(actionOf(TerminalKey.arrowRight), '\x1b[C');
      expect(actionOf(TerminalKey.arrowLeft), '\x1b[D');
    });

    test('application cursor mode uses SS3 sequences', () {
      expect(actionOf(TerminalKey.arrowUp, appCursorKeys: true), '\x1bOA');
      expect(actionOf(TerminalKey.arrowDown, appCursorKeys: true), '\x1bOB');
      expect(actionOf(TerminalKey.arrowRight, appCursorKeys: true), '\x1bOC');
      expect(actionOf(TerminalKey.arrowLeft, appCursorKeys: true), '\x1bOD');
    });

    test('ctrl+arrows keep the modifier placeholder', () {
      expect(actionOf(TerminalKey.arrowUp, ctrl: true), '\x1b[1;5A');
      expect(actionOf(TerminalKey.arrowDown, ctrl: true), '\x1b[1;5B');
      expect(actionOf(TerminalKey.arrowRight, ctrl: true), '\x1b[1;5C');
      expect(actionOf(TerminalKey.arrowLeft, ctrl: true), '\x1b[1;5D');
    });

    test('alt+left/right move by word on non-mac platforms', () {
      expect(actionOf(TerminalKey.arrowRight, alt: true), '\x1b[1;5C');
      expect(actionOf(TerminalKey.arrowLeft, alt: true), '\x1b[1;5D');
    });

    test('alt+left/right use word movement escapes on macOS', () {
      expect(actionOf(TerminalKey.arrowRight, alt: true, macos: true),
          '\x1bf');
      expect(
          actionOf(TerminalKey.arrowLeft, alt: true, macos: true), '\x1bb');
    });

    test('shift+left/right in the alt buffer keep the placeholder', () {
      // Left/Right have no +AnyMod record, so the +Shift+AppScreen records
      // are reachable for them.
      expect(
        actionOf(TerminalKey.arrowLeft, shift: true, appScreen: true),
        '\x1b[1;*D',
      );
      expect(
        actionOf(TerminalKey.arrowRight, shift: true, appScreen: true),
        '\x1b[1;*C',
      );
    });

    test('shift+up/down in the alt buffer keep the placeholder', () {
      // The explicit -Shift on the `-Shift+AnyMod+Ansi` records is honored
      // even though AnyMod is set, so the +Shift+AppScreen records win.
      expect(
        actionOf(TerminalKey.arrowUp, shift: true, appScreen: true),
        '\x1b[1;*A',
      );
      expect(
        actionOf(TerminalKey.arrowDown, shift: true, appScreen: true),
        '\x1b[1;*B',
      );
    });

    test('VT52 (-Ansi) records never match', () {
      // The VT52 record would produce '\x1bA'; the ANSI record must win.
      expect(actionOf(TerminalKey.arrowUp), isNot('\x1bA'));
    });

    test('keypad arrows follow the cursor key mode', () {
      expect(
        actionOf(TerminalKey.arrowUp, appCursorKeys: true, keyPad: true),
        '\x1bOA',
      );
      expect(actionOf(TerminalKey.arrowUp, keyPad: true), '\x1b[A');
    });
  });

  group('default keytab: navigation keys', () {
    test('home and end', () {
      expect(actionOf(TerminalKey.home), '\x1b[H');
      expect(actionOf(TerminalKey.end), '\x1b[F');
      expect(actionOf(TerminalKey.home, appCursorKeys: true), '\x1bOH');
      expect(actionOf(TerminalKey.end, appCursorKeys: true), '\x1bOF');
    });

    test('home and end with ctrl keep the placeholder', () {
      expect(actionOf(TerminalKey.home, ctrl: true), '\x1b[1;*H');
      expect(actionOf(TerminalKey.end, ctrl: true), '\x1b[1;*F');
    });

    test('insert and delete', () {
      expect(actionOf(TerminalKey.insert), '\x1b[2~');
      expect(actionOf(TerminalKey.delete), '\x1b[3~');
      expect(actionOf(TerminalKey.insert, ctrl: true), '\x1b[2;*~');
      expect(actionOf(TerminalKey.delete, shift: true), '\x1b[3;*~');
    });

    test('page up and page down', () {
      expect(actionOf(TerminalKey.pageUp), '\x1b[5~');
      expect(actionOf(TerminalKey.pageDown), '\x1b[6~');
      expect(actionOf(TerminalKey.pageUp, ctrl: true), '\x1b[5;*~');
      expect(actionOf(TerminalKey.pageDown, alt: true), '\x1b[6;*~');
    });

    test('keypad variants', () {
      expect(actionOf(TerminalKey.insert, keyPad: true), '\x1b[2~');
      expect(actionOf(TerminalKey.delete, keyPad: true), '\x1b[3~');
      expect(actionOf(TerminalKey.pageUp, keyPad: true), '\x1b[5~');
      expect(actionOf(TerminalKey.pageDown, keyPad: true), '\x1b[6~');
      expect(actionOf(TerminalKey.numpadClear, keyPad: true), '\x1b[E');
      expect(actionOf(TerminalKey.home, appCursorKeys: true, keyPad: true),
          '\x1bOH');
    });
  });

  group('default keytab: function keys', () {
    test('unmodified function keys', () {
      final expected = {
        TerminalKey.f1: '\x1bOP',
        TerminalKey.f2: '\x1bOQ',
        TerminalKey.f3: '\x1bOR',
        TerminalKey.f4: '\x1bOS',
        TerminalKey.f5: '\x1b[15~',
        TerminalKey.f6: '\x1b[17~',
        TerminalKey.f7: '\x1b[18~',
        TerminalKey.f8: '\x1b[19~',
        TerminalKey.f9: '\x1b[20~',
        TerminalKey.f10: '\x1b[21~',
        TerminalKey.f11: '\x1b[23~',
        TerminalKey.f12: '\x1b[24~',
      };

      expected.forEach((key, sequence) {
        expect(actionOf(key), sequence, reason: '$key');
      });
    });

    test('modified function keys keep the placeholder', () {
      expect(actionOf(TerminalKey.f1, shift: true), '\x1bO*P');
      expect(actionOf(TerminalKey.f4, ctrl: true), '\x1bO*S');
      expect(actionOf(TerminalKey.f5, shift: true), '\x1b[15;*~');
      expect(actionOf(TerminalKey.f12, ctrl: true), '\x1b[24;*~');
    });
  });

  group('default keytab: scroll shortcuts', () {
    test('all six scroll shortcut records are declared', () {
      final shortcuts = Keytab.defaultKeytab.records
          .where((record) => record.action.type == KeytabActionType.shortcut)
          .map((record) => record.action.value)
          .toSet();

      expect(shortcuts, {
        'scrollLineUp',
        'scrollPageUp',
        'scrollUpToTop',
        'scrollLineDown',
        'scrollPageDown',
        'scrollDownToBottom',
      });
    });

    test('all six scroll shortcuts are reachable via shift+key', () {
      // find() honors the explicit +Shift on the shortcut records and
      // treats the +AnyMod input records as fallbacks, so shift+key now
      // resolves to the scroll shortcuts.
      expect(actionOf(TerminalKey.arrowUp, shift: true), 'scrollLineUp');
      expect(actionOf(TerminalKey.arrowDown, shift: true), 'scrollLineDown');
      expect(actionOf(TerminalKey.pageUp, shift: true), 'scrollPageUp');
      expect(actionOf(TerminalKey.pageDown, shift: true), 'scrollPageDown');
      expect(actionOf(TerminalKey.home, shift: true), 'scrollUpToTop');
      expect(actionOf(TerminalKey.end, shift: true), 'scrollDownToBottom');
    });

    test('shift+page keys inside the alt buffer produce nothing', () {
      // The scroll shortcut records require -AppScreen, and the
      // escape-sequence records require -Shift, so no record matches.
      expect(
        actionOf(TerminalKey.pageUp, shift: true, appScreen: true),
        isNull,
      );
      expect(
        actionOf(TerminalKey.pageDown, shift: true, appScreen: true),
        isNull,
      );
    });
  });
}
