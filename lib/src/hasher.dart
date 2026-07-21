import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'bindings.dart';
import 'hex.dart';

/// The length in bytes of a BLAKE3 key (keyed mode).
const int blake3KeyLength = 32;

/// The default digest length in bytes.
const int blake3OutLength = 32;

/// An incremental BLAKE3 hasher.
///
/// Feed data with [update] (any number of times), then read a digest with
/// [finalize]. Finalizing does not consume the hasher: you may keep
/// updating and finalize again, and you may request any output length
/// (BLAKE3 is an extendable-output function).
///
/// ```dart
/// final hasher = Blake3Hasher();
/// try {
///   hasher.update(firstChunk);
///   hasher.update(secondChunk);
///   final digest = hasher.finalize();
/// } finally {
///   hasher.dispose();
/// }
/// ```
///
/// The hasher owns a small native buffer. Call [dispose] when done; a
/// finalizer also frees forgotten hashers at garbage collection, but the
/// native memory is invisible to the Dart heap, so prefer explicit
/// disposal.
final class Blake3Hasher implements Finalizable {
  Blake3Hasher._(this._hasher) {
    _finalizer.attach(this, _hasher, detach: this);
  }

  /// Creates a hasher for the default, unkeyed hash.
  factory Blake3Hasher() {
    final hasher = _allocateHasher();
    blake3HasherInit(hasher);
    return Blake3Hasher._(hasher);
  }

  /// Creates a keyed hasher (a MAC / PRF). [key] must be exactly
  /// [blake3KeyLength] (32) bytes.
  ///
  /// Throws [ArgumentError] if [key] is not 32 bytes long.
  factory Blake3Hasher.keyed(Uint8List key) {
    if (key.length != blake3KeyLength) {
      throw ArgumentError.value(
        key.length,
        'key.length',
        'BLAKE3 key must be exactly $blake3KeyLength bytes',
      );
    }
    final hasher = _allocateHasher();
    final keyBuffer = allocateBytes(blake3KeyLength);
    try {
      keyBuffer.asTypedList(blake3KeyLength).setAll(0, key);
      blake3HasherInitKeyed(hasher, keyBuffer);
    } finally {
      freeBytes(keyBuffer);
    }
    return Blake3Hasher._(hasher);
  }

  /// Creates a hasher in key-derivation (KDF) mode.
  ///
  /// [context] is an application-specific, globally unique domain
  /// separation string (for example
  /// `'example.com 2024 session tokens v1'`). Material fed with [update]
  /// is then turned into derived key bytes by [finalize]. The context
  /// should be hardcoded, not attacker-controlled.
  factory Blake3Hasher.deriveKey(String context) {
    final contextBytes = utf8.encode(context);
    final hasher = _allocateHasher();
    final contextBuffer = allocateBytes(contextBytes.length);
    try {
      contextBuffer.asTypedList(contextBytes.length).setAll(0, contextBytes);
      blake3HasherInitDeriveKeyRaw(hasher, contextBuffer, contextBytes.length);
    } finally {
      freeBytes(contextBuffer);
    }
    return Blake3Hasher._(hasher);
  }

  static final NativeFinalizer _finalizer = NativeFinalizer(freeFunction);

  Pointer<Void> _hasher;
  bool _disposed = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Feeds [data] into the hasher. May be called any number of times.
  ///
  /// Accepts any `List<int>`, so chunks straight from a `Stream<List<int>>`
  /// (a file's `openRead()`, a socket) feed in without wrapping. A
  /// [Uint8List] passes through untouched; any other list is copied once.
  ///
  /// Throws [StateError] if the hasher has been disposed.
  void update(List<int> data) {
    _checkNotDisposed();
    updateHasher(_hasher, data is Uint8List ? data : Uint8List.fromList(data));
  }

  /// Returns [outputLength] bytes of hash output.
  ///
  /// [outputLength] defaults to 32 and may be any non-negative value:
  /// BLAKE3 produces an unbounded stream, so lengths above 32 give the
  /// extendable output (XOF). [seek] skips that many bytes into the output
  /// stream, so `finalize(seek: 64, outputLength: 32)` returns output
  /// bytes 64..95. Finalizing leaves the hasher usable.
  ///
  /// Throws [ArgumentError] if [outputLength] or [seek] is negative, and
  /// [StateError] if the hasher has been disposed.
  Uint8List finalize({int outputLength = blake3OutLength, int seek = 0}) {
    _checkNotDisposed();
    return finalizeHasher(_hasher, outputLength, seek);
  }

  /// Like [finalize] but returns the output as a lowercase hex string, so a
  /// streamed digest formats the same way [blake3Hex] does.
  String finalizeHex({int outputLength = blake3OutLength, int seek = 0}) =>
      toHex(finalize(outputLength: outputLength, seek: seek));

  /// Resets the hasher to its just-created state, keeping the same mode
  /// and key. Lets you reuse one hasher for many independent inputs
  /// without reallocating.
  ///
  /// Throws [StateError] if the hasher has been disposed.
  void reset() {
    _checkNotDisposed();
    blake3HasherReset(_hasher);
  }

  /// Releases the native hasher. Safe to call more than once. After
  /// disposal, [update], [finalize] and [reset] throw [StateError].
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    freeBytes(_hasher.cast());
    _hasher = nullptr;
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('Blake3Hasher has been disposed');
    }
  }

  static Pointer<Void> _allocateHasher() =>
      allocateBytes(hasherSize).cast<Void>();
}

/// Feeds [data] into [hasher] with a single native copy. Shared by
/// [Blake3Hasher.update] and the one-shot top-level functions.
void updateHasher(Pointer<Void> hasher, Uint8List data) {
  if (data.isEmpty) return;
  final input = allocateBytes(data.length);
  try {
    input.asTypedList(data.length).setAll(0, data);
    blake3HasherUpdate(hasher, input, data.length);
  } finally {
    freeBytes(input);
  }
}

/// Reads [outputLength] bytes of output from [hasher] at offset [seek].
/// Shared by [Blake3Hasher.finalize] and the one-shot top-level functions.
Uint8List finalizeHasher(Pointer<Void> hasher, int outputLength, int seek) {
  if (outputLength < 0) {
    throw ArgumentError.value(
      outputLength,
      'outputLength',
      'must not be negative',
    );
  }
  if (seek < 0) {
    throw ArgumentError.value(seek, 'seek', 'must not be negative');
  }
  if (outputLength == 0) return Uint8List(0);
  final out = allocateBytes(outputLength);
  try {
    blake3HasherFinalizeSeek(hasher, seek, out, outputLength);
    return Uint8List.fromList(out.asTypedList(outputLength));
  } finally {
    freeBytes(out);
  }
}
