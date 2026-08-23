import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';

void main() {
  group('TerminalStyle defaults', () {
    test('has documented defaults', () {
      const style = TerminalStyle();
      expect(style.fontSize, 13.0);
      expect(style.height, 1.2);
      expect(style.fontFamily, 'monospace');
      expect(style.fontFamilyFallback, contains('Menlo'));
      expect(style.fontFamilyFallback, contains('monospace'));
      expect(style.fontFamilyFallback.last, 'sans-serif');
    });
  });

  group('TerminalStyle.fromTextStyle', () {
    test('maps every field from a fully specified TextStyle', () {
      final style = TerminalStyle.fromTextStyle(const TextStyle(
        fontSize: 20,
        height: 2.0,
        fontFamily: 'Courier',
        fontFamilyFallback: ['Menlo', 'Monaco'],
      ));
      expect(style.fontSize, 20);
      expect(style.height, 2.0);
      expect(style.fontFamily, 'Courier');
      expect(style.fontFamilyFallback, ['Menlo', 'Monaco']);
    });

    test('falls back to defaults for an empty TextStyle', () {
      final style = TerminalStyle.fromTextStyle(const TextStyle());
      expect(style.fontSize, 13.0);
      expect(style.height, 1.2);
      expect(style.fontFamily, 'monospace');
      expect(style.fontFamilyFallback, contains('Menlo'));
    });

    test('uses first fallback family when fontFamily is missing', () {
      final style = TerminalStyle.fromTextStyle(const TextStyle(
        fontFamilyFallback: ['MyMono', 'OtherMono'],
      ));
      expect(style.fontFamily, 'MyMono');
      expect(style.fontFamilyFallback, ['MyMono', 'OtherMono']);
    });

    test('keeps partial fields and defaults the rest', () {
      final style = TerminalStyle.fromTextStyle(const TextStyle(fontSize: 7));
      expect(style.fontSize, 7);
      expect(style.height, 1.2);
      expect(style.fontFamily, 'monospace');
    });
  });

  group('TerminalStyle.toTextStyle', () {
    const style = TerminalStyle(fontSize: 10, height: 1.5, fontFamily: 'X');

    test('no arguments produces plain text', () {
      final textStyle = style.toTextStyle();
      expect(textStyle.fontSize, 10);
      expect(textStyle.height, 1.5);
      expect(textStyle.fontFamily, 'X');
      expect(textStyle.color, isNull);
      expect(textStyle.backgroundColor, isNull);
      expect(textStyle.fontWeight, FontWeight.normal);
      expect(textStyle.fontStyle, FontStyle.normal);
      expect(textStyle.decoration, TextDecoration.none);
    });

    test('maps colors', () {
      final textStyle = style.toTextStyle(
        color: const Color(0xFF112233),
        backgroundColor: const Color(0xFF445566),
      );
      expect(textStyle.color, const Color(0xFF112233));
      expect(textStyle.backgroundColor, const Color(0xFF445566));
    });

    test('bold maps to FontWeight.bold', () {
      expect(style.toTextStyle(bold: true).fontWeight, FontWeight.bold);
      expect(style.toTextStyle(bold: false).fontWeight, FontWeight.normal);
    });

    test('italic maps to FontStyle.italic', () {
      expect(style.toTextStyle(italic: true).fontStyle, FontStyle.italic);
      expect(style.toTextStyle(italic: false).fontStyle, FontStyle.normal);
    });

    test('underline maps to TextDecoration.underline', () {
      expect(
        style.toTextStyle(underline: true).decoration,
        TextDecoration.underline,
      );
      expect(
        style.toTextStyle(underline: false).decoration,
        TextDecoration.none,
      );
    });

    test('all flags combine', () {
      final textStyle = style.toTextStyle(
        color: const Color(0xFFFFFFFF),
        bold: true,
        italic: true,
        underline: true,
      );
      expect(textStyle.fontWeight, FontWeight.bold);
      expect(textStyle.fontStyle, FontStyle.italic);
      expect(textStyle.decoration, TextDecoration.underline);
      expect(textStyle.color, const Color(0xFFFFFFFF));
    });
  });

  group('TerminalStyle.copyWith', () {
    test('no arguments copies every field', () {
      const style = TerminalStyle(
        fontSize: 11,
        height: 1.3,
        fontFamily: 'A',
        fontFamilyFallback: ['B'],
      );
      final copy = style.copyWith();
      expect(copy.fontSize, 11);
      expect(copy.height, 1.3);
      expect(copy.fontFamily, 'A');
      expect(copy.fontFamilyFallback, ['B']);
    });

    test('overrides only the given fields', () {
      const style = TerminalStyle(fontSize: 11, fontFamily: 'A');
      final copy = style.copyWith(fontSize: 22, fontFamilyFallback: ['C']);
      expect(copy.fontSize, 22);
      expect(copy.fontFamily, 'A');
      expect(copy.height, 1.2);
      expect(copy.fontFamilyFallback, ['C']);
    });
  });
}
