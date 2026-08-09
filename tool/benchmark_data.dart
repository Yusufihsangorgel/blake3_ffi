// One reading of doc/benchmark.json, shared by everything that publishes a
// number from it: tool/readme_tables.dart writes the README tables,
// tool/benchmark_svg.dart draws the chart, and test/published_numbers_test.dart
// checks both against the file. Rounding lives here and only here, so the
// README and the chart cannot round the same measurement two different ways.
//
// The primitive is `microsPerCall`. Throughput is derived from it rather than
// read out of the `throughputMBps` field, which is already rounded to one
// decimal: rounding that again to a whole number turns 2221.48 into 2222.
import 'dart:convert';
import 'dart:io';

/// The input size the README headline, the pubspec screenshot caption and the
/// chart all quote.
const headlineBytes = 16 * 1024 * 1024;

/// Candidate keys, as `bench/bench.dart` writes them.
const labelFfi = 'blake3_ffi';
const labelPureDart = 'blake3_dart';
const labelSha256 = 'crypto sha256';

/// Throughput is reported in decimal megabytes per second, so 1 MB/s is
/// [bytesPerMegabyte] bytes per second.
const bytesPerMegabyte = 1000 * 1000;

/// A benchmark run, read back from the JSON `bench/bench.dart` wrote.
class BenchmarkReport {
  BenchmarkReport(this._json);

  factory BenchmarkReport.readFile(File file) => BenchmarkReport(
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
  );

  final Map<String, Object?> _json;

  Map<String, Object?> get _machine =>
      _json['machine']! as Map<String, Object?>;
  Map<String, Object?> get _method => _json['method']! as Map<String, Object?>;
  Map<String, Object?> get _versions =>
      _json['versions']! as Map<String, Object?>;

  String get cpu => '${_machine['cpu']}';
  String get dartVersion => '${_machine['dart']}';

  /// `Platform.operatingSystem` is lower case and its version string repeats
  /// the word "Version" on macOS; neither reads well in a sentence.
  String get osName => switch ('${_machine['os']}') {
    'macos' => 'macOS',
    'linux' => 'Linux',
    'windows' => 'Windows',
    final other => other,
  };

  String get osVersion {
    final version = '${_machine['osVersion']}';
    return version.startsWith('Version ') ? version.substring(8) : version;
  }

  /// The resolved version of a baseline package, for example `blake3_dart`.
  String version(String package) => '${_versions[package]}';

  int get batches => _method['batchesPerMeasurement']! as int;
  int get placements => _method['placements']! as int;

  bool get implementationsAgree =>
      (_json['crossCheck']! as Map<String, Object?>)['agree']! as bool;

  List<BenchmarkRow> get bulk => _rows('bulk');
  List<BenchmarkRow> get small => _rows('small');

  /// The bulk row every published headline quotes.
  BenchmarkRow get headline => bulk.firstWhere(
    (row) => row.inputBytes == headlineBytes,
    orElse: () => throw StateError(
      'doc/benchmark.json has no $headlineBytes-byte bulk row; the README '
      'headline, the pubspec caption and the chart all quote that size.',
    ),
  );

  List<BenchmarkRow> _rows(String key) => [
    for (final row
        in (_json[key]! as List<Object?>).cast<Map<String, Object?>>())
      BenchmarkRow(row),
  ];
}

/// One input size: every candidate's fastest placement at that size.
class BenchmarkRow {
  BenchmarkRow(this._json);

  final Map<String, Object?> _json;

  int get inputBytes => _json['inputBytes']! as int;

  Map<String, Object?> _candidate(String label) =>
      (_json['candidates']! as Map<String, Object?>)[label]!
          as Map<String, Object?>;

  /// Fastest placement, in microseconds per call. Every other figure on this
  /// row is derived from this one.
  double microsPerCall(String label) =>
      (_candidate(label)['microsPerCall']! as num).toDouble();

  /// Bytes per microsecond is megabytes per second when a megabyte is
  /// [bytesPerMegabyte] bytes, which is why there is no conversion factor here.
  double throughputMBps(String label) => inputBytes / microsPerCall(label);

  /// The rounded copy `bench/bench.dart` also writes. Nothing is published from
  /// it; the test only checks that it still agrees with [throughputMBps].
  double storedThroughputMBps(String label) =>
      (_candidate(label)['throughputMBps']! as num).toDouble();

  /// How far the slowest placement fell behind the fastest, as a fraction.
  double placementSpread(String label) =>
      (_candidate(label)['placementSpread']! as num).toDouble();

  /// How many times faster [labelFfi] was than [slower] at this size.
  double ratioOverFfi(String slower) =>
      microsPerCall(slower) / microsPerCall(labelFfi);
}

/// `1 MiB`, `4 KiB`, `64 B`. Only uses a binary unit when the size is an exact
/// multiple of it, so a 1500-byte row could never print as `1 KiB`.
String sizeLabel(int bytes) {
  const mebibyte = 1024 * 1024;
  if (bytes >= mebibyte && bytes % mebibyte == 0) {
    return '${bytes ~/ mebibyte} MiB';
  }
  if (bytes >= 1024 && bytes % 1024 == 0) return '${bytes ~/ 1024} KiB';
  return '$bytes B';
}

/// Throughput as published: a whole number of MB/s.
String throughputText(BenchmarkRow row, String label) =>
    row.throughputMBps(label).round().toString();

/// Per-call cost as published: microseconds to two decimals.
String microsText(BenchmarkRow row, String label) =>
    row.microsPerCall(label).toStringAsFixed(2);

/// A speed-up as published, without the trailing `x`.
String ratioText(BenchmarkRow row, String slower) =>
    row.ratioOverFfi(slower).toStringAsFixed(1);

/// Greedy wrap, so a generated paragraph does not arrive as one long line.
List<String> wrapWords(String text, int width) {
  final lines = <String>[];
  var line = StringBuffer();
  for (final word in text.split(' ')) {
    if (line.isEmpty) {
      line.write(word);
    } else if (line.length + 1 + word.length > width) {
      lines.add(line.toString());
      line = StringBuffer(word);
    } else {
      line
        ..write(' ')
        ..write(word);
    }
  }
  if (line.isNotEmpty) lines.add(line.toString());
  return lines;
}
