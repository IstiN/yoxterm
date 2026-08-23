import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/xterm.dart';

void main() {
  // Note: SingleActivator does not implement value equality, so shortcuts
  // are matched by their trigger key and modifier flags.
  Intent? findShortcut(
    Map<ShortcutActivator, Intent> shortcuts,
    LogicalKeyboardKey trigger, {
    bool control = false,
    bool shift = false,
    bool alt = false,
    bool meta = false,
  }) {
    for (final entry in shortcuts.entries) {
      final key = entry.key;
      if (key is SingleActivator &&
          key.trigger == trigger &&
          key.control == control &&
          key.shift == shift &&
          key.alt == alt &&
          key.meta == meta) {
        return entry.value;
      }
    }
    return null;
  }

  group('defaultTerminalShortcuts', () {
    test('uses Apple shortcuts on iOS and macOS', () {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        debugDefaultTargetPlatformOverride = platform;

        final shortcuts = defaultTerminalShortcuts;

        expect(
          findShortcut(shortcuts, LogicalKeyboardKey.keyC, meta: true),
          isA<CopySelectionTextIntent>(),
        );
        expect(
          findShortcut(shortcuts, LogicalKeyboardKey.keyV, meta: true),
          isA<PasteTextIntent>(),
        );
        expect(
          findShortcut(shortcuts, LogicalKeyboardKey.keyA, meta: true),
          isA<SelectAllTextIntent>(),
        );
        // Apple shortcuts must not use control.
        expect(
          findShortcut(shortcuts, LogicalKeyboardKey.keyC, control: true),
          isNull,
        );

        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('uses control based shortcuts on other platforms', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.fuchsia,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        debugDefaultTargetPlatformOverride = platform;

        final shortcuts = defaultTerminalShortcuts;

        expect(
          findShortcut(
            shortcuts,
            LogicalKeyboardKey.keyC,
            control: true,
            shift: true,
          ),
          isA<CopySelectionTextIntent>(),
        );
        expect(
          findShortcut(shortcuts, LogicalKeyboardKey.keyV, control: true),
          isA<PasteTextIntent>(),
        );
        expect(
          findShortcut(shortcuts, LogicalKeyboardKey.keyA, control: true),
          isA<SelectAllTextIntent>(),
        );

        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
