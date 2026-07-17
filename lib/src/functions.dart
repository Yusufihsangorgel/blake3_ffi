import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'bindings.dart';
import 'hasher.dart';

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
    _toHex(blake3(data, outputLength: outputLength));

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

const String _hexDigits = '0123456789abcdef';

String _toHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer
      ..write(_hexDigits[byte >> 4])
      ..write(_hexDigits[byte & 0xf]);
  }
  return buffer.toString();
}
