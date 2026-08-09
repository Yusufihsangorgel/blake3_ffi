// Writes the benchmark tables in README.md from doc/benchmark.json, so the
// published tables are not a hand copy of a benchmark run.
//
//   dart run bench/bench.dart --json doc/benchmark.json
//   dart run tool/readme_tables.dart
//   dart run tool/benchmark_svg.dart
//
// Running it twice changes nothing the second time. test/published_numbers_test
// .dart renders the same block and fails if README.md has drifted from it, so
// forgetting to run this is a red test rather than a wrong number on pub.dev.
import 'dart:io';

import 'benchmark_data.dart';

const beginMarker = '<!-- benchmark:begin -->';
const endMarker = '<!-- benchmark:end -->';

/// Markdown wraps at the same width as the prose around it.
const _wrapColumn = 80;

void main() {
  final root = Directory.current;
  final dataFile = File('${root.path}/doc/benchmark.json');
  if (!dataFile.existsSync()) {
    stderr.writeln(
      'doc/benchmark.json not found. Run it first:\n'
      '  dart run bench/bench.dart --json doc/benchmark.json',
    );
    exit(1);
  }

  final readmeFile = File('${root.path}/README.md');
  final before = readmeFile.readAsStringSync();
  final after = replaceBlock(
    before,
    renderBlock(BenchmarkReport.readFile(dataFile)),
  );
  if (after == before) {
    stdout.writeln('${readmeFile.path} already matches doc/benchmark.json.');
    return;
  }
  readmeFile.writeAsStringSync(after);
  stdout.writeln('Wrote ${readmeFile.path}');
}

/// The generated part of README.md: where the numbers came from, then the two
/// tables. Everything else in that section is prose about what they mean.
String renderBlock(BenchmarkReport report) {
  final buffer = StringBuffer();
  for (final line in wrapWords(_provenance(report), _wrapColumn)) {
    buffer.writeln(line);
  }
  buffer
    ..writeln()
    ..writeln('Bulk throughput, MB/s:')
    ..writeln()
    ..write(_table(report, report.bulk, throughputText))
    ..writeln()
    ..writeln('Small inputs, microseconds per call including FFI overhead:')
    ..writeln()
    ..write(_table(report, report.small, microsText));
  return buffer.toString();
}

/// Swaps the text between the markers, leaving the rest of the file alone.
String replaceBlock(String readme, String block) {
  final start = readme.indexOf(beginMarker);
  final end = readme.indexOf(endMarker);
  if (start < 0 || end < start) {
    stderr.writeln(
      'README.md has no $beginMarker ... $endMarker pair to write into.',
    );
    exit(1);
  }
  final head = readme.substring(0, start + beginMarker.length);
  return '$head\n$block${readme.substring(end)}';
}

String _provenance(BenchmarkReport report) =>
    'Measured on ${report.cpu}, ${report.osName} ${report.osVersion}, '
    'Dart ${report.dartVersion}, against '
    'blake3_dart ${report.version('blake3_dart')} and '
    'crypto ${report.version('crypto')}. Each figure is the fastest of '
    '${report.batches} batches in the fastest of ${report.placements} '
    'placements. Input sizes are powers of two, so 1 MiB is '
    '${_grouped(1024 * 1024)} bytes; throughput is decimal, so 1 MB/s is '
    '${_grouped(bytesPerMegabyte)} bytes per second.';

/// `1000000` as `1,000,000`, so the sentence quoting it reads like prose.
String _grouped(int value) {
  final digits = '$value';
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String _table(
  BenchmarkReport report,
  List<BenchmarkRow> rows,
  String Function(BenchmarkRow row, String label) cell,
) {
  final buffer = StringBuffer()
    ..writeln(
      '| Input | this package '
      '| blake3_dart ${report.version('blake3_dart')} '
      '| crypto ${report.version('crypto')} SHA-256 '
      '| vs pure Dart | vs SHA-256 |',
    )
    ..writeln('|---|---|---|---|---|---|');
  for (final row in rows) {
    buffer.writeln(
      '| ${sizeLabel(row.inputBytes)} '
      '| ${cell(row, labelFfi)} '
      '| ${cell(row, labelPureDart)} '
      '| ${cell(row, labelSha256)} '
      '| ${ratioText(row, labelPureDart)}x '
      '| ${ratioText(row, labelSha256)}x |',
    );
  }
  return buffer.toString();
}
