import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';

void main() {
  const style = TextStyle(fontSize: 13, fontFamily: 'monospace');

  group('ParagraphCache', () {
    test('miss returns null, layout populates the cache', () {
      final cache = ParagraphCache(10);
      expect(cache.getLayoutFromCache(42), isNull);
      expect(cache.length, 0);

      final paragraph = cache.performAndCacheLayout(
        'hello',
        style,
        TextScaler.noScaling,
        42,
      );

      expect(cache.length, 1);
      expect(cache.getLayoutFromCache(42), same(paragraph));
    });

    test('different keys cache independent paragraphs', () {
      final cache = ParagraphCache(10);
      final a = cache.performAndCacheLayout('a', style, TextScaler.noScaling, 1);
      final b = cache.performAndCacheLayout('b', style, TextScaler.noScaling, 2);

      expect(cache.length, 2);
      expect(cache.getLayoutFromCache(1), same(a));
      expect(cache.getLayoutFromCache(2), same(b));
      expect(a, isNot(same(b)));
    });

    test('same key replaces the cached paragraph', () {
      final cache = ParagraphCache(10);
      final first =
          cache.performAndCacheLayout('a', style, TextScaler.noScaling, 1);
      final second =
          cache.performAndCacheLayout('b', style, TextScaler.noScaling, 1);

      expect(cache.length, 1);
      expect(cache.getLayoutFromCache(1), same(second));
      expect(cache.getLayoutFromCache(1), isNot(same(first)));
    });

    test('clear removes all entries', () {
      final cache = ParagraphCache(10);
      cache.performAndCacheLayout('a', style, TextScaler.noScaling, 1);
      cache.performAndCacheLayout('b', style, TextScaler.noScaling, 2);
      expect(cache.length, 2);

      cache.clear();
      expect(cache.length, 0);
      expect(cache.getLayoutFromCache(1), isNull);
      expect(cache.getLayoutFromCache(2), isNull);

      // The cache stays usable after a clear.
      final paragraph =
          cache.performAndCacheLayout('c', style, TextScaler.noScaling, 3);
      expect(cache.getLayoutFromCache(3), same(paragraph));
    });

    test('exceeding maximumSize evicts the least recently used entry', () {
      final cache = ParagraphCache(2);
      cache.performAndCacheLayout('a', style, TextScaler.noScaling, 1);
      cache.performAndCacheLayout('b', style, TextScaler.noScaling, 2);
      // Touch key 1 so key 2 becomes the LRU entry.
      expect(cache.getLayoutFromCache(1), isNotNull);

      cache.performAndCacheLayout('c', style, TextScaler.noScaling, 3);

      expect(cache.length, 2);
      expect(cache.getLayoutFromCache(1), isNotNull);
      expect(cache.getLayoutFromCache(2), isNull); // evicted
      expect(cache.getLayoutFromCache(3), isNotNull);
    });

    test('layout respects the text style and scaler', () {
      final cache = ParagraphCache(10);
      final plain = cache.performAndCacheLayout(
        'mmmm',
        style,
        TextScaler.noScaling,
        1,
      );
      final scaled = cache.performAndCacheLayout(
        'mmmm',
        style,
        const TextScaler.linear(2),
        2,
      );

      expect(scaled.maxIntrinsicWidth, greaterThan(plain.maxIntrinsicWidth));
    });

    test('laid out paragraphs have positive height and intrinsic width', () {
      final cache = ParagraphCache(10);
      final paragraph = cache.performAndCacheLayout(
        'abc',
        style,
        TextScaler.noScaling,
        1,
      );
      // Layout is unbounded (width: double.infinity), so the paragraph width
      // itself is infinite; intrinsic metrics and height stay finite.
      expect(paragraph.maxIntrinsicWidth.isFinite, isTrue);
      expect(paragraph.height, greaterThan(0));
    });
  });
}
