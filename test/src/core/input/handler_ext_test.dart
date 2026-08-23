import 'package:test/test.dart';
import 'package:xterm/src/core/input/handler.dart';
import 'package:xterm/src/core/input/keys.dart';
import 'package:xterm/src/core/input/keytab/keytab.dart';
import 'package:xterm/src/core/platform.dart';

import '../../../_fixture/fake_terminal_state.dart';

TerminalKeyboardEvent event({
  TerminalKey key = TerminalKey.keyA,
  bool shift = false,
  bool ctrl = false,
  bool alt = false,
  FakeTerminalState? state,
  bool altBuffer = false,
  TerminalTargetPlatform platform = TerminalTargetPlatform.linux,
}) {
  return TerminalKeyboardEvent(
    key: key,
    shift: shift,
    ctrl: ctrl,
    alt: alt,
    state: state ?? FakeTerminalState(),
    altBuffer: altBuffer,
    platform: platform,
  );
}

/// A handler that always returns [output].
class _ConstHandler implements TerminalInputHandler {
  _ConstHandler(this.output);

  final String? output;

  @override
  String? call(TerminalKeyboardEvent event) => output;
}

void main() {
  group('TerminalKeyboardEvent', () {
    test('copyWith replaces selected fields', () {
      final original = event(key: TerminalKey.keyA);
      final copy = original.copyWith(key: TerminalKey.keyB, ctrl: true);

      expect(copy.key, TerminalKey.keyB);
      expect(copy.ctrl, isTrue);
      expect(copy.shift, original.shift);
      expect(copy.alt, original.alt);
      expect(copy.state, same(original.state));
      expect(copy.altBuffer, original.altBuffer);
      expect(copy.platform, original.platform);
    });

    test('copyWith without arguments keeps all fields', () {
      final original = event(key: TerminalKey.f5, shift: true, altBuffer: true);
      final copy = original.copyWith();

      expect(copy.key, original.key);
      expect(copy.shift, isTrue);
      expect(copy.altBuffer, isTrue);
      expect(copy.platform, original.platform);
    });

    test('toString contains the field values', () {
      final text = event(key: TerminalKey.keyC, ctrl: true).toString();

      expect(text, contains('key: TerminalKey.keyC'));
      expect(text, contains('ctrl: true'));
      expect(text, contains('altBuffer: false'));
    });
  });

  group('CascadeInputHandler', () {
    test('returns the first non-null result', () {
      final handler = CascadeInputHandler([
        _ConstHandler(null),
        _ConstHandler('first'),
        _ConstHandler('second'),
      ]);

      expect(handler(event()), 'first');
    });

    test('returns null when every handler returns null', () {
      final handler = CascadeInputHandler([
        _ConstHandler(null),
        _ConstHandler(null),
      ]);

      expect(handler(event()), isNull);
    });

    test('empty cascade returns null', () {
      expect(const CascadeInputHandler([]).call(event()), isNull);
    });
  });

  group('defaultInputHandler', () {
    test('maps plain keys through the default keytab', () {
      expect(
        defaultInputHandler(event(key: TerminalKey.arrowUp)),
        '\x1b[A',
      );
      expect(defaultInputHandler(event(key: TerminalKey.enter)), '\r');
    });

    test('ctrl + letter produces the control character', () {
      expect(
        defaultInputHandler(event(key: TerminalKey.keyC, ctrl: true)),
        '\x03',
      );
    });

    test('alt + letter produces ESC + uppercase letter', () {
      expect(
        defaultInputHandler(event(key: TerminalKey.keyA, alt: true)),
        '\x1bA',
      );
    });

    test('alt + letter does nothing on macOS', () {
      expect(
        defaultInputHandler(
          event(
            key: TerminalKey.keyA,
            alt: true,
            platform: TerminalTargetPlatform.macos,
          ),
        ),
        isNull,
      );
    });

    test('unmapped key returns null', () {
      expect(defaultInputHandler(event(key: TerminalKey.f20)), isNull);
    });

    test('arrow keys follow DECCKM (cursorKeysMode)', () {
      final state = FakeTerminalState()..cursorKeysMode = true;
      expect(
        defaultInputHandler(event(key: TerminalKey.arrowUp, state: state)),
        '\x1bOA',
      );
      expect(
        defaultInputHandler(event(key: TerminalKey.arrowDown, state: state)),
        '\x1bOB',
      );
    });

    test('appKeypadMode does not affect cursor keys', () {
      final state = FakeTerminalState()..appKeypadMode = true;
      expect(
        defaultInputHandler(event(key: TerminalKey.arrowUp, state: state)),
        '\x1b[A',
      );
    });
  });

  group('KeytabInputHandler', () {
    final keytab = Keytab.parse(r'key Home : "\E[1;*H"');
    const handler = KeytabInputHandler();

    test('returns null when no record matches', () {
      final h = KeytabInputHandler(Keytab.parse(r'key End : "\E[F"'));
      expect(h(event(key: TerminalKey.home)), isNull);
    });

    test('uses the default keytab when none is provided', () {
      expect(handler(event(key: TerminalKey.arrowUp)), '\x1b[A');
    });

    test('unescaped action is returned', () {
      final h = KeytabInputHandler(keytab);
      expect(h(event(key: TerminalKey.home)), '\x1b[1;*H');
    });

    group('insertModifiers', () {
      final h = KeytabInputHandler(keytab);

      final combos = {
        'shift': (true, false, false, '2'),
        'alt': (false, false, true, '3'),
        'shift+alt': (true, false, true, '4'),
        'ctrl': (false, true, false, '5'),
        'shift+ctrl': (true, true, false, '6'),
        'ctrl+alt': (false, true, true, '7'),
        'shift+ctrl+alt': (true, true, true, '8'),
      };

      combos.forEach((name, combo) {
        test('$name inserts code ${combo.$4}', () {
          final output = h(event(
            key: TerminalKey.home,
            shift: combo.$1,
            ctrl: combo.$2,
            alt: combo.$3,
          ));
          expect(output, '\x1b[1;${combo.$4}H');
        });
      });
    });

    test('shortcut actions are returned unescaped as-is', () {
      final h = KeytabInputHandler(
        Keytab.parse(r'key Up +Shift : scrollLineUp'),
      );
      expect(h(event(key: TerminalKey.arrowUp, shift: true)), 'scrollLineUp');
    });
  });

  group('CtrlInputHandler', () {
    const handler = CtrlInputHandler();

    test('ctrl + a .. z map to 0x01 .. 0x1a', () {
      final keys = [
        TerminalKey.keyA,
        TerminalKey.keyB,
        TerminalKey.keyC,
        TerminalKey.keyD,
        TerminalKey.keyE,
      ];
      for (var i = 0; i < keys.length; i++) {
        expect(
          handler(event(key: keys[i], ctrl: true)),
          String.fromCharCode(1 + i),
          reason: 'ctrl + ${keys[i]}',
        );
      }
      expect(handler(event(key: TerminalKey.keyZ, ctrl: true)), '\x1a');
    });

    test('ignored without ctrl', () {
      expect(handler(event(key: TerminalKey.keyA)), isNull);
    });

    test('ignored when shift is also pressed', () {
      expect(handler(event(key: TerminalKey.keyA, ctrl: true, shift: true)),
          isNull);
    });

    test('ignored when alt is also pressed', () {
      expect(handler(event(key: TerminalKey.keyA, ctrl: true, alt: true)),
          isNull);
    });

    test('ignored for non-letter keys', () {
      expect(handler(event(key: TerminalKey.home, ctrl: true)), isNull);
      expect(handler(event(key: TerminalKey.digit1, ctrl: true)), isNull);
    });
  });

  group('AltInputHandler', () {
    const handler = AltInputHandler();

    test('alt + a .. z map to ESC + uppercase letter', () {
      expect(handler(event(key: TerminalKey.keyA, alt: true)), '\x1bA');
      expect(handler(event(key: TerminalKey.keyM, alt: true)), '\x1bM');
      expect(handler(event(key: TerminalKey.keyZ, alt: true)), '\x1bZ');
    });

    test('ignored without alt', () {
      expect(handler(event(key: TerminalKey.keyA)), isNull);
    });

    test('ignored when ctrl is also pressed', () {
      expect(handler(event(key: TerminalKey.keyA, alt: true, ctrl: true)),
          isNull);
    });

    test('ignored when shift is also pressed', () {
      expect(handler(event(key: TerminalKey.keyA, alt: true, shift: true)),
          isNull);
    });

    test('ignored on macOS', () {
      expect(
        handler(event(
          key: TerminalKey.keyA,
          alt: true,
          platform: TerminalTargetPlatform.macos,
        )),
        isNull,
      );
    });

    test('works on other desktop platforms', () {
      for (final platform in [
        TerminalTargetPlatform.windows,
        TerminalTargetPlatform.linux,
      ]) {
        expect(
          handler(event(
              key: TerminalKey.keyB, alt: true, platform: platform)),
          '\x1bB',
          reason: '$platform',
        );
      }
    });

    test('ignored for non-letter keys', () {
      expect(handler(event(key: TerminalKey.home, alt: true)), isNull);
      expect(handler(event(key: TerminalKey.digit1, alt: true)), isNull);
    });
  });
}
