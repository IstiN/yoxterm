import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:xterm/zmodem.dart';
import 'package:zmodem/zmodem.dart' hide ZModemFileInfo;

/// Wires a [ZModemMux] to in-memory streams and records everything the mux
/// writes to the underlying channel and to the terminal.
class MuxHarness {
  final stdinController = StreamController<List<int>>();

  final stdoutController = StreamController<Uint8List>();

  final stdinChunks = <List<int>>[];

  final terminalOutput = StringBuffer();

  late final ZModemMux mux;

  MuxHarness() {
    // Construct eagerly so the mux is subscribed to [stdoutController] even
    // in tests that never call methods on it directly.
    mux = ZModemMux(
      stdin: stdinController.sink,
      stdout: stdoutController.stream,
    );
  }

  int _stdinCursor = 0;

  void collectStdin() {
    stdinController.stream.listen(stdinChunks.add);
  }

  /// Returns and consumes the bytes the mux wrote to stdin since the last
  /// call.
  Uint8List drainStdin() {
    final builder = BytesBuilder();
    for (var i = _stdinCursor; i < stdinChunks.length; i++) {
      builder.add(stdinChunks[i]);
    }
    _stdinCursor = stdinChunks.length;
    return builder.toBytes();
  }

  /// Lets pending microtasks and async stream events settle.
  Future<void> pump([int turns = 20]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

/// Rewrites hex-header trailers produced by the zmodem package's own
/// encoder (`CR LF XON`) into the form its parser (like lrzsz) expects
/// (`CR LF|0x80 XON`).
///
/// The plain `CR LF XON` byte sequence cannot occur inside binary packets
/// because control bytes are ZDLE-escaped there, so the rewrite is safe.
Uint8List lrzszStyle(Uint8List data) {
  final out = <int>[];
  for (var i = 0; i < data.length; i++) {
    if (i + 2 < data.length &&
        data[i] == 0x0d &&
        data[i + 1] == 0x0a &&
        data[i + 2] == 0x11) {
      out.addAll(const [0x0d, 0x8a, 0x11]);
      i += 2;
    } else {
      out.add(data[i]);
    }
  }
  return Uint8List.fromList(out);
}

void main() {
  group('ListExtension.dump()', () {
    test('renders bytes as zero-padded hex', () {
      expect([0x00, 0x0a, 0xff, 0x18].dump(), '00 0a ff 18');
      expect(<int>[].dump(), '');
    });
  });

  group('ListExtension.listIndexOf()', () {
    test('finds a pattern inside the list', () {
      expect([1, 2, 3, 4, 5].listIndexOf([2, 3]), 1);
    });

    test('finds a pattern at the start', () {
      expect([1, 2, 3].listIndexOf([1, 2]), 0);
    });

    test('returns null when the pattern is absent', () {
      expect([1, 2, 3].listIndexOf([4]), isNull);
      expect([1, 2, 3].listIndexOf([1, 2, 3, 4]), isNull);
    });

    test('honors the start offset', () {
      expect([1, 2, 9, 1, 2, 3].listIndexOf([1, 2], 1), 3);
    });

    test('rejects partial matches at candidate positions', () {
      expect([1, 2, 9, 1, 2].listIndexOf([1, 2, 3]), isNull);
    });

    test('a pattern starting at the last possible position is missed', () {
      // Documents a pre-existing off-by-one: the scan loop uses
      // `i < length - other.length` instead of `<=`, so a pattern that
      // ends exactly at the end of the list is never found.
      expect([9, 1, 2].listIndexOf([1, 2]), isNull);
      expect([1, 2].listIndexOf([1, 2]), isNull);
    });
  });

  group('ZModemCallbackOffer', () {
    test('accept() delegates to onAccept with the offset', () {
      int? acceptedOffset;
      final offer = ZModemCallbackOffer(
        ZModemFileInfo(pathname: 'a.txt'),
        onAccept: (offset) {
          acceptedOffset = offset;
          return const Stream<Uint8List>.empty();
        },
      );

      expect(offer.info.pathname, 'a.txt');
      offer.accept(42);
      expect(acceptedOffset, 42);
    });

    test('skip() calls onSkip when provided', () {
      var skipped = false;
      final offer = ZModemCallbackOffer(
        ZModemFileInfo(pathname: 'a.txt'),
        onAccept: (_) => const Stream<Uint8List>.empty(),
        onSkip: () => skipped = true,
      );

      offer.skip();
      expect(skipped, isTrue);
    });

    test('skip() without onSkip does not throw', () {
      final offer = ZModemCallbackOffer(
        ZModemFileInfo(pathname: 'a.txt'),
        onAccept: (_) => const Stream<Uint8List>.empty(),
      );

      expect(offer.skip, returnsNormally);
    });
  });

  group('ZModemMux: terminal passthrough', () {
    test('plain output is forwarded to the terminal as UTF-8', () async {
      final h = MuxHarness()..collectStdin();
      h.mux.onTerminalInput = h.terminalOutput.write;

      h.stdoutController.add(Uint8List.fromList('hello \xe2\x9c\x93'.codeUnits));
      await h.pump();

      expect(h.terminalOutput.toString(), 'hello ✓');
    });

    test('terminalWrite() forwards input when no session is active', () async {
      final h = MuxHarness()..collectStdin();

      h.mux.terminalWrite('ls\n');
      await h.pump();

      expect(utf8.decode(h.drainStdin()), 'ls\n');
    });
  });

  group('ZModemMux: receiving a file (remote is sz)', () {
    test('full receive handshake with an accepted file', () async {
      final h = MuxHarness()..collectStdin();
      final remote = ZModemCore();

      final offers = <ZModemOffer>[];
      h.mux.onFileOffer = offers.add;

      // The remote sender initiates the session. Terminal output that
      // precedes the init sequence must still reach the terminal.
      h.mux.onTerminalInput = h.terminalOutput.write;
      remote.initiateSend();
      h.stdoutController.add(Uint8List.fromList([
        ...'prompt\$ '.codeUnits,
        ...lrzszStyle(remote.dataToSend()),
      ]));
      await h.pump();

      expect(h.terminalOutput.toString(), 'prompt\$ ');

      // The mux answered ZRQINIT with ZRINIT.
      final initResponse = h.drainStdin();
      expect(initResponse, isNotEmpty);
      final initEvents = remote.receive(lrzszStyle(initResponse)).toList();
      expect(initEvents.whereType<ZReadyToSendEvent>(), hasLength(1));

      // Plain text that arrives while a session is active is forwarded to
      // the terminal (the session's onPlainText hook).
      h.stdoutController.add(Uint8List.fromList('sz: busy\r\n'.codeUnits));
      await h.pump();

      // The remote offers a file.
      remote.offerFile(ZModemFileInfo(pathname: 'hello.txt', length: 5));
      h.stdoutController.add(lrzszStyle(remote.dataToSend()));
      await h.pump();

      expect(offers, hasLength(1));
      expect(offers.single.info.pathname, 'hello.txt');
      expect(offers.single.info.length, 5);

      // The parser keeps up to 3 trailing bytes buffered to detect frame
      // prefixes; they are flushed once the next chunk arrives.
      expect(h.terminalOutput.toString(), 'prompt\$ sz: busy\r\n');

      // Accept the offer: the mux must send ZRPOS and open a data stream.
      final received = <int>[];
      final receiveDone = Completer<void>();
      final subscription = offers.single.accept(0).listen(
            received.addAll,
            onDone: receiveDone.complete,
          );
      // Exercise the flow-control hooks of the receive sink.
      subscription.pause();
      subscription.resume();
      await h.pump();

      final acceptedEvents = remote.receive(lrzszStyle(h.drainStdin())).toList();
      expect(acceptedEvents.whereType<ZFileAcceptedEvent>().single.offset, 0);

      // The remote sends the file content and finishes.
      remote.sendFileData(Uint8List.fromList('hello'.codeUnits));
      remote.finishSending(5);
      h.stdoutController.add(lrzszStyle(remote.dataToSend()));
      await h.pump();
      await receiveDone.future;

      expect(utf8.decode(received), 'hello');

      // While the session is active, terminalWrite() is suppressed.
      final chunksBefore = h.stdinChunks.length;
      h.mux.terminalWrite('ignored');
      await h.pump();
      expect(h.stdinChunks, hasLength(chunksBefore));

      // The remote closes the session; the mux must reset afterwards.
      remote.finishSession();
      h.stdoutController.add(lrzszStyle(remote.dataToSend()));
      await h.pump();

      h.mux.terminalWrite('works again');
      await h.pump();
      expect(utf8.decode(h.stdinChunks.last), 'works again');
    });

    test('a file offer is auto-skipped when no onFileOffer is set', () async {
      final h = MuxHarness()..collectStdin();
      final remote = ZModemCore();

      remote.initiateSend();
      h.stdoutController.add(lrzszStyle(remote.dataToSend()));
      await h.pump();
      remote.receive(lrzszStyle(h.drainStdin())).toList();

      remote.offerFile(ZModemFileInfo(pathname: 'unwanted.bin', length: 1));
      h.stdoutController.add(lrzszStyle(remote.dataToSend()));
      await h.pump();

      // The mux must have answered with ZSKIP.
      final events = remote.receive(lrzszStyle(h.drainStdin())).toList();
      expect(events.whereType<ZFileSkippedEvent>(), hasLength(1));
    });

    test('skipping an offer through ZModemOffer.skip() sends ZSKIP', () async {
      final h = MuxHarness()..collectStdin();
      final remote = ZModemCore();

      final offers = <ZModemOffer>[];
      h.mux.onFileOffer = offers.add;

      remote.initiateSend();
      h.stdoutController.add(lrzszStyle(remote.dataToSend()));
      await h.pump();
      remote.receive(lrzszStyle(h.drainStdin())).toList();

      remote.offerFile(ZModemFileInfo(pathname: 'skip.me', length: 1));
      h.stdoutController.add(lrzszStyle(remote.dataToSend()));
      await h.pump();

      expect(offers, hasLength(1));
      offers.single.skip();
      await h.pump();

      final events = remote.receive(lrzszStyle(h.drainStdin())).toList();
      expect(events.whereType<ZFileSkippedEvent>(), hasLength(1));
    });
  });

  group('ZModemMux: sending a file (remote is rz)', () {
    test('full send handshake', () async {
      final h = MuxHarness()..collectStdin();
      final remote = ZModemCore()..initiateReceive();

      final fileBytes = Uint8List.fromList('data'.codeUnits);
      var requests = 0;
      var skipped = false;
      h.mux.onFileRequest = () async {
        requests++;
        if (requests > 1) {
          return const <ZModemOffer>[];
        }
        return [
          ZModemCallbackOffer(
            ZModemFileInfo(pathname: 'out.bin', length: fileBytes.length),
            onAccept: (_) => Stream.value(fileBytes),
            onSkip: () => skipped = true,
          ),
        ];
      };

      // The remote receiver announces itself with ZRINIT.
      h.stdoutController.add(lrzszStyle(remote.dataToSend()));
      await h.pump();
      expect(requests, 1);

      // The mux offered the file; the remote sees the proposal.
      final offerEvents = remote.receive(lrzszStyle(h.drainStdin())).toList();
      final offered =
          offerEvents.whereType<ZFileOfferedEvent>().single.fileInfo;
      expect(offered.pathname, 'out.bin');
      expect(offered.length, fileBytes.length);

      // The remote accepts from offset 0; the mux streams the content.
      remote.acceptFile(0);
      h.stdoutController.add(lrzszStyle(remote.dataToSend()));
      await h.pump(40);

      final dataEvents = remote.receive(lrzszStyle(h.drainStdin())).toList();
      final data = dataEvents
          .whereType<ZFileDataEvent>()
          .expand((event) => event.data)
          .toList();
      expect(utf8.decode(data), 'data');
      expect(dataEvents.whereType<ZFileEndEvent>(), hasLength(1));
      expect(skipped, isFalse);

      // The remote asks for the next file. The offers iterator is cached
      // for the whole session (`_fileOffers ??=`), so onFileRequest is not
      // invoked again; the exhausted iterator makes the mux close the
      // session with ZFIN.
      h.stdoutController.add(lrzszStyle(remote.dataToSend()));
      await h.pump();
      expect(requests, 1);

      // The remote receives ZFIN and acknowledges it.
      final finEvents = remote.receive(lrzszStyle(h.drainStdin())).toList();
      expect(finEvents.whereType<ZSessionFinishedEvent>(), hasLength(1));

      // The mux receives the ZFIN acknowledgment and resets.
      h.stdoutController.add(lrzszStyle(remote.dataToSend()));
      await h.pump();

      h.mux.terminalWrite('after');
      await h.pump();
      expect(utf8.decode(h.stdinChunks.last), 'after');
    });

    test('a skipped offer advances to the next offer', () async {
      final h = MuxHarness()..collectStdin();
      final remote = ZModemCore()..initiateReceive();

      final skippedNames = <String>[];
      h.mux.onFileRequest = () async => [
            ZModemCallbackOffer(
              ZModemFileInfo(pathname: 'first.bin', length: 1),
              onAccept: (_) => const Stream<Uint8List>.empty(),
              onSkip: () => skippedNames.add('first.bin'),
            ),
            ZModemCallbackOffer(
              ZModemFileInfo(pathname: 'second.bin', length: 1),
              onAccept: (_) => const Stream<Uint8List>.empty(),
              onSkip: () => skippedNames.add('second.bin'),
            ),
          ];

      h.stdoutController.add(lrzszStyle(remote.dataToSend()));
      await h.pump();

      // First file offered.
      var events = remote.receive(lrzszStyle(h.drainStdin())).toList();
      expect(events.whereType<ZFileOfferedEvent>().single.fileInfo.pathname,
          'first.bin');

      // Remote skips it; the mux must offer the second file.
      remote.skipFile();
      h.stdoutController.add(lrzszStyle(remote.dataToSend()));
      await h.pump();

      expect(skippedNames, ['first.bin']);

      events = remote.receive(lrzszStyle(h.drainStdin())).toList();
      expect(events.whereType<ZFileOfferedEvent>().single.fileInfo.pathname,
          'second.bin');
    });
  });
}
