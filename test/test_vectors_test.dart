import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blake3_ffi/blake3_ffi.dart';
import 'package:test/test.dart';

/// Drives the official BLAKE3 test vectors
/// (https://github.com/BLAKE3-team/BLAKE3/blob/master/test_vectors).
///
/// Each case fixes an input length; the input is the repeating byte
/// sequence 0, 1, ..., 250, 0, 1, .... Every case provides an extended
/// (131-byte) output for the default hash, keyed hash, and key-derivation
/// modes. Implementations must match both the extended output and its
/// first 32 bytes.
void main() {
  final vectors =
      jsonDecode(File('test/test_vectors.json').readAsStringSync())
          as Map<String, dynamic>;
  final key = Uint8List.fromList(utf8.encode(vectors['key'] as String));
  final context = vectors['context_string'] as String;
  final cases = (vectors['cases'] as List).cast<Map<String, dynamic>>();

  test('the fixture has the expected shape', () {
    expect(cases, hasLength(35));
    expect(key, hasLength(32));
    expect(context, 'BLAKE3 2019-12-27 16:29:52 test vectors context');
  });

  group('default hash', () {
    for (final testCase in cases) {
      final inputLen = testCase['input_len'] as int;
      final expected = testCase['hash'] as String;
      final input = _vectorInput(inputLen);
      final fullLength = expected.length ~/ 2;

      test('input_len $inputLen, extended output', () {
        expect(blake3Hex(input, outputLength: fullLength), expected);
      });
      test('input_len $inputLen, default 32-byte output', () {
        expect(blake3Hex(input), expected.substring(0, 64));
      });
    }
  });

  group('keyed hash', () {
    for (final testCase in cases) {
      final inputLen = testCase['input_len'] as int;
      final expected = testCase['keyed_hash'] as String;
      final input = _vectorInput(inputLen);
      final fullLength = expected.length ~/ 2;

      test('input_len $inputLen, extended output', () {
        expect(
          _hex(blake3Keyed(key, input, outputLength: fullLength)),
          expected,
        );
      });
      test('input_len $inputLen, default 32-byte output', () {
        expect(_hex(blake3Keyed(key, input)), expected.substring(0, 64));
      });
    }
  });

  group('derive key', () {
    for (final testCase in cases) {
      final inputLen = testCase['input_len'] as int;
      final expected = testCase['derive_key'] as String;
      final input = _vectorInput(inputLen);
      final fullLength = expected.length ~/ 2;

      test('input_len $inputLen, extended output', () {
        expect(
          _hex(blake3DeriveKey(context, input, outputLength: fullLength)),
          expected,
        );
      });
      test('input_len $inputLen, default 32-byte output', () {
        expect(
          _hex(blake3DeriveKey(context, input)),
          expected.substring(0, 64),
        );
      });
    }
  });

  group('streaming equals one-shot across all modes', () {
    for (final testCase in cases) {
      final inputLen = testCase['input_len'] as int;
      if (inputLen == 0) continue; // Nothing to split.
      final input = _vectorInput(inputLen);
      final fullLength = (testCase['hash'] as String).length ~/ 2;

      test('input_len $inputLen', () {
        for (final hasher in [
          Blake3Hasher(),
          Blake3Hasher.keyed(key),
          Blake3Hasher.deriveKey(context),
        ]) {
          try {
            _updateInThirds(hasher, input);
            final streamed = hasher.finalize(outputLength: fullLength);
            hasher.reset();
            hasher.update(input);
            final oneShot = hasher.finalize(outputLength: fullLength);
            expect(streamed, oneShot);
          } finally {
            hasher.dispose();
          }
        }
      });
    }
  });

  group('finalize seek reads the same extended stream', () {
    for (final testCase in cases) {
      final inputLen = testCase['input_len'] as int;
      final expected = testCase['hash'] as String;
      final fullLength = expected.length ~/ 2;
      final input = _vectorInput(inputLen);

      test('input_len $inputLen, bytes 32..$fullLength via seek', () {
        final hasher = Blake3Hasher()..update(input);
        try {
          final tail = hasher.finalize(seek: 32, outputLength: fullLength - 32);
          expect(_hex(tail), expected.substring(64));
        } finally {
          hasher.dispose();
        }
      });
    }
  });
}

/// The repeating 0..250 byte sequence of length [length] used by every
/// BLAKE3 test vector.
Uint8List _vectorInput(int length) {
  final input = Uint8List(length);
  for (var i = 0; i < length; i++) {
    input[i] = i % 251;
  }
  return input;
}

void _updateInThirds(Blake3Hasher hasher, Uint8List input) {
  final third = input.length ~/ 3;
  hasher
    ..update(Uint8List.sublistView(input, 0, third))
    ..update(Uint8List.sublistView(input, third, third * 2))
    ..update(Uint8List.sublistView(input, third * 2));
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
