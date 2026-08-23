import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/src/ui/glyph_atlas.dart';
import 'package:yoxterm/xterm.dart';

GlyphAtlas _atlas({int capacity = 256, int columns = 16}) {
  return GlyphAtlas(
    textStyle: const TerminalStyle(fontSize: 13),
    textScaler: TextScaler.noScaling,
    cellSize: const Size(13, 16),
    devicePixelRatio: 1,
    capacity: capacity,
    columns: columns,
  );
}

void main() {
  test('assigns distinct tiles and builds an image', () {
    final atlas = _atlas();
    expect(atlas.image, isNull);
    expect(atlas.tileIndex(0x41, 0), -1); // 'A' not added yet

    atlas.ensureAll([
      GlyphAtlas.keyFor(0x41, 0),
      GlyphAtlas.keyFor(0x42, 0),
    ]);

    final a = atlas.tileIndex(0x41, 0);
    final b = atlas.tileIndex(0x42, 0);
    expect(a, 0);
    expect(b, 1);
    expect(atlas.tileCount, 2);
    expect(atlas.image, isNotNull);
    expect(atlas.image!.width, 16 * 13); // columns * tileWidth
    expect(atlas.image!.height, 16 * 16); // rows * tileHeight

    // Tile rects are distinct and inside the image.
    for (final tile in [a, b]) {
      final o = tile * 4;
      expect(atlas.tileRects[o + 2], lessThanOrEqualTo(atlas.image!.width));
      expect(atlas.tileRects[o + 3], lessThanOrEqualTo(atlas.image!.height));
    }
    expect(atlas.tileRects[0], isNot(atlas.tileRects[4]));

    atlas.disposeAndClear();
  });

  test('style variants get distinct tiles, same variant reuses its tile', () {
    final atlas = _atlas();
    atlas.ensureAll([
      GlyphAtlas.keyFor(0x41, 0),
      GlyphAtlas.keyFor(0x41, CellFlags.bold),
      GlyphAtlas.keyFor(0x41, CellFlags.italic),
      GlyphAtlas.keyFor(0x41, CellFlags.underline),
    ]);

    final plain = atlas.tileIndex(0x41, 0);
    final bold = atlas.tileIndex(0x41, CellFlags.bold);
    final italic = atlas.tileIndex(0x41, CellFlags.italic);
    final underline = atlas.tileIndex(0x41, CellFlags.underline);
    expect({plain, bold, italic, underline}, hasLength(4));

    // Unrelated flags (e.g. faint/inverse) do not change the tile.
    expect(atlas.tileIndex(0x41, CellFlags.faint), plain);
    expect(atlas.tileIndex(0x41, CellFlags.inverse), plain);
    expect(atlas.tileIndex(0x41, CellFlags.bold | CellFlags.faint), bold);

    // Adding an existing key again is a no-op (no rebuild, same image).
    final image = atlas.image;
    atlas.ensureAll([GlyphAtlas.keyFor(0x41, 0)]);
    expect(atlas.image, same(image));
    expect(atlas.tileCount, 4);

    atlas.disposeAndClear();
  });

  test('overflow keeps returning -1 so the caller falls back', () {
    final atlas = _atlas(capacity: 2, columns: 2);
    atlas.ensureAll([
      GlyphAtlas.keyFor(0x41, 0),
      GlyphAtlas.keyFor(0x42, 0),
      GlyphAtlas.keyFor(0x43, 0), // does not fit
    ]);
    expect(atlas.isFull, isTrue);
    expect(atlas.tileCount, 2);
    expect(atlas.tileIndex(0x43, 0), -1);
    // Still not added on retry.
    atlas.ensureAll([GlyphAtlas.keyFor(0x43, 0)]);
    expect(atlas.tileIndex(0x43, 0), -1);
    atlas.disposeAndClear();
  });

  test('invalidation releases tiles and the image', () {
    final atlas = _atlas();
    atlas.ensureAll([GlyphAtlas.keyFor(0x41, 0)]);
    expect(atlas.image, isNotNull);

    atlas.disposeAndClear();
    expect(atlas.image, isNull);
    expect(atlas.tileCount, 0);
    expect(atlas.tileIndex(0x41, 0), -1);

    // Atlas keeps working after invalidation.
    atlas.ensureAll([GlyphAtlas.keyFor(0x41, 0)]);
    expect(atlas.tileIndex(0x41, 0), 0);
    expect(atlas.image, isNotNull);
    atlas.disposeAndClear();
  });
}
