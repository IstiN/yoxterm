import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:yoxterm/core.dart';

void main() {
  BenchmarkWrite().run();
  BenchmarkWrite2().run();
  BenchmarkWriteBuffer().run();
  BenchmarkWriteCMatrix().run();
  BenchmarkWriteLines().run();
  BenchmarkWriteLinesBytes().run();
  BenchmarkWriteCMatrixBytes().run();
}

abstract class Benchmark {
  String explain();

  void benchmark();

  void run() {
    print('benchmark: ${explain()}');
    print('preheating...');
    benchmark();
    final sw = Stopwatch()..start();
    print('running...');
    benchmark();
    sw.stop();
    print('result: ${sw.elapsedMilliseconds} ms');
  }
}

class BenchmarkWrite extends Benchmark {
  static const cycle = 1 << 20;
  static const data = 'hello world';

  @override
  String explain() {
    return "write '$data' to Terminal for $cycle times";
  }

  @override
  void benchmark() {
    final terminal = Terminal(maxLines: 40000);
    for (var i = 0; i < cycle; i++) {
      terminal.write(data);
    }
  }
}

class BenchmarkWrite2 extends Benchmark {
  static const cycle = 100000;
  static const data = '100000';

  @override
  String explain() {
    return "write '$data' to Terminal for $cycle times";
  }

  @override
  void benchmark() {
    final terminal = Terminal(maxLines: 40000);
    for (var i = 0; i < cycle; i++) {
      terminal.write(data);
    }
  }
}

class BenchmarkWriteCMatrix extends Benchmark {
  BenchmarkWriteCMatrix() {
    data = File('script/cmatrix.txt').readAsStringSync();
  }

  static const cycle = 12;
  late final String data;

  @override
  String explain() {
    return 'write ${data.length / 1024} kb CMatrix -r output to Terminal for $cycle time(s)';
  }

  @override
  void benchmark() {
    final terminal = Terminal(maxLines: 40000);
    for (var i = 0; i < cycle; i++) {
      terminal.write(data);
    }
  }
}

class BenchmarkWriteLines extends Benchmark {
  BenchmarkWriteLines() {
    data = File('script/lines.txt').readAsStringSync();
  }

  static const cycle = 10;
  late final String data;

  @override
  String explain() {
    return 'write ${data.length / 1024} kb `find .` output to Terminal for $cycle time(s)';
  }

  @override
  void benchmark() {
    final terminal = Terminal(maxLines: 40000);
    for (var i = 0; i < cycle; i++) {
      terminal.write(data);
    }
  }
}

class BenchmarkWriteBuffer extends Benchmark {
  static const cycle = 1 << 20;
  static const data = 'hello world';

  @override
  String explain() {
    return "write '$data' to StringBuffer for $cycle times";
  }

  @override
  void benchmark() {
    final buffer = StringBuffer();
    for (var i = 0; i < cycle; i++) {
      buffer.write(data);
    }
  }
}

/// Base for the byte-path benchmarks: compares the old PTY input path
/// (per-chunk `utf8.decode` + [Terminal.write]) against the new
/// [Terminal.writeBytes] on the same payload, fed in PTY-shaped 64 KiB
/// chunks.
abstract class BenchmarkBytes extends Benchmark {
  late final Uint8List data;

  int get cycle;

  @override
  String explain() {
    return 'write ${data.length / 1024} kb as 64 KiB byte chunks for $cycle time(s): decode+write vs writeBytes';
  }

  @override
  void benchmark() {
    const chunkSize = 64 * 1024;
    const attempts = 3;

    // Old path: decode each chunk to a String, then Terminal.write.
    var best = 1 << 62;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final terminal = Terminal(maxLines: 40000);
      final sw = Stopwatch()..start();
      for (var i = 0; i < cycle; i++) {
        for (var offset = 0; offset < data.length; offset += chunkSize) {
          final end = offset + chunkSize > data.length
              ? data.length
              : offset + chunkSize;
          terminal.write(
            utf8.decode(Uint8List.sublistView(data, offset, end),
                allowMalformed: true),
          );
        }
      }
      sw.stop();
      if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
    }
    print('  utf8.decode + write: $best ms (min of $attempts)');

    // New path: Terminal.writeBytes decodes incrementally, no String.
    best = 1 << 62;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final terminal = Terminal(maxLines: 40000);
      final sw = Stopwatch()..start();
      for (var i = 0; i < cycle; i++) {
        for (var offset = 0; offset < data.length; offset += chunkSize) {
          final end = offset + chunkSize > data.length
              ? data.length
              : offset + chunkSize;
          terminal.writeBytes(Uint8List.sublistView(data, offset, end));
        }
      }
      sw.stop();
      if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
    }
    print('  writeBytes:            $best ms (min of $attempts)');
  }
}

class BenchmarkWriteLinesBytes extends BenchmarkBytes {
  BenchmarkWriteLinesBytes() {
    data = File('script/lines.txt').readAsBytesSync();
  }

  @override
  int get cycle => 10;
}

class BenchmarkWriteCMatrixBytes extends BenchmarkBytes {
  BenchmarkWriteCMatrixBytes() {
    data = File('script/cmatrix.txt').readAsBytesSync();
  }

  @override
  int get cycle => 12;
}
