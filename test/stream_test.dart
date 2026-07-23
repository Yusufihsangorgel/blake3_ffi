import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:blake3_ffi/blake3_ffi.dart';
import 'package:test/test.dart';

Uint8List sample(int n) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) (i * 31 + 7) % 256]);

Stream<List<int>> chunked(Uint8List data, int chunkSize) async* {
  for (var i = 0; i < data.length; i += chunkSize) {
    yield data.sublist(i, math.min(i + chunkSize, data.length));
  }
}

void main() {
  test('blake3Stream matches blake3 over the whole input', () async {
    final data = sample(100000);
    final streamed = await blake3Stream(chunked(data, 4096));
    // Feeding the bytes in chunks must give the same digest as hashing them in
    // one call.
    expect(streamed, blake3(data));
  });

  test('the digest is independent of chunk boundaries', () async {
    final data = sample(50000);
    final expected = blake3(data);
    for (final size in [1, 7, 1024, 50000]) {
      expect(
        await blake3Stream(chunked(data, size)),
        expected,
        reason: 'chunk size $size',
      );
    }
  });

  test('blake3StreamHex matches blake3Hex', () async {
    final data = sample(20000);
    expect(await blake3StreamHex(chunked(data, 333)), blake3Hex(data));
  });

  test(
    'deprecated blake3HexStream still forwards to blake3StreamHex',
    () async {
      final data = sample(20000);
      // ignore: deprecated_member_use_from_same_package
      expect(await blake3HexStream(chunked(data, 333)), blake3Hex(data));
    },
  );

  test('hashing a file stream matches hashing its bytes', () async {
    final dir = Directory.systemTemp.createTempSync('blake3_stream_test');
    try {
      final file = File('${dir.path}/data.bin');
      final data = sample(80000);
      file.writeAsBytesSync(data);
      // The whole point: hash a file without reading it all into memory.
      expect(await blake3Stream(file.openRead()), blake3(data));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('an empty stream hashes to the empty-input digest', () async {
    expect(await blake3Stream(const Stream.empty()), blake3(Uint8List(0)));
  });

  test('the extendable output length carries through the stream', () async {
    final data = sample(10000);
    expect(
      await blake3Stream(chunked(data, 512), outputLength: 64),
      blake3(data, outputLength: 64),
    );
  });
}
