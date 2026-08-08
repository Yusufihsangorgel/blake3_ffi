import 'dart:convert';
import 'dart:typed_data';

import 'package:blake3_ffi/blake3_ffi.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

/// A stand-in for the reason this view exists: code that takes a [Hash] and
/// does not care which one.
Digest checksum(List<int> bytes, {Hash algorithm = sha256}) =>
    algorithm.convert(bytes);

void main() {
  final data = Uint8List.fromList(utf8.encode('the quick brown fox' * 97));

  group('blake3Hash as a crypto Hash', () {
    test('agrees with the direct blake3 call', () {
      // The whole point: two ways in, one answer out. If these ever diverge,
      // the Hash view is quietly a different algorithm.
      expect(blake3Hash.convert(data).bytes, equals(blake3(data)));
    });

    test('chunked conversion matches the one-shot digest', () {
      // convert() is overridden to skip the sink, so the two paths are
      // genuinely separate code and have to be pinned against each other.
      final collected = <Digest>[];
      final sink = blake3Hash.startChunkedConversion(
        ChunkedConversionSink.withCallback((digests) {
          collected.addAll(digests);
        }),
      );
      for (var offset = 0; offset < data.length; offset += 64) {
        final end = (offset + 64).clamp(0, data.length);
        sink.add(data.sublist(offset, end));
      }
      sink.close();

      expect(collected, hasLength(1));
      expect(collected.single.bytes, equals(blake3(data)));
    });

    test('addSlice with isLast closes and emits', () {
      final collected = <Digest>[];
      final sink = blake3Hash.startChunkedConversion(
        ChunkedConversionSink.withCallback(collected.addAll),
      );
      sink.addSlice(data, 0, data.length, true);

      expect(collected.single.bytes, equals(blake3(data)));
    });

    test('drops into an API that takes a Hash', () {
      expect(checksum(data, algorithm: blake3Hash).bytes, equals(blake3(data)));
      // And the default still works, so the swap is opt-in.
      expect(checksum(data).bytes, isNot(equals(blake3(data))));
    });

    test('produces a 32-byte digest, like sha256', () {
      expect(blake3Hash.convert(data).bytes, hasLength(32));
      expect(blake3Hash.blockSize, equals(sha256.blockSize));
    });

    test('the empty input hashes without special casing', () {
      expect(
        blake3Hash.convert(const <int>[]).bytes,
        equals(blake3(Uint8List(0))),
      );
    });

    test('accepts a plain List<int>, not only Uint8List', () {
      final plain = <int>[1, 2, 3, 250, 251, 252];
      expect(
        blake3Hash.convert(plain).bytes,
        equals(blake3(Uint8List.fromList(plain))),
      );
    });

    test('closing twice does not touch the freed hasher', () {
      // A converter is allowed to close a sink more than once. The native
      // hasher is released on the first close, so a second must be inert
      // rather than a use after free.
      final collected = <Digest>[];
      final sink = blake3Hash.startChunkedConversion(
        ChunkedConversionSink.withCallback(collected.addAll),
      );
      sink.add(data);
      sink.close();
      expect(sink.close, returnsNormally);
      expect(collected, hasLength(1));
    });

    test('adding after close throws rather than being ignored', () {
      final sink = blake3Hash.startChunkedConversion(
        ChunkedConversionSink.withCallback((_) {}),
      );
      sink.close();
      expect(() => sink.add(data), throwsStateError);
    });
  });
}
