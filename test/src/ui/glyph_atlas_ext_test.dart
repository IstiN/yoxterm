import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/src/ui/glyph_atlas.dart';
import 'package:yoxterm/xterm.dart';

GlyphAtlas _atlas({
  int capacity = 256,
  int columns = 16,
  double devicePixelRatio = 1,
  Size cellSize = const Size(13, 16),
}) {
  return GlyphAtlas(
    textStyle: const TerminalStyle(fontSize: 13),
    textScaler: TextScaler.noScaling,
    cellSize: cellSize,
    devicePixelRatio: devicePixelRatio,
    capacity: capacity,
    columns: columns,
  );
}

void main() {
  group('GlyphAtlas.keyFor', () {
    test('encodes bold/italic/underline in bits 21..23', () {
      expect(GlyphAtlas.keyFor(0x41, 0), 0x41);
      expect(GlyphAtlas.keyFor(0x41, CellFlags.bold), 0x41 | (1 << 21));
      expect(GlyphAtlas.keyFor(0x41, CellFlags.italic), 0x41 | (1 << 22));
      expect(GlyphAtlas.keyFor(0x41, CellFlags.underline), 0x41 | (1 << 23));
      expect(
        GlyphAtlas.keyFor(
          0x41,
          CellFlags.bold | CellFlags.italic | CellFlags.underline,
        ),
        0x41 | (7 << 21),
      );
    });

    test('color-affecting flags do not change the key', () {
      expect(
        GlyphAtlas.keyFor(0x41, CellFlags.faint | CellFlags.inverse),
        GlyphAtlas.keyFor(0x41, 0),
      );
    });
  });

  group('GlyphAtlas device pixel ratio', () {
    test('non-positive dpr is clamped to 1.0', () {
      expect(_atlas(devicePixelRatio: 0).devicePixelRatio, 1.0);
      expect(_atlas(devicePixelRatio: -2).devicePixelRatio, 1.0);
    });

    test('higher dpr produces physically larger tiles', () {
      final atlas = _atlas(devicePixelRatio: 2);
      atlas.ensureAll([GlyphAtlas.keyFor(0x41, 0)]);
      // columns * ceil(cellWidth * dpr)
      expect(atlas.image!.width, 16 * 26);
      expect(atlas.image!.height, 16 * 32);
      atlas.disposeAndClear();
    });

    test('fractional dpr rounds tile size up to whole texels', () {
      final atlas = _atlas(
        devicePixelRatio: 1.5,
        cellSize: const Size(7, 11),
      );
      atlas.ensureAll([GlyphAtlas.keyFor(0x41, 0)]);
      // ceil(7 * 1.5) = 11, ceil(11 * 1.5) = 17
      expect(atlas.image!.width, 16 * 11);
      expect(atlas.image!.height, 16 * 17);
      atlas.disposeAndClear();
    });

    test('atlases built for different dprs have different geometry', () {
      final lo = _atlas(devicePixelRatio: 1);
      final hi = _atlas(devicePixelRatio: 2);
      lo.ensureAll([GlyphAtlas.keyFor(0x41, 0)]);
      hi.ensureAll([GlyphAtlas.keyFor(0x41, 0)]);
      expect(hi.image!.width, lo.image!.width * 2);
      lo.disposeAndClear();
      hi.disposeAndClear();
    });
  });

  group('GlyphAtlas non-ASCII tiles', () {
    test('codepoints >= 128 are stored on the map path', () {
      final atlas = _atlas();
      atlas.ensureAll([
        GlyphAtlas.keyFor(0x2588, 0), // █ full block
        GlyphAtlas.keyFor(0xE0B0, 0), //  powerline glyph
      ]);

      final block = atlas.tileIndex(0x2588, 0);
      final powerline = atlas.tileIndex(0xE0B0, 0);
      expect(block, greaterThanOrEqualTo(0));
      expect(powerline, greaterThanOrEqualTo(0));
      expect(block, isNot(powerline));
      expect(atlas.tileCount, 2);
      expect(atlas.image, isNotNull);
      atlas.disposeAndClear();
    });

    test('non-ASCII style variants get distinct tiles', () {
      final atlas = _atlas();
      atlas.ensureAll([
        GlyphAtlas.keyFor(0x2588, 0),
        GlyphAtlas.keyFor(0x2588, CellFlags.bold),
      ]);
      expect(atlas.tileIndex(0x2588, 0), isNot(atlas.tileIndex(0x2588, CellFlags.bold)));
      expect(atlas.tileCount, 2);
      atlas.disposeAndClear();
    });

    test('ASCII and non-ASCII tiles share the same grid', () {
      final atlas = _atlas();
      atlas.ensureAll([
        GlyphAtlas.keyFor(0x41, 0),
        GlyphAtlas.keyFor(0x2588, 0),
      ]);
      expect(atlas.tileIndex(0x41, 0), 0);
      expect(atlas.tileIndex(0x2588, 0), 1);
      atlas.disposeAndClear();
    });
  });

  group('GlyphAtlas edge cases', () {
    test('codepoint 0x7F uses the ASCII lookup path', () {
      final atlas = _atlas();
      atlas.ensureAll([GlyphAtlas.keyFor(0x7F, 0)]);
      expect(atlas.tileIndex(0x7F, 0), 0);
      expect(atlas.tileCount, 1);
      atlas.disposeAndClear();
    });

    test('duplicate keys in one ensureAll call are added once', () {
      final atlas = _atlas();
      final key = GlyphAtlas.keyFor(0x41, 0);
      atlas.ensureAll([key, key, key]);
      expect(atlas.tileCount, 1);
      atlas.disposeAndClear();
    });

    test('ensureAll with no missing keys does not build an image', () {
      final atlas = _atlas();
      atlas.ensureAll(const []);
      expect(atlas.image, isNull);
      expect(atlas.tileCount, 0);

      // Adding only already-known keys is also a no-op.
      atlas.ensureAll([GlyphAtlas.keyFor(0x41, 0)]);
      final image = atlas.image;
      atlas.ensureAll([GlyphAtlas.keyFor(0x41, 0)]);
      expect(atlas.image, same(image));
      atlas.disposeAndClear();
    });

    test('disposeAndClear is idempotent', () {
      final atlas = _atlas();
      atlas.ensureAll([GlyphAtlas.keyFor(0x41, 0)]);
      atlas.disposeAndClear();
      expect(atlas.image, isNull);
      expect(atlas.tileCount, 0);

      // A second dispose must neither throw nor corrupt state.
      atlas.disposeAndClear();
      expect(atlas.image, isNull);
      expect(atlas.tileCount, 0);

      // Disposing a never-used atlas is fine too.
      _atlas().disposeAndClear();
    });

    test('all eight style variants of one glyph coexist', () {
      final atlas = _atlas();
      const styleFlags = [
        0,
        CellFlags.bold,
        CellFlags.italic,
        CellFlags.underline,
        CellFlags.bold | CellFlags.italic,
        CellFlags.bold | CellFlags.underline,
        CellFlags.italic | CellFlags.underline,
        CellFlags.bold | CellFlags.italic | CellFlags.underline,
      ];
      atlas.ensureAll([
        for (final flags in styleFlags) GlyphAtlas.keyFor(0x41, flags),
      ]);

      final tiles = {
        for (final flags in styleFlags) atlas.tileIndex(0x41, flags),
      };
      expect(tiles, hasLength(8));
      expect(atlas.tileCount, 8);
      atlas.disposeAndClear();
    });

    test('capacity smaller than columns still builds a valid image', () {
      final atlas = _atlas(capacity: 4, columns: 16);
      atlas.ensureAll([
        GlyphAtlas.keyFor(0x41, 0),
        GlyphAtlas.keyFor(0x42, 0),
      ]);
      // rows = ceil(4 / 16) = 1 — image is wider than the used area.
      expect(atlas.image!.width, 16 * 13);
      expect(atlas.image!.height, 16);
      expect(atlas.isFull, isFalse);
      atlas.disposeAndClear();
    });

    test('capacity 1 serves exactly one glyph variant', () {
      final atlas = _atlas(capacity: 1, columns: 1);
      atlas.ensureAll([
        GlyphAtlas.keyFor(0x41, 0),
        GlyphAtlas.keyFor(0x42, 0),
      ]);
      expect(atlas.isFull, isTrue);
      expect(atlas.tileIndex(0x41, 0), 0);
      expect(atlas.tileIndex(0x42, 0), -1);

      // Disposal frees the single slot for reuse.
      atlas.disposeAndClear();
      expect(atlas.isFull, isFalse);
      atlas.ensureAll([GlyphAtlas.keyFor(0x42, 0)]);
      expect(atlas.tileIndex(0x42, 0), 0);
      expect(atlas.tileIndex(0x41, 0), -1);
      atlas.disposeAndClear();
    });

    test('mixed ASCII/non-ASCII overflow keeps both lookups at -1', () {
      final atlas = _atlas(capacity: 2, columns: 2);
      atlas.ensureAll([
        GlyphAtlas.keyFor(0x41, 0),
        GlyphAtlas.keyFor(0x2588, 0),
        GlyphAtlas.keyFor(0x42, 0), // ASCII overflow
        GlyphAtlas.keyFor(0x2591, 0), // non-ASCII overflow
      ]);
      expect(atlas.tileIndex(0x42, 0), -1);
      expect(atlas.tileIndex(0x2591, 0), -1);
      expect(atlas.tileCount, 2);
      atlas.disposeAndClear();
    });

    test('tile rects of later rows stay within the image', () {
      final atlas = _atlas(capacity: 256, columns: 16);
      // Add enough glyphs to reach the second grid row.
      atlas.ensureAll([
        for (var c = 0x21; c <= 0x31; c++) GlyphAtlas.keyFor(c, 0),
      ]);
      final tile = atlas.tileIndex(0x31, 0); // 17th glyph → row 1
      final o = tile * 4;
      expect(tile, 16);
      expect(atlas.tileRects[o + 1], greaterThan(0)); // top below row 0
      expect(atlas.tileRects[o + 3], lessThanOrEqualTo(atlas.image!.height));
      atlas.disposeAndClear();
    });
  });
}
