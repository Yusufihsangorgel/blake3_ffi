import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'bindings.dart';
import 'hasher.dart';
import 'hex.dart';

/// Hashes [data] with BLAKE3 and returns [outputLength] bytes (32 by
/// default; larger values give the extendable output).
///
/// ```dart
/// final digest = blake3(utf8.encode('hello'));
/// ```
Uint8List blake3(Uint8List data, {int outputLength = blake3OutLength}) =>
    _oneShot(data, outputLength, blake3HasherInit);

/// Like [blake3] but returns the digest as a lowercase hex string.
String blake3Hex(Uint8List data, {int outputLength = blake3OutLength}) =>
    toHex(blake3(data, outputLength: outputLength));

/// Keyed BLAKE3 (a MAC / PRF). [key] must be exactly [blake3KeyLength]
/// (32) bytes.
///
/// Throws [ArgumentError] if [key] is not 32 bytes long.
Uint8List blake3Keyed(
  Uint8List key,
  Uint8List data, {
  int outputLength = blake3OutLength,
}) {
  if (key.length != blake3KeyLength) {
    throw ArgumentError.value(
      key.length,
      'key.length',
      'BLAKE3 key must be exactly $blake3KeyLength bytes',
    );
  }
  return _oneShot(data, outputLength, (hasher) {
    final keyBuffer = allocateBytes(blake3KeyLength);
    try {
      keyBuffer.asTypedList(blake3KeyLength).setAll(0, key);
      blake3HasherInitKeyed(hasher, keyBuffer);
    } finally {
      freeBytes(keyBuffer);
    }
  });
}

/// Like [blake3Keyed] but returns the MAC as a lowercase hex string.
String blake3KeyedHex(
  Uint8List key,
  Uint8List data, {
  int outputLength = blake3OutLength,
}) => toHex(blake3Keyed(key, data, outputLength: outputLength));

/// BLAKE3 key derivation (KDF mode). [context] is a hardcoded,
/// application-specific domain separation string; [keyMaterial] is the
/// input keying material. Returns [outputLength] derived bytes.
///
/// See [Blake3Hasher.deriveKey] for guidance on choosing a context.
Uint8List blake3DeriveKey(
  String context,
  Uint8List keyMaterial, {
  int outputLength = blake3OutLength,
}) {
  final contextBytes = utf8.encode(context);
  return _oneShot(keyMaterial, outputLength, (hasher) {
    final contextBuffer = allocateBytes(contextBytes.length);
    try {
      contextBuffer.asTypedList(contextBytes.length).setAll(0, contextBytes);
      blake3HasherInitDeriveKeyRaw(hasher, contextBuffer, contextBytes.length);
    } finally {
      freeBytes(contextBuffer);
    }
  });
}

/// Like [blake3DeriveKey] but returns the derived key as a lowercase hex string.
String blake3DeriveKeyHex(
  String context,
  Uint8List keyMaterial, {
  int outputLength = blake3OutLength,
}) => toHex(blake3DeriveKey(context, keyMaterial, outputLength: outputLength));

/// Runs init/update/finalize on a native hasher without the [Finalizable]
/// wrapper: the whole lifetime is bounded by this call, so a plain
/// try/finally frees it and avoids the finalizer bookkeeping in the
/// one-shot hot path.
Uint8List _oneShot(
  Uint8List data,
  int outputLength,
  void Function(Pointer<Void> hasher) init,
) {
  final hasher = allocateBytes(hasherSize).cast<Void>();
  try {
    init(hasher);
    updateHasher(hasher, data);
    return finalizeHasher(hasher, outputLength, 0);
  } finally {
    freeBytes(hasher.cast());
  }
}

/// Hashes the bytes of [data] with BLAKE3 as they arrive and returns
/// [outputLength] bytes, without ever holding the whole input in memory.
///
/// This is the streaming counterpart to [blake3]: hand it a file's byte stream
/// (`File(path).openRead()`) or any other `Stream<List<int>>` and it is hashed
/// chunk by chunk through a single [Blake3Hasher], which is disposed when the
/// stream ends. It is the memory-safe way to hash something too large to load at
/// once (a big upload, an archive, a disk image), and unlike a SHA-256 stream
/// from `package:crypto` it runs at BLAKE3's speed.
///
/// ```dart
/// final digest = await blake3Stream(File('big.iso').openRead());
/// ```
Future<Uint8List> blake3Stream(
  Stream<List<int>> data, {
  int outputLength = blake3OutLength,
}) async {
  final hasher = Blake3Hasher();
  try {
    await for (final chunk in data) {
      hasher.update(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
    }
    return hasher.finalize(outputLength: outputLength);
  } finally {
    hasher.dispose();
  }
}

/// Like [blake3Stream] but returns the digest as a lowercase hex string; see
/// [blake3Hex] for the one-shot equivalent.
Future<String> blake3StreamHex(
  Stream<List<int>> data, {
  int outputLength = blake3OutLength,
}) async {
  final digest = await blake3Stream(data, outputLength: outputLength);
  return toHex(digest);
}

/// Renamed to [blake3StreamHex] so the hex variant is a `Hex` suffix on its
/// base name, matching `blake3`/`blake3Hex`, `blake3Keyed`/`blake3KeyedHex`
/// and `blake3DeriveKey`/`blake3DeriveKeyHex`.
@Deprecated('Use blake3StreamHex instead. Will be removed in 2.0.0.')
Future<String> blake3HexStream(
  Stream<List<int>> data, {
  int outputLength = blake3OutLength,
}) => blake3StreamHex(data, outputLength: outputLength);
