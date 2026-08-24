import 'dart:math' show min;
import 'dart:typed_data';

import 'package:yoxterm/src/core/buffer/cell_offset.dart';
import 'package:yoxterm/src/core/cell.dart';
import 'package:yoxterm/src/core/cursor.dart';
import 'package:yoxterm/src/utils/circular_buffer.dart';
import 'package:yoxterm/src/utils/unicode_v11.dart';

const _cellSize = 4;

const _cellForeground = 0;

const _cellBackground = 1;

const _cellAttributes = 2;

const _cellContent = 3;

class BufferLine with IndexedItem {
  BufferLine(
    this._length, {
    this.isWrapped = false,
  }) : _data = Uint32List(_calcCapacity(_length) * _cellSize);

  int _length;

  Uint32List _data;

  /// High-water mark (in cells) of the highest index ever written since the
  /// last [reset]. Invariant: cells at index >= [_occ] are always zero, so
  /// [reset] only needs to clear `[0, _occ)` instead of the whole backing
  /// store (which is allocated with spare capacity, e.g. 128 cells for an
  /// 80-column line).
  var _occ = 0;

  /// The current high-water mark of written cells. Exposed for tests.
  int get debugOccupiedCells => _occ;

  Uint32List get data => _data;

  var isWrapped = false;

  /// Monotonically increasing mutation counter, bumped by every method that
  /// changes cell data or recycles the line ([reset]). Consumers such as the
  /// painter's per-line replay cache compare versions to detect changes
  /// without diffing cell contents. Anchor moves do not bump it — anchors do
  /// not affect what the line paints.
  int version = 0;

  int get length => _length;

  final _anchors = <CellAnchor>[];

  List<CellAnchor> get anchors => _anchors;

  int getForeground(int index) {
    return _data[index * _cellSize + _cellForeground];
  }

  int getBackground(int index) {
    return _data[index * _cellSize + _cellBackground];
  }

  int getAttributes(int index) {
    return _data[index * _cellSize + _cellAttributes];
  }

  int getContent(int index) {
    return _data[index * _cellSize + _cellContent];
  }

  int getCodePoint(int index) {
    return _data[index * _cellSize + _cellContent] & CellContent.codepointMask;
  }

  int getWidth(int index) {
    return _data[index * _cellSize + _cellContent] >> CellContent.widthShift;
  }

  void getCellData(int index, CellData cellData) {
    final offset = index * _cellSize;
    cellData.foreground = _data[offset + _cellForeground];
    cellData.background = _data[offset + _cellBackground];
    cellData.flags = _data[offset + _cellAttributes];
    cellData.content = _data[offset + _cellContent];
  }

  CellData createCellData(int index) {
    final cellData = CellData.empty();
    final offset = index * _cellSize;
    _data[offset + _cellForeground] = cellData.foreground;
    _data[offset + _cellBackground] = cellData.background;
    _data[offset + _cellAttributes] = cellData.flags;
    _data[offset + _cellContent] = cellData.content;
    return cellData;
  }

  void setForeground(int index, int value) {
    _data[index * _cellSize + _cellForeground] = value;
    _touch(index);
    version++;
  }

  void setBackground(int index, int value) {
    _data[index * _cellSize + _cellBackground] = value;
    _touch(index);
    version++;
  }

  void setAttributes(int index, int value) {
    _data[index * _cellSize + _cellAttributes] = value;
    _touch(index);
    version++;
  }

  void setContent(int index, int value) {
    _data[index * _cellSize + _cellContent] = value;
    _touch(index);
    version++;
  }

  void setCodePoint(int index, int char) {
    final width = unicodeV11.wcwidth(char);
    setContent(index, char | (width << CellContent.widthShift));
  }

  void setCell(int index, int char, int witdh, CursorStyle style) {
    final offset = index * _cellSize;
    _data[offset + _cellForeground] = style.foreground;
    _data[offset + _cellBackground] = style.background;
    _data[offset + _cellAttributes] = style.attrs;
    _data[offset + _cellContent] = char | (witdh << CellContent.widthShift);
    _touch(index);
    version++;
  }

  void setCellData(int index, CellData cellData) {
    final offset = index * _cellSize;
    _data[offset + _cellForeground] = cellData.foreground;
    _data[offset + _cellBackground] = cellData.background;
    _data[offset + _cellAttributes] = cellData.flags;
    _data[offset + _cellContent] = cellData.content;
    _touch(index);
    version++;
  }

  /// Raises the high-water mark so [reset] clears cell [index] too.
  void _touch(int index) {
    if (index >= _occ) _occ = index + 1;
  }

  void eraseCell(int index, CursorStyle style) {
    _eraseCellRaw(index, style);
    version++;
  }

  /// Erases a cell without bumping [version]. Bulk operations erase their
  /// cells through this and bump [version] once for the whole operation.
  void _eraseCellRaw(int index, CursorStyle style) {
    final offset = index * _cellSize;
    _data[offset + _cellForeground] = style.foreground;
    _data[offset + _cellBackground] = style.background;
    _data[offset + _cellAttributes] = style.attrs;
    _data[offset + _cellContent] = 0;
    _touch(index);
  }

  void resetCell(int index) {
    final offset = index * _cellSize;
    _data[offset + _cellForeground] = 0;
    _data[offset + _cellBackground] = 0;
    _data[offset + _cellAttributes] = 0;
    _data[offset + _cellContent] = 0;
    _touch(index);
    version++;
  }

  /// Erase cells whose index satisfies [start] <= index < [end]. Erased cells
  /// are filled with [style].
  void eraseRange(int start, int end, CursorStyle style) {
    // reset cell one to the left if start is second cell of a wide char
    if (start > 0 && getWidth(start - 1) == 2) {
      _eraseCellRaw(start - 1, style);
    }

    // reset cell one to the right if end is second cell of a wide char
    if (end > 0 && end < _length && getWidth(end - 1) == 2) {
      _eraseCellRaw(end - 1, style);
    }

    end = min(end, _length);
    for (var i = start; i < end; i++) {
      _eraseCellRaw(i, style);
    }
    version++;
  }

  /// Remove [count] cells starting at [start]. Cells that are empty after the
  /// removal are filled with [style].
  void removeCells(int start, int count, [CursorStyle? style]) {
    assert(start >= 0 && start < _length);
    assert(count >= 0 && start + count <= _length);

    style ??= CursorStyle.empty;

    if (start + count < _length) {
      final moveStart = start * _cellSize;
      final moveEnd = (_length - count) * _cellSize;
      final moveOffset = count * _cellSize;
      _data.setRange(moveStart, moveEnd, _data, moveStart + moveOffset);
    }

    for (var i = _length - count; i < _length; i++) {
      _eraseCellRaw(i, style);
    }

    if (start > 0 && getWidth(start - 1) == 2) {
      _eraseCellRaw(start - 1, style);
    }

    // Update anchors, remove anchors that are inside the removed range.
    // Iterate backwards: disposing an anchor removes it from [_anchors].
    for (var i = _anchors.length - 1; i >= 0; i--) {
      final anchor = _anchors[i];
      if (anchor.x >= start) {
        if (anchor.x < start + count) {
          anchor.dispose();
        } else {
          anchor.reposition(anchor.x - count);
        }
      }
    }
    version++;
  }

  /// Inserts [count] cells at [start]. New cells are initialized with [style].
  void insertCells(int start, int count, [CursorStyle? style]) {
    style ??= CursorStyle.empty;

    if (start > 0 && getWidth(start - 1) == 2) {
      _eraseCellRaw(start - 1, style);
    }

    if (start + count < _length) {
      final moveStart = start * _cellSize;
      final moveEnd = (_length - count) * _cellSize;
      final moveOffset = count * _cellSize;
      _data.setRange(moveStart + moveOffset, moveEnd + moveOffset, _data, moveStart);
      // Content shifted right: the high-water mark moves with it.
      if (_occ > start) _occ = min(_occ + count, _length);
    }

    final end = min(start + count, _length);
    for (var i = start; i < end; i++) {
      _eraseCellRaw(i, style);
    }

    if (getWidth(_length - 1) == 2) {
      _eraseCellRaw(_length - 1, style);
    }

    // Update anchors, move anchors that are after the inserted range.
    // Iterate backwards: disposing an anchor removes it from [_anchors].
    for (var i = _anchors.length - 1; i >= 0; i--) {
      final anchor = _anchors[i];
      if (anchor.x >= start + count) {
        anchor.reposition(anchor.x + count);

        // Remove anchors that are now outside the buffer.
        if (anchor.x >= _length) {
          anchor.dispose();
        }
      }
    }
    version++;
  }

  void resize(int length) {
    assert(length >= 0);

    if (length == _length) {
      return;
    }

    if (length > _length) {
      final newBufferSize = _calcCapacity(length) * _cellSize;

      if (newBufferSize > _data.length) {
        final newBuffer = Uint32List(newBufferSize);
        newBuffer.setRange(0, _data.length, _data);
        _data = newBuffer;
      }
    }

    _length = length;
    version++;

    for (var i = 0; i < _anchors.length; i++) {
      final anchor = _anchors[i];
      if (anchor.x > _length) {
        anchor.reposition(_length);
      }
    }
  }

  /// Returns the offset of the last cell that has content from the start of
  /// the line.
  int getTrimmedLength([int? cols]) {
    final maxCols = _data.length ~/ _cellSize;

    if (cols == null || cols > maxCols) {
      cols = maxCols;
    }

    if (cols <= 0) {
      return 0;
    }

    for (var i = cols - 1; i >= 0; i--) {
      var codePoint = getCodePoint(i);

      if (codePoint != 0) {
        // we are at the last cell in this line that has content.
        // the length of this line is the index of this cell + 1
        // the only exception is that if that last cell is wider
        // than 1 then we have to add the diff
        final lastCellWidth = getWidth(i);
        return i + lastCellWidth;
      }
    }
    return 0;
  }

  /// Copies [len] cells from [src] starting at [srcCol] to [dstCol] at this
  /// line.
  void copyFrom(BufferLine src, int srcCol, int dstCol, int len) {
    resize(dstCol + len);

    _data.setRange(
      dstCol * _cellSize,
      (dstCol + len) * _cellSize,
      src.data,
      srcCol * _cellSize,
    );
    if (dstCol + len > _occ) _occ = dstCol + len;
    version++;
  }

  static int _calcCapacity(int length) {
    assert(length >= 0);

    var capacity = 64;

    if (length < 256) {
      while (capacity < length) {
        capacity *= 2;
      }
    } else {
      capacity = 256;
      while (capacity < length) {
        capacity += 32;
      }
    }

    return capacity;
  }

  String getText([int? from, int? to]) {
    if (from == null || from < 0) {
      from = 0;
    }

    if (to == null || to > _length) {
      to = _length;
    }

    final builder = StringBuffer();
    for (var i = from; i < to; i++) {
      final codePoint = getCodePoint(i);
      final width = getWidth(i);
      if (codePoint != 0 && i + width <= to) {
        builder.writeCharCode(codePoint);
      }
    }

    return builder.toString();
  }

  CellAnchor createAnchor(int offset) {
    final anchor = CellAnchor(offset, owner: this);
    _anchors.add(anchor);
    return anchor;
  }

  /// Erases all cells and resets per-line state ([isWrapped], anchors) so the
  /// line can be reused as a fresh empty line. Used to recycle scrolled-out
  /// lines instead of allocating a new [BufferLine] per scrolled line.
  ///
  /// Only cells below the [_occ] high-water mark are cleared: cells at or
  /// beyond it were never written since the last reset and are known to be
  /// zero already, so a short line does not pay for clearing the whole
  /// (capacity-sized) backing store.
  void reset() {
    if (_occ > 0) {
      _data.fillRange(0, _occ * _cellSize, 0);
      _occ = 0;
    }
    isWrapped = false;
    version++;
    // Detach anchors that still point at this line (e.g. selection ends) so
    // they don't silently follow the line into its new position. Iterate
    // backwards: disposing an anchor removes it from [_anchors].
    for (var i = _anchors.length - 1; i >= 0; i--) {
      _anchors[i].dispose();
    }
  }

  void dispose() {
    // Iterate backwards: disposing an anchor removes it from [_anchors].
    for (var i = _anchors.length - 1; i >= 0; i--) {
      _anchors[i].dispose();
    }
  }

  @override
  String toString() {
    return getText();
  }
}

/// A handle to a cell in a [BufferLine] that can be used to track the location
/// of the cell. Anchors are guaranteed to be stable, retaining their relative
/// position to each other after mutations to the buffer.
class CellAnchor {
  CellAnchor(int offset, {BufferLine? owner})
      : _offset = offset,
        _owner = owner;

  int _offset;

  int get x {
    return _offset;
  }

  int get y {
    assert(attached);
    return _owner!.index;
  }

  CellOffset get offset {
    assert(attached);
    return CellOffset(_offset, _owner!.index);
  }

  BufferLine? _owner;

  BufferLine? get line => _owner;

  bool get attached => _owner?.attached ?? false;

  void reparent(BufferLine owner, int offset) {
    _owner?._anchors.remove(this);
    _owner = owner;
    _owner?._anchors.add(this);
    _offset = offset;
  }

  void reposition(int offset) {
    _offset = offset;
  }

  void dispose() {
    _owner?._anchors.remove(this);
    _owner = null;
  }

  @override
  String toString() {
    if (attached) {
      return 'CellAnchor($x, $y)';
    } else {
      return 'CellAnchor($x, detached)';
    }
  }
}
