import 'dart:ui';

import 'package:flutter/widgets.dart';

/// A cache of laid out [Paragraph]s. This is used to avoid laying out the
/// same text multiple times, which is expensive.
///
/// Entries are kept in least-recently-used order: every lookup or (re)layout
/// promotes the key to the most-recently-used position, and when the cache
/// exceeds its maximum size the least recently used entries are evicted.
///
/// Unlike a plain [Map]-backed LRU, eviction, replacement, [clear] and
/// [dispose] all call [Paragraph.dispose] on the dropped values, so cached
/// paragraphs do not wait for the GC to release their native memory.
class ParagraphCache {
  ParagraphCache(int maximumSize) : _maximumSize = maximumSize;

  final int _maximumSize;

  /// Backing store. Iteration order is least-recently-used first; a lookup
  /// or layout moves its key to the end (most-recently-used).
  final Map<int, Paragraph> _cache = <int, Paragraph>{};

  /// Number of paragraphs disposed by this cache through eviction,
  /// replacement, [clear] or [dispose]. Exposed for tests.
  @visibleForTesting
  int debugDisposedCount = 0;

  /// Returns a [Paragraph] for the given [key]. [key] is the same as the
  /// key argument to [performAndCacheLayout].
  Paragraph? getLayoutFromCache(int key) {
    final paragraph = _cache.remove(key);
    if (paragraph == null) return null;
    // Promote to most-recently-used.
    _cache[key] = paragraph;
    return paragraph;
  }

  /// Applies [style] and [textScaler] to [text] and lays it out to create a
  /// [Paragraph]. The [Paragraph] is cached and can be retrieved with the
  /// same [key] by calling [getLayoutFromCache].
  Paragraph performAndCacheLayout(
    String text,
    TextStyle style,
    TextScaler textScaler,
    int key,
  ) {
    final builder = ParagraphBuilder(style.getParagraphStyle());
    builder.pushStyle(style.getTextStyle(textScaler: textScaler));
    builder.addText(text);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    // Replace any existing entry (disposing it) and insert as MRU.
    final previous = _cache.remove(key);
    if (previous != null) _disposeParagraph(previous);
    _cache[key] = paragraph;
    _evictEldestWhileOversized();
    return paragraph;
  }

  /// Clears the cache, disposing every cached paragraph. This should be
  /// called when the same text and style pair no longer produces the same
  /// layout. For example, when a font is loaded.
  void clear() {
    for (final paragraph in _cache.values) {
      paragraph.dispose();
    }
    debugDisposedCount += _cache.length;
    _cache.clear();
  }

  /// Disposes every cached paragraph and releases the cache. The cache must
  /// not be used after disposal.
  void dispose() {
    clear();
  }

  /// Returns the number of [Paragraph]s in the cache.
  int get length {
    return _cache.length;
  }

  /// Drops the least recently used entries until the cache fits within
  /// [_maximumSize].
  void _evictEldestWhileOversized() {
    while (_cache.length > _maximumSize) {
      final eldest = _cache.entries.first;
      _cache.remove(eldest.key);
      _disposeParagraph(eldest.value);
    }
  }

  void _disposeParagraph(Paragraph paragraph) {
    paragraph.dispose();
    debugDisposedCount++;
  }
}
