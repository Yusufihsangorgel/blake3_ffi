import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'functions.dart';
import 'hasher.dart';

/// BLAKE3 as a `package:crypto` [Hash].
///
/// The package's own [blake3] and [Blake3Hasher] are the direct way to hash
/// bytes here. This exists for the other case: code that already takes a
/// [Hash] — a checksum helper, a content-addressed cache, an HMAC-style
/// wrapper, anything with a `Hash algorithm` parameter — can be handed
/// [blake3Hash] without changing shape.
///
/// ```dart
/// import 'package:blake3_ffi/blake3_ffi.dart';
/// import 'package:crypto/crypto.dart';
///
/// Digest checksum(List<int> bytes, {Hash with_ = sha256}) =>
///     with_.convert(bytes);
///
/// checksum(bytes, with_: blake3Hash); // same call, different algorithm
/// ```
///
/// [Digest] holds 32 bytes, which is BLAKE3's default output. The longer
/// outputs BLAKE3 can produce have nowhere to go in a [Digest], so use
/// [blake3] directly with `outputLength` for those.
final class Blake3Hash extends Hash {
  /// Creates the [Hash] view. Prefer the [blake3Hash] instance.
  const Blake3Hash();

  /// BLAKE3 compresses 64-byte blocks, the same as SHA-256.
  ///
  /// `package:crypto` reads this when it needs to pad or chunk to the
  /// algorithm's block, most visibly in `Hmac`.
  @override
  int get blockSize => 64;

  /// Hashes [input] in one call.
  ///
  /// Overridden rather than inherited: the inherited version routes through
  /// [startChunkedConversion], and the one-shot native call skips both the
  /// sink and the intermediate copy.
  @override
  Digest convert(List<int> input) =>
      Digest(blake3(input is Uint8List ? input : Uint8List.fromList(input)));

  @override
  ByteConversionSink startChunkedConversion(Sink<Digest> sink) =>
      _Blake3Sink(sink);
}

/// BLAKE3 as a `package:crypto` [Hash], for APIs that take one.
const Hash blake3Hash = Blake3Hash();

/// Feeds a [Blake3Hasher] from a chunked conversion and emits the digest once.
class _Blake3Sink extends ByteConversionSink {
  _Blake3Sink(this._sink);

  final Sink<Digest> _sink;
  final Blake3Hasher _hasher = Blake3Hasher();
  bool _closed = false;

  @override
  void add(List<int> chunk) {
    if (_closed) {
      throw StateError('cannot add to a closed sink');
    }
    _hasher.update(chunk);
  }

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    add(chunk.sublist(start, end));
    if (isLast) close();
  }

  @override
  void close() {
    // A converter may close a sink more than once, and the native hasher is
    // freed here, so the second call has to be a no-op rather than a use
    // after free.
    if (_closed) return;
    _closed = true;
    _sink
      ..add(Digest(_hasher.finalize()))
      ..close();
    _hasher.dispose();
  }
}
