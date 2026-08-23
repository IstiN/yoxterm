import 'package:test/test.dart';
import 'package:yoxterm/src/core/buffer/cell_offset.dart';
import 'package:yoxterm/src/core/mouse/button.dart';
import 'package:yoxterm/src/core/mouse/button_state.dart';
import 'package:yoxterm/src/core/mouse/handler.dart';
import 'package:yoxterm/src/core/mouse/mode.dart';
import 'package:yoxterm/src/core/platform.dart';

import '../../../_fixture/fake_terminal_state.dart';

TerminalMouseEvent event({
  TerminalMouseButton button = TerminalMouseButton.left,
  TerminalMouseButtonState buttonState = TerminalMouseButtonState.down,
  CellOffset position = const CellOffset(0, 0),
  FakeTerminalState? state,
  TerminalTargetPlatform platform = TerminalTargetPlatform.linux,
}) {
  return TerminalMouseEvent(
    button: button,
    buttonState: buttonState,
    position: position,
    state: state ?? FakeTerminalState(),
    platform: platform,
  );
}

FakeTerminalState stateWith({
  MouseMode mouseMode = MouseMode.none,
  MouseReportMode reportMode = MouseReportMode.sgr,
}) {
  return FakeTerminalState()
    ..mouseMode = mouseMode
    ..mouseReportMode = reportMode;
}

/// A handler that always returns [output].
class _ConstHandler implements TerminalMouseHandler {
  const _ConstHandler(this.output);

  final String? output;

  @override
  String? call(TerminalMouseEvent event) => output;
}

/// A handler that extends [TerminalMouseHandler] directly.
class _ExtendedHandler extends TerminalMouseHandler {
  const _ExtendedHandler();

  @override
  String? call(TerminalMouseEvent event) => 'extended';
}

void main() {
  group('CascadeMouseHandler', () {
    test('returns the first non-null result', () {
      final handler = CascadeMouseHandler([
        _ConstHandler(null),
        _ConstHandler('first'),
        _ConstHandler('second'),
      ]);

      expect(handler(event()), 'first');
    });

    test('returns null when every handler returns null', () {
      final handler = CascadeMouseHandler([
        _ConstHandler(null),
        _ConstHandler(null),
      ]);

      expect(handler(event()), isNull);
    });

    test('handlers can extend TerminalMouseHandler directly', () {
      // Non-const instantiation so the base constructor actually runs.
      // ignore: prefer_const_constructors
      expect(_ExtendedHandler().call(event()), 'extended');
    });
  });

  group('defaultMouseHandler', () {
    test('does not report when the mouse mode is none', () {
      expect(
        defaultMouseHandler(event(state: stateWith(mouseMode: MouseMode.none))),
        isNull,
      );
    });

    test('reports clicks in clickOnly mode', () {
      final output = defaultMouseHandler(event(
        state: stateWith(mouseMode: MouseMode.clickOnly),
      ));
      expect(output, '\x1b[<0;1;1M');
    });

    test('reports up and down in upDownScroll mode', () {
      final state = stateWith(mouseMode: MouseMode.upDownScroll);
      expect(
        defaultMouseHandler(event(state: state)),
        '\x1b[<0;1;1M',
      );
      expect(
        defaultMouseHandler(event(
          state: state,
          buttonState: TerminalMouseButtonState.up,
        )),
        '\x1b[<0;1;1m',
      );
    });

    test('suppresses wheel-up release events', () {
      final state = stateWith(mouseMode: MouseMode.upDownScroll);
      expect(
        defaultMouseHandler(event(
          state: state,
          button: TerminalMouseButton.wheelUp,
          buttonState: TerminalMouseButtonState.up,
        )),
        isNull,
      );
    });
  });

  group('ClickMouseHandler', () {
    const handler = ClickMouseHandler();

    test('reports button presses for the first three buttons', () {
      final state = stateWith(mouseMode: MouseMode.clickOnly);

      expect(handler(event(state: state)), '\x1b[<0;1;1M');
      expect(
        handler(event(state: state, button: TerminalMouseButton.middle)),
        '\x1b[<1;1;1M',
      );
      expect(
        handler(event(state: state, button: TerminalMouseButton.right)),
        '\x1b[<2;1;1M',
      );
    });

    test('does not report button releases', () {
      final state = stateWith(mouseMode: MouseMode.clickOnly);
      expect(
        handler(event(
          state: state,
          buttonState: TerminalMouseButtonState.up,
        )),
        isNull,
      );
    });

    test('does not report wheel buttons', () {
      final state = stateWith(mouseMode: MouseMode.clickOnly);
      for (final button in [
        TerminalMouseButton.wheelUp,
        TerminalMouseButton.wheelDown,
        TerminalMouseButton.wheelLeft,
        TerminalMouseButton.wheelRight,
      ]) {
        expect(handler(event(state: state, button: button)), isNull,
            reason: '$button');
      }
    });

    test('does nothing in other mouse modes', () {
      for (final mode in [
        MouseMode.none,
        MouseMode.upDownScroll,
        MouseMode.upDownScrollDrag,
        MouseMode.upDownScrollMove,
      ]) {
        expect(
          handler(event(state: stateWith(mouseMode: mode))),
          isNull,
          reason: '$mode',
        );
      }
    });
  });

  group('UpDownMouseHandler', () {
    const handler = UpDownMouseHandler();

    test('reports presses and releases in all upDownScroll modes', () {
      for (final mode in [
        MouseMode.upDownScroll,
        MouseMode.upDownScrollDrag,
        MouseMode.upDownScrollMove,
      ]) {
        final state = stateWith(mouseMode: mode);
        expect(handler(event(state: state)), '\x1b[<0;1;1M', reason: '$mode');
        expect(
          handler(event(
            state: state,
            buttonState: TerminalMouseButtonState.up,
          )),
          '\x1b[<0;1;1m',
          reason: '$mode',
        );
      }
    });

    test('reports wheel presses', () {
      final state = stateWith(mouseMode: MouseMode.upDownScroll);
      expect(
        handler(event(state: state, button: TerminalMouseButton.wheelUp)),
        '\x1b[<64;1;1M',
      );
      expect(
        handler(event(state: state, button: TerminalMouseButton.wheelDown)),
        '\x1b[<65;1;1M',
      );
    });

    test('never reports wheel releases', () {
      final state = stateWith(mouseMode: MouseMode.upDownScroll);
      for (final button in [
        TerminalMouseButton.wheelUp,
        TerminalMouseButton.wheelDown,
        TerminalMouseButton.wheelLeft,
        TerminalMouseButton.wheelRight,
      ]) {
        expect(
          handler(event(
            state: state,
            button: button,
            buttonState: TerminalMouseButtonState.up,
          )),
          isNull,
          reason: '$button',
        );
      }
    });

    test('does nothing in none and clickOnly modes', () {
      for (final mode in [MouseMode.none, MouseMode.clickOnly]) {
        expect(
          handler(event(state: stateWith(mouseMode: mode))),
          isNull,
          reason: '$mode',
        );
      }
    });
  });
}
