// Redraws doc/benchmark.svg (and doc/benchmark.png) from the measurements in
// doc/benchmark.json, so the chart cannot drift away from the benchmark that
// produced it.
//
//   dart run bench/bench.dart --json doc/benchmark.json
//   dart run tool/benchmark_svg.dart
//
// Every figure the chart shows — bar values, ratios, versions, machine — comes
// from that file through tool/benchmark_data.dart, which is also what writes
// the README tables, so the two cannot round one measurement two ways. The only
// number typed here is the input size the chart highlights, and it has to name
// a row the benchmark actually measured.
//
// The chart is an emphasis bar chart rather than a categorical one. Three bars
// share one measure and one of them is the subject, so the subject takes the
// accent hue and the two baselines share a single de-emphasis gray; telling the
// baselines apart by colour would encode nothing, and their row labels already
// name them. Both marks clear 3:1 against the surface, and every bar carries a
// direct label, so identity never rests on colour alone.
//
// The PNG is rendered by rsvg-convert when it is on PATH (`brew install
// librsvg`). Without it the SVG is still written and the PNG is left alone.
import 'dart:io';

import 'benchmark_data.dart';

/// Surface and ink. Marks are validated against the surface at 3:1 or better.
const _surface = '#0B1220';
const _accent = '#38BDF8';
const _deEmphasis = '#64748B';
const _inkPrimary = '#E2E8F0';
const _inkSecondary = '#94A3B8';

const _width = 1100;
const _height = 360;

/// Bars start here; row labels are right-aligned just left of it.
const _baselineX = 300.0;
const _maxBarWidth = 600.0;
const _barHeight = 24.0;
const _rowPitch = 48.0;
const _firstRowTop = 116.0;
const _cornerRadius = 4.0;

/// Benchmark label to the name shown on the chart. `%s` takes the resolved
/// version of the package behind that row.
const _rowLabels = <String, (String, String?)>{
  labelFfi: ('blake3_ffi (this package)', null),
  labelSha256: ('crypto %s sha256', 'crypto'),
  labelPureDart: ('blake3_dart %s (pure Dart)', 'blake3_dart'),
};

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

  final svg = _renderSvg(BenchmarkReport.readFile(dataFile));

  final svgFile = File('${root.path}/doc/benchmark.svg')
    ..writeAsStringSync(svg);
  stdout.writeln('Wrote ${svgFile.path}');

  final pngFile = File('${root.path}/doc/benchmark.png');
  _renderPng(svgFile, pngFile);
}

String _renderSvg(BenchmarkReport report) {
  final row = report.headline;

  final bars = [
    for (final label in _rowLabels.keys)
      (
        label: _displayLabel(label, report),
        value: row.throughputMBps(label),
        accent: label == labelFfi,
      ),
  ]..sort((a, b) => b.value.compareTo(a.value));

  final scale = _maxBarWidth / bars.first.value;
  final buffer = StringBuffer()
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="$_width" '
      'height="$_height" viewBox="0 0 $_width $_height" '
      'font-family="Menlo, monospace" role="img" '
      'aria-labelledby="chart-title">',
    )
    ..writeln(
      '  <title id="chart-title">${_xml(_altText(bars, row))}'
      '</title>',
    )
    ..writeln('  <rect width="$_width" height="$_height" fill="$_surface"/>')
    ..writeln(
      '  <text x="48" y="52" font-size="24" font-weight="bold" '
      'fill="$_inkPrimary">BLAKE3 at ${sizeLabel(headlineBytes)}: native FFI '
      'against the pure-Dart path</text>',
    )
    ..writeln(
      '  <text x="48" y="80" font-size="14" fill="$_inkSecondary">'
      '${_xml(_subtitle(report))}</text>',
    )
    ..writeln('  <g font-size="14">');

  var top = _firstRowTop;
  for (final bar in bars) {
    final barWidth = bar.value * scale;
    final fill = bar.accent ? _accent : _deEmphasis;
    final textBaseline = top + _barHeight / 2 + 5;
    buffer
      ..writeln('    <path d="${_barPath(top, barWidth)}" fill="$fill"/>')
      ..writeln(
        '    <text x="${_n(_baselineX - 12)}" y="${_n(textBaseline)}" '
        'text-anchor="end" fill="$_inkSecondary">${_xml(bar.label)}</text>',
      )
      ..writeln(
        '    <text x="${_n(_baselineX + barWidth + 12)}" '
        'y="${_n(textBaseline)}" fill="$_inkPrimary">'
        '${bar.value.round()}</text>',
      );
    top += _rowPitch;
  }

  buffer
    ..writeln('  </g>')
    ..writeln(
      '  <line x1="${_n(_baselineX)}" y1="${_n(_firstRowTop - 12)}" '
      'x2="${_n(_baselineX)}" '
      'y2="${_n(top - _rowPitch + _barHeight + 12)}" stroke="$_deEmphasis" '
      'stroke-width="1"/>',
    );

  var captionY = 300.0;
  for (final line in _caption(row)) {
    buffer.writeln(
      '  <text x="48" y="${_n(captionY)}" font-size="13.5" '
      'fill="$_inkSecondary">${_xml(line)}</text>',
    );
    captionY += 20;
  }

  buffer.writeln('</svg>');
  return buffer.toString();
}

String _displayLabel(String key, BenchmarkReport report) {
  final (template, versionKey) = _rowLabels[key]!;
  if (versionKey == null) return template;
  return template.replaceFirst('%s', report.version(versionKey));
}

/// The reported figure is the lowest of every batch in every placement, so it
/// is the fastest placement's fastest batch, not one batch per placement.
String _subtitle(BenchmarkReport report) =>
    '${report.cpu}, Dart ${report.dartVersion}. Fastest of ${report.batches} '
    'batches in the fastest of ${report.placements} placements; MB/s is '
    '1,000,000 bytes per second.';

List<String> _caption(BenchmarkRow row) => [
  '${ratioText(row, labelPureDart)}x the pure-Dart path and '
      '${ratioText(row, labelSha256)}x SHA-256, out of the same NEON kernel '
      'the reference implementation ships.',
  'Both BLAKE3 rows return identical digests; bench/bench.dart checks that '
      'before it times anything.',
];

String _altText(
  List<({bool accent, String label, num value})> bars,
  BenchmarkRow row,
) =>
    'Bar chart of hashing throughput at ${sizeLabel(headlineBytes)}. '
    '${bars.map((b) => '${b.label}, ${b.value.round()} MB per second').join('; ')}. '
    'That is ${ratioText(row, labelPureDart)} times the pure-Dart path.';

/// A bar growing right from the baseline: square where it meets the axis,
/// rounded at the data end. Collapses to a rectangle when it is too short to
/// round without distorting the value.
String _barPath(double top, double width) {
  final bottom = top + _barHeight;
  if (width <= _cornerRadius * 2) {
    return 'M ${_n(_baselineX)} ${_n(top)} H ${_n(_baselineX + width)} '
        'V ${_n(bottom)} H ${_n(_baselineX)} Z';
  }
  final end = _baselineX + width;
  return 'M ${_n(_baselineX)} ${_n(top)} '
      'H ${_n(end - _cornerRadius)} '
      'A $_cornerRadius $_cornerRadius 0 0 1 ${_n(end)} '
      '${_n(top + _cornerRadius)} '
      'V ${_n(bottom - _cornerRadius)} '
      'A $_cornerRadius $_cornerRadius 0 0 1 ${_n(end - _cornerRadius)} '
      '${_n(bottom)} '
      'H ${_n(_baselineX)} Z';
}

/// Coordinates at one decimal, with a trailing `.0` dropped, so the file stays
/// readable and a redraw with the same numbers produces the same bytes.
String _n(double value) {
  final rounded = value.toStringAsFixed(1);
  return rounded.endsWith('.0')
      ? rounded.substring(0, rounded.length - 2)
      : rounded;
}

void _renderPng(File svgFile, File pngFile) {
  final ProcessResult result;
  try {
    result = Process.runSync('rsvg-convert', [
      '-w',
      '$_width',
      '-h',
      '$_height',
      '-o',
      pngFile.path,
      svgFile.path,
    ]);
  } on ProcessException {
    stdout.writeln(
      'rsvg-convert not found; ${pngFile.path} left unchanged. '
      'Install it with `brew install librsvg` (or `apt install librsvg2-bin`) '
      'and run this again.',
    );
    return;
  }
  if (result.exitCode != 0) {
    stderr.writeln('rsvg-convert failed: ${result.stderr}');
    exit(result.exitCode);
  }
  stdout.writeln('Wrote ${pngFile.path}');
}

String _xml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
