// The README tables are written from doc/benchmark.json by
// tool/readme_tables.dart and the chart by tool/benchmark_svg.dart, but the
// prose figures, the pubspec screenshot caption and the chart text are still
// typed, and the generated files still have to be regenerated after a
// re-measurement. This test is what makes forgetting either one a build
// failure rather than something a reader finds: three artifacts once carried
// three different numbers for the same row, and one of them named the wrong
// baseline entirely.
//
// It is a guard on the figures, not on the sentences around them. A mutation
// audit of eleven single-edit drifts killed three and let eight through: the
// input size and machine in the pubspec caption, the baseline versions in the
// caption and in the prose, a caption that keeps all three figures but hands
// them to the wrong engines, the input size in the opening paragraph, and two
// prose claims in "Performance, honestly". doc/benchmark.png survived too, and
// that is the chart a reader actually sees; only the SVG it is rendered from
// is checked here, because rsvg-convert is not available on every CI runner.
//
// It checks agreement with doc/benchmark.json, not that the numbers are right
// for the machine running the test, so it is stable on CI. To change the
// numbers, re-measure and redraw:
//
//   dart run bench/bench.dart --json doc/benchmark.json
//   dart run tool/readme_tables.dart
//   dart run tool/benchmark_svg.dart
//
// then update the prose figures and the pubspec caption until this passes.
import 'dart:io';

import 'package:test/test.dart';

import '../tool/benchmark_data.dart';
import '../tool/readme_tables.dart';

void main() {
  final report = BenchmarkReport.readFile(File('doc/benchmark.json'));
  final headline = report.headline;

  final native = headline.throughputMBps(labelFfi).round();
  final pureDart = headline.throughputMBps(labelPureDart).round();
  final sha256 = headline.throughputMBps(labelSha256).round();

  /// The speed-up as prose rounds it: "22x", "a factor of 22".
  final wholeRatio = headline.ratioOverFfi(labelPureDart).round();

  test('the README tables are the ones tool/readme_tables.dart writes', () {
    final readme = File('README.md').readAsStringSync();
    expect(
      _lf(_generatedBlock(readme)),
      _lf(renderBlock(report)),
      reason:
          'README.md has drifted from doc/benchmark.json. '
          'Run `dart run tool/readme_tables.dart`.',
    );
  });

  test('the README prose quotes the measured headline row', () {
    final readme = _unwrapped(File('README.md').readAsStringSync());
    expect(
      readme,
      contains('$native MB/s against $pureDart MB/s'),
      reason: 'the prose figure in "Which BLAKE3 package" has drifted',
    );
    expect(
      readme,
      contains('a factor of $wholeRatio'),
      reason: 'the rounded speed-up in "Which BLAKE3 package" has drifted',
    );
    expect(
      readme,
      contains('${wholeRatio}x its throughput'),
      reason: 'the speed-up in the opening paragraph has drifted',
    );
    expect(
      readme,
      contains('${sizeLabel(headlineBytes)} on an ${report.cpu}'),
      reason:
          'the prose names a different input size or machine than the '
          'measurement it quotes',
    );
  });

  test('the pubspec screenshot caption quotes the same figures', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final figure in [native, pureDart, sha256]) {
      expect(
        pubspec,
        contains('$figure'),
        reason: 'pub.dev renders this caption; $figure is not in it',
      );
    }
    expect(
      pubspec,
      contains('${wholeRatio}x'),
      reason: 'the speed-up in the package description has drifted',
    );
    // The baseline this package is compared against lives in package:crypto,
    // not in dart:core. That mistake shipped once.
    expect(pubspec, isNot(contains('dart:core')));
  });

  test('the chart was redrawn from the same measurement', () {
    final svg = File('doc/benchmark.svg').readAsStringSync();
    for (final figure in [native, pureDart, sha256]) {
      expect(
        svg,
        contains('>$figure</text>'),
        reason: 'doc/benchmark.svg is stale; run tool/benchmark_svg.dart',
      );
    }
    expect(
      svg,
      contains('${ratioText(headline, labelPureDart)}x the pure-Dart path'),
    );
    expect(
      svg,
      contains('BLAKE3 at ${sizeLabel(headlineBytes)}:'),
      reason: 'the chart headline names a different input size',
    );
  });

  test('the two BLAKE3 implementations agreed when this was measured', () {
    expect(
      report.implementationsAgree,
      isTrue,
      reason:
          'a throughput ratio between two different functions means '
          'nothing',
    );
  });

  test('ordering still barely mattered, as the README claims', () {
    expect(
      _unwrapped(File('README.md').readAsStringSync()),
      contains('under 0.6% at ${sizeLabel(headlineBytes)}'),
      reason: 'the caveat this test backs is no longer the one in the README',
    );
    for (final label in [labelFfi, labelPureDart, labelSha256]) {
      expect(
        headline.placementSpread(label),
        lessThan(0.006),
        reason:
            'README says the spread across placements was under 0.6% at '
            '${sizeLabel(headlineBytes)}, and $label no longer is',
      );
    }
  });

  test('per-call cost is still negligible against a bulk call', () {
    final smallest = report.small.firstWhere((row) => row.inputBytes == 64);
    final bulk = report.bulk.firstWhere((row) => row.inputBytes == 1024 * 1024);
    expect(
      bulk.microsPerCall(labelFfi) / smallest.microsPerCall(labelFfi),
      greaterThanOrEqualTo(1000),
      reason:
          'README says a 1 MiB call costs three orders of magnitude more '
          'than the 64-byte row, which is what makes those rows a measure '
          'of the kernel rather than of the call',
    );
  });

  test('the throughput recorded alongside each row still agrees with it', () {
    for (final row in [...report.bulk, ...report.small]) {
      for (final label in [labelFfi, labelPureDart, labelSha256]) {
        final derived = row.throughputMBps(label);
        // The stored field is a one-decimal copy of a value that inputBytes
        // and microsPerCall already determine. Allow the half unit its own
        // rounding can move it, plus what the four-decimal rounding of
        // microsPerCall can move the derived value by.
        final slack = 0.05 + derived * (0.00005 / row.microsPerCall(label));
        expect(
          row.storedThroughputMBps(label),
          closeTo(derived, slack),
          reason:
              'doc/benchmark.json disagrees with itself at '
              '${sizeLabel(row.inputBytes)} for $label',
        );
      }
    }
  });
}

/// Prose here is hard-wrapped, so a quoted phrase can straddle a line break:
/// "22x its" ends one line and "throughput" starts the next. Matching against a
/// single-spaced copy keeps these checks about the words rather than about
/// where the wrap happens to fall. The pubspec is matched raw instead, because
/// there a phrase split across lines is the bug being watched for.
/// Normalises line endings before a block comparison.
///
/// `StringBuffer.writeln` always writes `\n`, and a Windows checkout can hand
/// back the same file with `\r\n`. Comparing the two raw turned the suite red
/// on one runner out of three for a difference that is not in the content.
String _lf(String text) => text.replaceAll('\r\n', '\n');

String _unwrapped(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

/// The part of README.md that tool/readme_tables.dart owns.
String _generatedBlock(String readme) {
  final markerStart = readme.indexOf(beginMarker);
  final end = readme.indexOf(endMarker);
  if (markerStart < 0 || end < markerStart) {
    fail('README.md has no $beginMarker ... $endMarker pair');
  }
  return readme.substring(readme.indexOf('\n', markerStart) + 1, end);
}
