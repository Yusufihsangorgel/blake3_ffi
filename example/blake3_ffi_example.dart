import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blake3_ffi/blake3_ffi.dart';

/// Two things this package is good at: hashing a byte buffer in one call,
/// and hashing a large file in a stream without holding it all in memory.
void main() {
  // One-shot: hash a small message and print it as hex.
  final message = utf8.encode('The quick brown fox jumps over the lazy dog');
  print('blake3("...dog") = ${blake3Hex(message)}');

  // Streaming: hash this source file chunk by chunk.
  final digest = hashFile(File(Platform.script.toFilePath()));
  print('this file        = $digest');

  // Keyed hashing (a MAC): both sides share a 32-byte key.
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
  print('keyed("...dog")  = ${_hex(blake3Keyed(key, message))}');

  // Key derivation: turn a shared secret into a purpose-bound subkey.
  final subkey = blake3DeriveKey(
    'example.com 2026 session cookie v1',
    utf8.encode('master secret'),
  );
  print('derived key      = ${_hex(subkey)}');
}

/// Streams [file] through a [Blake3Hasher] 64 KiB at a time, so memory use
/// stays flat no matter how large the file is.
String hashFile(File file) {
  final hasher = Blake3Hasher();
  try {
    final handle = file.openSync();
    try {
      final buffer = Uint8List(64 * 1024);
      while (true) {
        final read = handle.readIntoSync(buffer);
        if (read == 0) break;
        hasher.update(Uint8List.sublistView(buffer, 0, read));
      }
    } finally {
      handle.closeSync();
    }
    return _hex(hasher.finalize());
  } finally {
    hasher.dispose();
  }
}

const String _hexDigits = '0123456789abcdef';

String _hex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer
      ..write(_hexDigits[byte >> 4])
      ..write(_hexDigits[byte & 0xf]);
  }
  return buffer.toString();
}
