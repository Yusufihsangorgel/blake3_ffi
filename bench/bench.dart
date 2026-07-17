// Compares native BLAKE3 against dart:convert-style hashing via the
// `crypto` package (SHA-256), on the same byte buffers.
// Run with: dart run bench/bench.dart
import 'dart:math';
import 'dart:typed_data';

import 'package:blake3_ffi/blake3_ffi.dart';
import 'package:crypto/crypto.dart' as crypto;

void main() {
  print('BLAKE3 (native FFI) vs crypto SHA-256 (pure Dart)\n');

  print('== bulk throughput');
  print(
    '  ${'size'.padLeft(8)}  ${'blake3'.padLeft(11)}'
    '  ${'sha256'.padLeft(11)}  ratio',
  );
  for (final megabytes in [1, 16, 64]) {
    final data = _randomBytes(megabytes * 1024 * 1024);
    final blake3Time = _measure(() => blake3(data), warmup: 2, runs: 4);
    final sha256Time = _measure(
      () => crypto.sha256.convert(data),
      warmup: 2,
      runs: 4,
    );
    print(
      '  ${'${megabytes}MB'.padLeft(8)}'
      '  ${_throughput(blake3Time, data.length)}'
      '  ${_throughput(sha256Time, data.length)}'
      '  ${(sha256Time / blake3Time).toStringAsFixed(1)}x',
    );
  }

  print('\n== small-input latency (per call, includes FFI overhead)');
  print(
    '  ${'size'.padLeft(8)}  ${'blake3'.padLeft(10)}'
    '  ${'sha256'.padLeft(10)}  ratio',
  );
  for (final size in [64, 256, 1024, 4096]) {
    final data = _randomBytes(size);
    final blake3Time = _measure(() => blake3(data), warmup: 1000, runs: 20000);
    final sha256Time = _measure(
      () => crypto.sha256.convert(data),
      warmup: 1000,
      runs: 20000,
    );
    print(
      '  ${'${size}B'.padLeft(8)}'
      '  ${_micros(blake3Time)}'
      '  ${_micros(sha256Time)}'
      '  ${(sha256Time / blake3Time).toStringAsFixed(1)}x',
    );
  }
}

Uint8List _randomBytes(int length) {
  final random = Random(42);
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

/// Mean wall time per call in microseconds, timed in batches so
/// sub-microsecond operations still get real resolution. Reports the
/// fastest of several batches to cut scheduler noise.
double _measure(
  void Function() body, {
  required int warmup,
  required int runs,
}) {
  for (var i = 0; i < warmup; i++) {
    body();
  }
  final watch = Stopwatch();
  var best = double.infinity;
  for (var batch = 0; batch < 5; batch++) {
    watch
      ..reset()
      ..start();
    for (var i = 0; i < runs; i++) {
      body();
    }
    watch.stop();
    final perCall = watch.elapsedMicroseconds / runs;
    if (perCall < best) best = perCall;
  }
  return best;
}

String _throughput(double micros, int bytes) {
  if (micros <= 0) return 'n/a'.padLeft(11);
  final mbPerSec = bytes / micros; // bytes/us == MB/s
  return '${mbPerSec.toStringAsFixed(0)} MB/s'.padLeft(11);
}

String _micros(double micros) => '${micros.toStringAsFixed(3)}us'.padLeft(10);
