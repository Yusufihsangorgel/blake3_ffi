// The single source of every throughput number quoted in README.md,
// doc/benchmark.svg and the pubspec screenshot caption.
//
//   dart run bench/bench.dart                          # markdown tables
//   dart run bench/bench.dart --json doc/benchmark.json
//
// Three candidates hash the same buffers:
//
//   blake3_ffi   this package: the reference BLAKE3 C code over FFI
//   blake3_dart  the pure-Dart BLAKE3 implementation, version pinned in
//                dev_dependencies
//   crypto       SHA-256 from package:crypto, the usual pure-Dart default
//
// Two habits keep the numbers honest.
//
// Placement rotation. Each candidate is measured once in every position,
// because whichever runs first in a round pays the VM's warm-up and would
// otherwise read slower than it is. The reported spread across placements
// says how much that still moved the result.
//
// A digest cross-check. The two BLAKE3 implementations must agree byte for
// byte before anything is timed. If they disagree they are not computing the
// same function and no ratio between them means anything.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:blake3_dart/blake3_dart.dart' as pure;
import 'package:blake3_ffi/blake3_ffi.dart' as native;
import 'package:crypto/crypto.dart' as crypto;

// Shared with the README tables and the chart so all three label a
// 1,048,576-byte buffer the same way. A mismatch here would not throw, it would
// just publish the wrong unit, which is the failure this import removes.
import '../tool/benchmark_data.dart' show sizeLabel;

/// Total bytes each measurement hashes, so a 1 MiB row and a 64 MiB row
/// average out the same amount of scheduling jitter.
const _volumePerMeasurement = 128 * 1024 * 1024;

/// Batches per measurement. The fastest batch is the reported one.
const _batches = 5;

const _bulkSizesMib = [1, 16, 64];
const _smallSizes = [64, 256, 1024, 4096];

/// Throughput is printed as decimal megabytes: 1 MB/s is 10^6 bytes/s.
const _bytesPerMegabyte = 1000 * 1000;

const _ffi = 'blake3_ffi';
const _sha256 = 'crypto sha256';
const _pureDart = 'blake3_dart';

typedef _Candidate = ({String label, int Function(Uint8List) hash});

/// Each closure returns a digest byte, which [_sink] then consumes, so no
/// part of the hash can be optimised away as dead.
const _candidates = <_Candidate>[
  (label: _ffi, hash: _hashNative),
  (label: _sha256, hash: _hashSha256),
  (label: _pureDart, hash: _hashPure),
];

int _hashNative(Uint8List data) => native.blake3(data)[0];
int _hashSha256(Uint8List data) => crypto.sha256.convert(data).bytes[0];
int _hashPure(Uint8List data) => pure.blake3(data)[0];

int _sink = 0;

void main(List<String> arguments) {
  final jsonPath = _optionValue(arguments, '--json');

  final crossCheck = _crossCheckDigests();
  final bulk = [
    for (final mebibytes in _bulkSizesMib)
      _measureAll(_randomBytes(mebibytes * 1024 * 1024)),
  ];
  final small = [
    for (final size in _smallSizes)
      _measureAll(_randomBytes(size), runs: 10000, warmup: 1000),
  ];

  final report = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'machine': {
      'cpu': _cpuName(),
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'dart': Platform.version.split(' ').first,
    },
    'versions': {
      'blake3_dart': _resolvedVersion('blake3_dart'),
      'crypto': _resolvedVersion('crypto'),
    },
    'method': {
      'batchesPerMeasurement': _batches,
      'placements': _candidates.length,
      'volumePerBulkMeasurementBytes': _volumePerMeasurement,
      'throughputUnit': 'MB/s, 1 MB = $_bytesPerMegabyte bytes',
    },
    'crossCheck': crossCheck,
    'bulk': [for (final row in bulk) row.toJson()],
    'small': [for (final row in small) row.toJson()],
  };

  _printMarkdown(report, bulk, small);

  if (jsonPath != null) {
    File(jsonPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    stdout.writeln('\nWrote $jsonPath');
  }

  // Keep the sink observable so the optimiser cannot drop the work above.
  if (_sink == 0x7fffffff) stdout.writeln('(unreachable) $_sink');
}

/// Proves the two BLAKE3 implementations compute the same function before
/// their throughputs are compared. Exits non-zero if they do not.
Map<String, Object> _crossCheckDigests() {
  final samples = <int>[0, 1, 63, 64, 1024, 1024 * 1024];
  for (final length in samples) {
    final data = _randomBytes(length);
    final ours = native.blake3(data);
    final theirs = pure.blake3(data);
    if (!_bytesEqual(ours, theirs)) {
      stderr.writeln(
        'digest mismatch at $length bytes:\n'
        '  blake3_ffi  ${_hex(ours)}\n'
        '  blake3_dart ${_hex(theirs)}',
      );
      exit(1);
    }
  }
  return {
    'inputLengths': samples,
    'agree': true,
    'digestOf1MiB': _hex(native.blake3(_randomBytes(1024 * 1024))),
  };
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// One input size, every candidate, measured once in every placement.
class _SizeResult {
  _SizeResult(this.inputBytes, this.microsByLabel);

  final int inputBytes;

  /// Label to per-call microseconds, one entry per placement.
  final Map<String, List<double>> microsByLabel;

  /// Fastest placement, in microseconds per call.
  double bestMicros(String label) => microsByLabel[label]!.reduce(min);

  double throughput(String label) =>
      inputBytes / bestMicros(label) * 1e6 / _bytesPerMegabyte;

  /// How far the slowest placement fell behind the fastest, as a fraction of
  /// the fastest. Large values mean the ordering still mattered.
  double placementSpread(String label) {
    final placements = microsByLabel[label]!;
    final fastest = placements.reduce(min);
    return (placements.reduce(max) - fastest) / fastest;
  }

  double ratio(String slower, String faster) =>
      bestMicros(slower) / bestMicros(faster);

  Map<String, Object> toJson() => {
    'inputBytes': inputBytes,
    'candidates': {
      for (final candidate in _candidates)
        candidate.label: {
          'microsPerCall': double.parse(
            bestMicros(candidate.label).toStringAsFixed(4),
          ),
          'throughputMBps': double.parse(
            throughput(candidate.label).toStringAsFixed(1),
          ),
          'placementMicros': [
            for (final micros in microsByLabel[candidate.label]!)
              double.parse(micros.toStringAsFixed(4)),
          ],
          'placementSpread': double.parse(
            placementSpread(candidate.label).toStringAsFixed(4),
          ),
        },
    },
    'ratios': {
      'ffiOverPureDart': double.parse(_ratioText(ratio(_pureDart, _ffi))),
      'ffiOverSha256': double.parse(_ratioText(ratio(_sha256, _ffi))),
    },
  };
}

_SizeResult _measureAll(Uint8List data, {int? runs, int? warmup}) {
  final iterations = runs ?? max(1, _volumePerMeasurement ~/ data.length);
  final warmupIterations = warmup ?? max(1, iterations ~/ 4);
  final microsByLabel = {for (final c in _candidates) c.label: <double>[]};
  for (var rotation = 0; rotation < _candidates.length; rotation++) {
    for (var position = 0; position < _candidates.length; position++) {
      final candidate = _candidates[(position + rotation) % _candidates.length];
      microsByLabel[candidate.label]!.add(
        _measure(
          () => _sink ^= candidate.hash(data),
          warmup: warmupIterations,
          runs: iterations,
        ),
      );
    }
  }
  return _SizeResult(data.length, microsByLabel);
}

/// Mean wall time per call in microseconds, timed in batches so
/// sub-microsecond operations still get real resolution. Reports the fastest
/// of [_batches] batches to cut scheduler noise.
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
  for (var batch = 0; batch < _batches; batch++) {
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

void _printMarkdown(
  Map<String, Object?> report,
  List<_SizeResult> bulk,
  List<_SizeResult> small,
) {
  final machine = report['machine']! as Map<String, Object?>;
  final versions = report['versions']! as Map<String, Object?>;
  stdout
    ..writeln(
      'Measured on ${machine['cpu']} (${machine['os']} '
      '${machine['osVersion']}, Dart ${machine['dart']}), against '
      'blake3_dart ${versions['blake3_dart']} and '
      'crypto ${versions['crypto']}.',
    )
    ..writeln(
      'Each figure is the fastest of $_batches batches, in the fastest of '
      '${_candidates.length} placements. Input sizes are powers of two; '
      '1 MB/s is $_bytesPerMegabyte bytes per second.',
    )
    ..writeln()
    ..writeln('Digests cross-checked: blake3_ffi == blake3_dart.')
    ..writeln()
    ..writeln('## Bulk throughput (MB/s, higher is better)')
    ..writeln()
    ..writeln(
      '| Input | $_ffi | $_pureDart | $_sha256 | vs pure Dart | vs SHA-256 |',
    )
    ..writeln('|---|---|---|---|---|---|');
  for (final row in bulk) {
    stdout.writeln(
      '| ${sizeLabel(row.inputBytes)} '
      '| ${row.throughput(_ffi).round()} '
      '| ${row.throughput(_pureDart).round()} '
      '| ${row.throughput(_sha256).round()} '
      '| ${_ratioText(row.ratio(_pureDart, _ffi))}x '
      '| ${_ratioText(row.ratio(_sha256, _ffi))}x |',
    );
  }

  stdout
    ..writeln()
    ..writeln('## Small inputs (microseconds per call, including FFI overhead)')
    ..writeln()
    ..writeln(
      '| Input | $_ffi | $_pureDart | $_sha256 | vs pure Dart | vs SHA-256 |',
    )
    ..writeln('|---|---|---|---|---|---|');
  for (final row in small) {
    stdout.writeln(
      '| ${sizeLabel(row.inputBytes)} '
      '| ${row.bestMicros(_ffi).toStringAsFixed(2)} '
      '| ${row.bestMicros(_pureDart).toStringAsFixed(2)} '
      '| ${row.bestMicros(_sha256).toStringAsFixed(2)} '
      '| ${_ratioText(row.ratio(_pureDart, _ffi))}x '
      '| ${_ratioText(row.ratio(_sha256, _ffi))}x |',
    );
  }

  stdout
    ..writeln()
    ..writeln('## Placement spread (slowest placement behind fastest)')
    ..writeln()
    ..writeln('| Input | $_ffi | $_pureDart | $_sha256 |')
    ..writeln('|---|---|---|---|');
  for (final row in [...bulk, ...small]) {
    stdout.writeln(
      '| ${sizeLabel(row.inputBytes)} '
      '| ${_percent(row.placementSpread(_ffi))} '
      '| ${_percent(row.placementSpread(_pureDart))} '
      '| ${_percent(row.placementSpread(_sha256))} |',
    );
  }
}

String _ratioText(double ratio) => ratio.toStringAsFixed(1);

String _percent(double fraction) => '${(fraction * 100).toStringAsFixed(1)}%';

Uint8List _randomBytes(int length) {
  final random = Random(42);
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

String? _optionValue(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index >= 0 && index + 1 < arguments.length) return arguments[index + 1];
  for (final argument in arguments) {
    if (argument.startsWith('$name=')) {
      return argument.substring(name.length + 1);
    }
  }
  return null;
}

/// The version actually resolved for [package], read back from the package
/// config rather than from the constraint, so a printed number always names
/// the build it came from.
String _resolvedVersion(String package) {
  final config = File.fromUri(
    Platform.script.resolve('../.dart_tool/package_config.json'),
  );
  if (!config.existsSync()) return 'unknown';
  final decoded = jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
  for (final entry
      in (decoded['packages']! as List<Object?>).cast<Map<String, Object?>>()) {
    if (entry['name'] != package) continue;
    final match = RegExp(
      '$package-([^/]+)',
    ).firstMatch(entry['rootUri'].toString());
    return match?.group(1) ?? 'unknown';
  }
  return 'unknown';
}

String _cpuName() {
  try {
    if (Platform.isMacOS) {
      final result = Process.runSync('sysctl', [
        '-n',
        'machdep.cpu.brand_string',
      ]);
      if (result.exitCode == 0) return result.stdout.toString().trim();
    } else if (Platform.isLinux) {
      final cpuinfo = File('/proc/cpuinfo');
      if (cpuinfo.existsSync()) {
        for (final line in cpuinfo.readAsLinesSync()) {
          if (line.startsWith('model name')) {
            return line.split(':').last.trim();
          }
        }
      }
    }
  } on ProcessException {
    // Fall through to the generic label below.
  }
  return Platform.operatingSystem;
}
