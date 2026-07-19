import 'dart:math';
import 'dart:typed_data';

import 'package:blake3_ffi/blake3_ffi.dart';
import 'package:test/test.dart';

void main() {
  Uint8List randomBytes(int length, [int seed = 1]) {
    final random = Random(seed);
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  group('one-shot', () {
    test('is deterministic', () {
      final data = randomBytes(1000);
      expect(blake3(data), blake3(data));
    });

    test('default output is 32 bytes', () {
      expect(blake3(randomBytes(10)), hasLength(32));
    });

    test('empty input hashes without error', () {
      expect(blake3(Uint8List(0)), hasLength(32));
    });

    test('blake3Hex agrees with blake3', () {
      final data = randomBytes(64);
      final hex = blake3Hex(data);
      expect(hex, hasLength(64));
      expect(hex, matches(RegExp(r'^[0-9a-f]+$')));
      expect(hex, _hex(blake3(data)));
    });

    test('blake3KeyedHex agrees with blake3Keyed', () {
      final key = randomBytes(32);
      final data = randomBytes(64);
      expect(blake3KeyedHex(key, data), _hex(blake3Keyed(key, data)));
    });

    test('blake3DeriveKeyHex agrees with blake3DeriveKey', () {
      final material = randomBytes(48);
      const context = 'blake3_ffi test 2026';
      expect(
        blake3DeriveKeyHex(context, material),
        _hex(blake3DeriveKey(context, material)),
      );
    });

    test('Blake3Hasher.finalizeHex agrees with finalize', () {
      final data = randomBytes(200);
      final hasher = Blake3Hasher()..update(data);
      try {
        expect(hasher.finalizeHex(), _hex(hasher.finalize()));
      } finally {
        hasher.dispose();
      }
    });
  });

  group('streaming', () {
    test('matches one-shot regardless of chunk boundaries', () {
      final data = randomBytes(5000, 42);
      final oneShot = blake3(data);
      for (final chunkSize in [1, 7, 64, 999, 5000]) {
        final hasher = Blake3Hasher();
        try {
          for (var offset = 0; offset < data.length; offset += chunkSize) {
            final end = min(offset + chunkSize, data.length);
            hasher.update(Uint8List.sublistView(data, offset, end));
          }
          expect(hasher.finalize(), oneShot, reason: 'chunkSize=$chunkSize');
        } finally {
          hasher.dispose();
        }
      }
    });

    test('finalize can be called repeatedly and after more updates', () {
      final hasher = Blake3Hasher()..update(randomBytes(100));
      try {
        final first = hasher.finalize();
        expect(hasher.finalize(), first); // Not consumed.
        hasher.update(randomBytes(100, 2));
        expect(hasher.finalize(), isNot(first)); // Reflects new input.
      } finally {
        hasher.dispose();
      }
    });

    test('reset returns the hasher to its initial state', () {
      final data = randomBytes(200, 3);
      final hasher = Blake3Hasher()..update(data);
      try {
        hasher
          ..finalize()
          ..reset()
          ..update(data);
        expect(hasher.finalize(), blake3(data));
      } finally {
        hasher.dispose();
      }
    });
  });

  group('extendable output (XOF)', () {
    test('longer output extends, it does not replace', () {
      final data = randomBytes(50);
      final short = blake3(data);
      final long = blake3(data, outputLength: 131);
      expect(long, hasLength(131));
      expect(Uint8List.sublistView(long, 0, 32), short);
    });

    test('seek reads a window of the same stream', () {
      final hasher = Blake3Hasher()..update(randomBytes(80));
      try {
        final whole = hasher.finalize(outputLength: 200);
        final window = hasher.finalize(seek: 64, outputLength: 100);
        expect(window, Uint8List.sublistView(whole, 64, 164));
      } finally {
        hasher.dispose();
      }
    });

    test('zero output length returns an empty digest', () {
      expect(blake3(randomBytes(10), outputLength: 0), isEmpty);
    });

    test('negative output length throws ArgumentError', () {
      final hasher = Blake3Hasher();
      try {
        expect(() => hasher.finalize(outputLength: -1), throwsArgumentError);
      } finally {
        hasher.dispose();
      }
    });

    test('negative seek throws ArgumentError', () {
      final hasher = Blake3Hasher();
      try {
        expect(() => hasher.finalize(seek: -1), throwsArgumentError);
      } finally {
        hasher.dispose();
      }
    });
  });

  group('keyed hashing', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));

    test('keyed digest differs from the unkeyed digest', () {
      final data = randomBytes(64);
      expect(blake3Keyed(key, data), isNot(blake3(data)));
    });

    test('top-level and streaming keyed agree', () {
      final data = randomBytes(300, 5);
      final hasher = Blake3Hasher.keyed(key)..update(data);
      try {
        expect(hasher.finalize(), blake3Keyed(key, data));
      } finally {
        hasher.dispose();
      }
    });

    test('a different key gives a different digest', () {
      final data = randomBytes(64);
      final otherKey = Uint8List.fromList(List<int>.filled(32, 7));
      expect(blake3Keyed(key, data), isNot(blake3Keyed(otherKey, data)));
    });

    test('wrong key length throws ArgumentError', () {
      final data = randomBytes(10);
      expect(() => blake3Keyed(Uint8List(31), data), throwsArgumentError);
      expect(() => blake3Keyed(Uint8List(33), data), throwsArgumentError);
      expect(() => Blake3Hasher.keyed(Uint8List(16)), throwsArgumentError);
    });
  });

  group('key derivation', () {
    test('top-level and streaming derive-key agree', () {
      final material = randomBytes(128, 9);
      const context = 'blake3_ffi test 2026 derive';
      final hasher = Blake3Hasher.deriveKey(context)..update(material);
      try {
        expect(hasher.finalize(), blake3DeriveKey(context, material));
      } finally {
        hasher.dispose();
      }
    });

    test('different contexts derive different keys', () {
      final material = randomBytes(64, 11);
      expect(
        blake3DeriveKey('context A', material),
        isNot(blake3DeriveKey('context B', material)),
      );
    });

    test('derive-key differs from the plain hash', () {
      final material = randomBytes(64, 12);
      expect(blake3DeriveKey('ctx', material), isNot(blake3(material)));
    });
  });

  group('lifecycle', () {
    test('dispose is idempotent', () {
      final hasher = Blake3Hasher();
      expect(hasher.isDisposed, isFalse);
      hasher.dispose();
      expect(hasher.isDisposed, isTrue);
      expect(hasher.dispose, returnsNormally);
    });

    test('use after dispose throws StateError', () {
      final hasher = Blake3Hasher()..dispose();
      expect(() => hasher.update(Uint8List(1)), throwsStateError);
      expect(hasher.finalize, throwsStateError);
      expect(hasher.reset, throwsStateError);
    });
  });

  group('large input', () {
    test('4 MB one-shot equals chunked streaming', () {
      final data = randomBytes(4 * 1024 * 1024, 99);
      final oneShot = blake3(data);
      final hasher = Blake3Hasher();
      try {
        const chunk = 64 * 1024;
        for (var offset = 0; offset < data.length; offset += chunk) {
          final end = min(offset + chunk, data.length);
          hasher.update(Uint8List.sublistView(data, offset, end));
        }
        expect(hasher.finalize(), oneShot);
      } finally {
        hasher.dispose();
      }
    });
  });
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
