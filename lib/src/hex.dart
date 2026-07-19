import 'dart:typed_data';

const String _hexDigits = '0123456789abcdef';

/// Lowercase hex encoding of [bytes]. Internal shared helper so every digest
/// path (one-shot, keyed, derived, streamed) formats output the same way.
String toHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer
      ..write(_hexDigits[byte >> 4])
      ..write(_hexDigits[byte & 0xf]);
  }
  return buffer.toString();
}
