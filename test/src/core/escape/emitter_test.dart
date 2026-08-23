import 'package:test/test.dart';
import 'package:xterm/src/core/escape/emitter.dart';

void main() {
  const emitter = EscapeEmitter();

  group('EscapeEmitter', () {
    test('primaryDeviceAttributes responds as a VT102', () {
      expect(emitter.primaryDeviceAttributes(), '\x1b[?1;2c');
    });

    test('secondaryDeviceAttributes reports model/version 0', () {
      expect(emitter.secondaryDeviceAttributes(), '\x1b[>0;0;0c');
    });

    test('tertiaryDeviceAttributes reports all-zero unit id', () {
      expect(emitter.tertiaryDeviceAttributes(), '\x1bP!|00000000\x1b\\');
    });

    test('operatingStatus reports no malfunction', () {
      expect(emitter.operatingStatus(), '\x1b[0n');
    });

    test('cursorPosition encodes 1-based row;column', () {
      expect(emitter.cursorPosition(10, 5), '\x1b[5;10R');
    });

    test('cursorPosition at origin', () {
      expect(emitter.cursorPosition(0, 0), '\x1b[0;0R');
    });

    test('bracketedPaste wraps text in 200~/201~ markers', () {
      expect(emitter.bracketedPaste('hello'), '\x1b[200~hello\x1b[201~');
    });

    test('bracketedPaste with empty text still emits both markers', () {
      expect(emitter.bracketedPaste(''), '\x1b[200~\x1b[201~');
    });

    test('size encodes rows;cols as a window manipulation report', () {
      expect(emitter.size(24, 80), '\x1b[8;24;80t');
    });
  });
}
