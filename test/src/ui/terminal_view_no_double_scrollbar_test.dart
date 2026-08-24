// Regression test: TerminalView must not render its own scrollbar so the
// host application's themed scrollbar is the only one shown.
//
// Symptom: in yoloit, the terminal panel wrapped the TerminalView in a
// purple RawScrollbar. xterm's inner Scrollable (Cupertino on macOS)
// also rendered its own gray scrollbar, so two bars appeared side by
// side.
//
// Fix: TerminalView wraps its inner Scrollable in a ScrollConfiguration
// with _NoScrollbarScrollBehavior, which returns the child unchanged from
// buildScrollbar (no scrollbar widget is appended). This test pins that
// invariant by counting how many Scrollbar-like widgets appear in the
// rendered subtree of a TerminalView.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yoxterm/xterm.dart';

void main() {
  testWidgets(
    'TerminalView renders no Cupertino scrollbar in its subtree',
    (tester) async {
      final terminal = Terminal();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalView(terminal),
            ),
          ),
        ),
      );
      await tester.pump();

      // Find every widget whose type name indicates a scrollbar. Flutter
      // ships Material's Scrollbar, Cupertino's CupertinoScrollbar, and
      // RawScrollbar — count any of them as "a scrollbar".
      final scrollbars = find
          .byWidgetPredicate(
            (w) => const {
              'Scrollbar',
              'CupertinoScrollbar',
              'RawScrollbar',
            }.contains(w.runtimeType.toString()),
          )
          .evaluate();

      expect(scrollbars.length, 0,
          reason: 'TerminalView must not render any visible scrollbar; '
              'the host supplies its own. Found: $scrollbars');
    },
  );
}