import 'dart:collection';

class ByteConsumer {
  final _queue = ListQueue<List<int>>();

  final _consumed = ListQueue<List<int>>();

  var _currentOffset = 0;

  var _length = 0;

  var _totalConsumed = 0;

  /// A lone high surrogate that ended a previous chunk. It is prepended to
  /// the next chunk so that a surrogate pair split across two [add] calls is
  /// still recombined.
  int? _pendingHighSurrogate;

  void add(String data) {
    if (data.isEmpty) return;
    var units = data.codeUnits;
    final pending = _pendingHighSurrogate;
    if (pending != null) {
      _pendingHighSurrogate = null;
      units = [pending, ...units];
    }
    var hasSurrogate = false;
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit >= 0xD800 && unit <= 0xDFFF) {
        hasSurrogate = true;
        break;
      }
    }
    if (!hasSurrogate) {
      _queue.addLast(units);
      _length += units.length;
      return;
    }
    // Combine UTF-16 surrogate pairs into single Unicode code points.
    final runes = <int>[];
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (i + 1 < units.length) {
          final low = units[i + 1];
          if (low >= 0xDC00 && low <= 0xDFFF) {
            runes.add(0x10000 + ((unit & 0x3FF) << 10) + (low & 0x3FF));
            i++;
            continue;
          }
        } else {
          // A trailing lone high surrogate may be the first half of a pair
          // that is completed by the next chunk. Hold it back.
          _pendingHighSurrogate = unit;
          continue;
        }
      }
      runes.add(unit);
    }
    if (runes.isEmpty) return;
    _queue.addLast(runes);
    _length += runes.length;
  }

  int peek() {
    final data = _queue.first;
    if (_currentOffset < data.length) {
      return data[_currentOffset];
    } else {
      final result = consume();
      rollback();
      return result;
    }
  }

  int consume() {
    final data = _queue.first;

    if (_currentOffset >= data.length) {
      _consumed.add(_queue.removeFirst());
      _currentOffset -= data.length;
      return consume();
    }

    _length--;
    _totalConsumed++;
    return data[_currentOffset++];
  }

  /// Rolls back the last [n] call.
  void rollback([int n = 1]) {
    _currentOffset -= n;
    _totalConsumed -= n;
    _length += n;
    while (_currentOffset < 0) {
      final rollback = _consumed.removeLast();
      _queue.addFirst(rollback);
      _currentOffset += rollback.length;
    }
  }

  /// Rolls back to the state when this consumer had [length] bytes.
  void rollbackTo(int length) {
    rollback(length - _length);
  }

  int get length => _length;

  int get totalConsumed => _totalConsumed;

  bool get isEmpty => _length == 0;

  bool get isNotEmpty => _length != 0;

  /// Unreferences data blocks that have been consumed. After calling this
  /// method, the consumer will not be able to roll back to consumed blocks.
  void unrefConsumedBlocks() {
    _consumed.clear();
  }

  /// Resets the consumer to its initial state.
  void reset() {
    _queue.clear();
    _consumed.clear();
    _currentOffset = 0;
    _totalConsumed = 0;
    _length = 0;
    _pendingHighSurrogate = null;
  }
}

// void main() {
//   final consumer = ByteConsumer();
//   consumer.add(Uint8List.fromList([1, 2, 3]));
//   consumer.add(Uint8List.fromList([4, 5, 6]));

//   while (consumer.isNotEmpty) {
//     print(consumer.consume());
//   }

//   consumer.rollback(5);

//   while (consumer.isNotEmpty) {
//     print(consumer.consume());
//   }

//   consumer.rollbackTo(3);

//   while (consumer.isNotEmpty) {
//     print(consumer.consume());
//   }
// }
