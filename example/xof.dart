/// BLAKE3's output is a stream, and the 32-byte digest is only its start.
///
/// Any hash here can be read for as many bytes as you want. `outputLength`
/// asks for more of the stream and `seek` starts reading further along it,
/// which turns one hash into a source of as much key material as a protocol
/// needs.
///
/// Two properties make that usable, and this file checks both over every byte
/// instead of stating them: reading more output never rewrites the bytes you
/// already read, and a window taken with `seek` is identical to that slice of
/// one long read.
///
///     dart run example/xof.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:blake3_ffi/blake3_ffi.dart';

void main() {
  _oneStream();
  print('');
  _threeSubkeys();
}

/// Reads the same input three ways and shows the three reads are one stream.
void _oneStream() {
  final data = utf8.encode('one input, read three ways');

  final digest = blake3(data);
  final extended = blake3(data, outputLength: 64);
  final second = _window(data, offset: 32, length: 32);

  print('one input, one output stream');
  print('  32 bytes            ${_hex(digest)}');
  print('  64 bytes            ${_hex(extended)}');
  print('  bytes 32..63, seek  ${_hex(second)}');

  // The hex above is truncated for width. Both checks run over every byte.
  _verify(
    'the 32-byte digest is the first half of the 64-byte read',
    digest,
    Uint8List.sublistView(extended, 0, 32),
  );
  _verify(
    'the seeked window is the second half of that same read',
    second,
    Uint8List.sublistView(extended, 32, 64),
  );
}

/// Takes three purpose-bound values out of one key derivation.
///
/// Encrypt-then-MAC wants two keys that cannot be computed from each other,
/// and the stored record wants a short id naming which key wrote it. One
/// derive-key pass over the secret yields all three as consecutive windows of
/// its output, at the offsets printed below. Windows need not be the same
/// length; the id is 8 bytes.
void _threeSubkeys() {
  const context = 'example.com 2026 message envelope v1';
  final secret = utf8.encode('master secret');

  final cipherKey = _deriveWindow(context, secret, offset: 0, length: 32);
  final macKey = _deriveWindow(context, secret, offset: 32, length: 32);
  final keyId = _deriveWindow(context, secret, offset: 64, length: 8);

  print('one derivation, three purpose-bound values');
  print('  cipher key  bytes  0..31  ${_hex(cipherKey)}');
  print('  mac key     bytes 32..63  ${_hex(macKey)}');
  print('  key id      bytes 64..71  ${_hex(keyId)}');

  // Reading the whole 72 bytes in one call has to give the same three pieces.
  final whole = blake3DeriveKey(context, secret, outputLength: 72);
  _verify(
    'the cipher key is bytes 0..31 of one 72-byte derivation',
    cipherKey,
    Uint8List.sublistView(whole, 0, 32),
  );
  _verify(
    'the mac key is bytes 32..63 of it',
    macKey,
    Uint8List.sublistView(whole, 32, 64),
  );
  _verify(
    'the key id is bytes 64..71 of it',
    keyId,
    Uint8List.sublistView(whole, 64, 72),
  );
}

/// Reads [length] bytes of the BLAKE3 stream for [data], starting at [offset].
/// Nothing before [offset] is handed back, and asking for a later window costs
/// the same as asking for the first one.
Uint8List _window(Uint8List data, {required int offset, required int length}) {
  final hasher = Blake3Hasher()..update(data);
  try {
    return hasher.finalize(seek: offset, outputLength: length);
  } finally {
    hasher.dispose();
  }
}

/// The same read in key-derivation mode, where [context] separates this use of
/// [secret] from every other use of it.
Uint8List _deriveWindow(
  String context,
  Uint8List secret, {
  required int offset,
  required int length,
}) {
  final hasher = Blake3Hasher.deriveKey(context)..update(secret);
  try {
    return hasher.finalize(seek: offset, outputLength: length);
  } finally {
    hasher.dispose();
  }
}

/// Compares every byte, then prints the claim it just established.
///
/// Throws instead of warning: `dart run` leaves asserts off, and a check that
/// cannot fail is decoration.
void _verify(String claim, Uint8List actual, Uint8List expected) {
  if (actual.length != expected.length) {
    throw StateError(
      'length differs (${actual.length} vs '
      '${expected.length}): $claim',
    );
  }
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) {
      throw StateError('byte $i differs: $claim');
    }
  }
  print('  verified: $claim');
}

/// The first 16 bytes as lowercase hex, marked when the value is longer.
String _hex(Uint8List bytes) {
  final head = bytes
      .take(16)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return bytes.length > 16 ? '$head...' : head;
}
