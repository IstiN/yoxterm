import 'package:test/test.dart';
import 'package:yoxterm/core.dart';

void main() {
  group('Terminal.syncOutputMode (DEC 2026)', () {
    test('defaults to disabled', () {
      final terminal = Terminal();
      expect(terminal.syncOutputMode, isFalse);
    });

    test('set/reset round-trips through the parser', () {
      final terminal = Terminal();

      terminal.write('\x1b[?2026h');
      expect(terminal.syncOutputMode, isTrue);

      terminal.write('\x1b[?2026l');
      expect(terminal.syncOutputMode, isFalse);
    });

    test('output between BSU and ESU mutates the buffer without notifying',
        () {
      final terminal = Terminal();
      var notifications = 0;
      terminal.addListener(() => notifications++);

      terminal.write('\x1b[?2026h');
      expect(notifications, 0);

      // Fast path (plain text) and parser path (escape sequences) are both
      // suppressed while the frame accumulates.
      terminal.write('hello');
      terminal.write('\x1b[0m');
      terminal.write(' world');
      expect(notifications, 0);
      expect(terminal.buffer.lines[0].toString(), 'hello world');
    });

    test('ESU triggers exactly one notification', () {
      final terminal = Terminal();
      var notifications = 0;
      terminal.addListener(() => notifications++);

      terminal.write('\x1b[?2026h');
      terminal.write('frame');
      expect(notifications, 0);

      terminal.write('\x1b[?2026l');
      expect(notifications, 1);
      expect(terminal.buffer.lines[0].toString(), 'frame');
    });

    test('ESU without a preceding BSU does not notify', () {
      final terminal = Terminal();
      var notifications = 0;
      terminal.addListener(() => notifications++);

      terminal.write('\x1b[?2026l');
      // Only the notification from write() itself, not an extra flush.
      expect(notifications, 1);
    });

    test('failsafe flushes when ESU never arrives', () async {
      final terminal = Terminal();
      var notifications = 0;
      terminal.addListener(() => notifications++);

      terminal.write('\x1b[?2026h');
      terminal.write('stalled');
      expect(notifications, 0);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(terminal.syncOutputMode, isFalse);
      expect(notifications, 1);
      expect(terminal.buffer.lines[0].toString(), 'stalled');
    });

    test('ESU cancels the failsafe', () async {
      final terminal = Terminal();
      var notifications = 0;
      terminal.addListener(() => notifications++);

      terminal.write('\x1b[?2026h');
      terminal.write('frame');
      terminal.write('\x1b[?2026l');
      expect(notifications, 1);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(notifications, 1);
    });

    test('dispose cancels a pending failsafe', () async {
      final terminal = Terminal();
      var notifications = 0;
      terminal.addListener(() => notifications++);

      terminal.write('\x1b[?2026h');
      terminal.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(notifications, 0);
    });

    test('writes without 2026 notify as before', () {
      final terminal = Terminal();
      var notifications = 0;
      terminal.addListener(() => notifications++);

      terminal.write('a');
      terminal.write('\x1b[2K');
      expect(notifications, 2);
    });
  });
}
