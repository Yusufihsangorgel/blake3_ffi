## 1.2.0

- The README now answers, in its first screen, why to reach for this rather
  than the zero-dependency route or the package that already owns the
  category. Both answers carry the file and line, or the issue number, that
  a reader can check. A "reach for it when" list and a sentence on when to
  skip it follow, because a page that only argues for itself is not useful
  for deciding.

## 1.1.3

- Documents how to ship a standalone binary. `dart compile exe` refuses outright
  on a package with a build hook; `dart build cli` runs the hook and writes the
  executable and its library into a `bundle/` directory. The binary resolves the
  library through a relative `../lib`, so a copy of it on its own fails at the
  first call, which is why the whole folder has to ship. Both halves were run to
  produce the output quoted in the README.

## 1.1.2

- `example/xof.dart` calls the extendable output. The README lists XOF among
  the reasons to take this package over the pure-Dart one, and no example
  reached it. The one API that decides that comparison had nowhere to be seen
  running. Docs and example only.

## 1.1.1

Documentation and packaging only. The API, the native code and the digests are
untouched.

- **The benchmark tables in the README are written by a tool now, not copied by
  hand.** The section claimed "nothing here is transcribed by hand" while both
  tables were hand-copied out of a benchmark run, and the test guarding them
  looked at one of the seven rows. `tool/readme_tables.dart` writes them from
  `doc/benchmark.json`, `tool/benchmark_svg.dart` draws the chart through the
  same helpers so the two cannot round one measurement differently, and
  `test/published_numbers_test.dart` now compares the whole generated block and
  looks for the headline figures where they are still typed: the README prose,
  the pubspec description and caption, and the chart's SVG. Six deliberate
  edits, one published figure each and two of them in rows the old test never
  read, all fail it. The words around those figures are not checked, and
  neither is `doc/benchmark.png`.
- Input sizes are labelled in binary units. A 1,048,576-byte buffer was called
  "1 MB" one line below "MB means 1,000,000 bytes"; the rows are 1, 16 and
  64 MiB, and throughput stays in decimal MB/s.
- The method line said each figure was "the fastest of five batches in each of
  three orderings". It is the fastest batch of the fastest placement, which is
  a stronger claim than the sentence made; the README and the chart both say
  that now.
- "Gave up web and mobile" understated the cost of the native path: there is no
  Flutter support on any platform yet, desktop included. The opening paragraph
  and the advice in "Which BLAKE3 package" say so.
- A `build/` directory would have been published. The root `.pubignore` shadowed
  the root `.gitignore` for the tree, so nothing that file excludes was being
  kept out of the archive; a dry-run with a `build/` directory present listed
  its files. 1.1.0 shipped clean only because no such directory existed when it
  was published. The rule moved to `doc/.pubignore`, which keeps the blog images
  out without disabling anything else.
- `description` is a literal block rather than a folded one, matching the
  screenshot caption. A folded block joins its lines with a space, which is how
  a wrapped "One-shot" once reached pub.dev as "One- shot".

## 1.1.0

- **Add `blake3Hash`, BLAKE3 as a `package:crypto` `Hash`.** `blake3(bytes)`
  was already the shortest way to hash here, so this is not for that. It is for
  the call sites you do not own: a checksum helper, a content-addressed cache
  or an `Hmac` that takes a `Hash` parameter can now be handed BLAKE3 without
  changing shape. `blockSize` is 64, matching SHA-256, so `Hmac` pads
  correctly; `startChunkedConversion` streams through a `Blake3Hasher` and
  releases it on close; and one-shot `convert` is overridden to skip the sink.
  A test pins the two paths against `blake3()` — a `Hash` view that drifted
  from the direct call would quietly be a different algorithm. Nine tests
  cover it, and each of five deliberate defects in the new code turns the
  suite red.
- `crypto` moves from a dev dependency to a dependency, since the `Hash` type
  is now part of this package's surface. It is pure Dart and already resolved
  in most trees.

## 1.0.2

- Add `example/README.md` for pub.dev's Example tab (it was empty). It walks
  through the four things the package does — one-shot hash, streaming file hash,
  keyed MAC, key derivation — with the example's real output. Docs only.

## 1.0.1

- Fix the bulk benchmark's 1 MB row, which was a measurement artifact rather
  than a real number. `bench/bench.dart` hashed a flat four iterations per size,
  so the 1 MB case timed only a few megabytes — too little to average out
  scheduling jitter, and its throughput swung roughly 2x from run to run while
  16 MB and 64 MB were steady. The benchmark now scales the iteration count so
  every size hashes a comparable total volume, and 1 MB lands near 14x like the
  larger sizes, not the 7.2x the README used to show. Benchmark and docs only;
  no library change.

## 1.0.0

First stable release. The public API is now committed to semantic versioning:
the hashing functions, `Blake3Hasher`, and the `blake3KeyLength` /
`blake3OutLength` constants will not change in a breaking way without a 2.0.0.
The package covers all three BLAKE3 modes (hash, keyed, and key derivation),
extendable output through `finalize(outputLength:, seek:)`, and one-shot,
incremental, and streaming hashing, all over the official BLAKE3 C sources
compiled from a build hook.

- `blake3HexStream` remains as a deprecated alias for `blake3StreamHex` (the
  0.4.0 rename) and now points at removal in 2.0.0 rather than 1.0.0, so code
  written against 0.4.0 keeps working across the 1.0.0 boundary.

## 0.4.0

- Rename `blake3HexStream` to `blake3StreamHex` so the hex variant is a `Hex`
  suffix on its base name, matching every other pair in the API: `blake3` and
  `blake3Hex`, `blake3Keyed` and `blake3KeyedHex`, `blake3DeriveKey` and
  `blake3DeriveKeyHex`. `blake3HexStream` still works as a deprecated alias
  that forwards to `blake3StreamHex`, and will be removed in 1.0.0.

## 0.3.1

- Declare `platforms: {linux, macos, windows}` in `pubspec.yaml`. Flutter's
  build-hooks support isn't stable yet and this package has no Android/iOS
  build today; pub.dev had inferred support for all five platforms from
  static analysis alone with no declaration to override it.

## 0.3.0

- `Blake3Hasher.update` now takes a `List<int>` instead of a `Uint8List`.
  Chunks from a `Stream<List<int>>` (a file's `openRead()`, a socket) arrive
  as plain `List<int>`, so the documented manual streaming loop did not
  compile without wrapping every chunk in `Uint8List.fromList`. A `Uint8List`
  still passes through with no copy; any other list is copied once, the same
  coercion `blake3Stream` already does. Source-compatible: `Uint8List` is a
  `List<int>`.

## 0.2.2

- Widen the native-toolchain constraints so the package can be installed in a
  Flutter app at all. `hooks` 2.1.0 and `native_toolchain_c` 0.19.3 raised their
  `meta` floor to ^1.19.0, and Flutter's SDK pins `meta` to 1.17.0, so
  `flutter pub add` failed at version solving with "flutter from sdk is
  incompatible". Allowing `hooks >=2.0.2` and `native_toolchain_c >=0.19.2`
  lets the solver pick a version that works with the pinned `meta`, while a
  pure-Dart project still resolves to the newest. No API or behaviour change.

## 0.2.1

- Declare the benchmark chart in `pubspec.yaml` so pub.dev renders it on the
  package page. The chart was already in the repository and the README, but
  pub.dev shows only what the `screenshots:` field points at, so the page a
  reader lands on from search opened with text where the measurement should
  have been.

## 0.2.0

- Add `blake3Stream` and `blake3HexStream`: one call to hash a
  `Stream<List<int>>` (a file's `openRead()`, an upload, any byte stream) as it
  arrives, without holding the whole input in memory. Each drives a
  `Blake3Hasher` internally and disposes it when the stream ends. This is the
  memory-safe way to hash something too large to load at once, and unlike a
  SHA-256 stream from `package:crypto` it runs at BLAKE3's throughput. The
  `outputLength` (XOF) argument carries through.

## 0.1.2

- Add hex variants for the raw-output paths: `blake3KeyedHex`, `blake3DeriveKeyHex`,
  and `Blake3Hasher.finalizeHex`. Keyed, derived, and streamed digests now format
  to hex the way `blake3Hex` already does, so callers stop re-implementing it (the
  example used to).

## 0.1.1

- Docs: sharpen the pub.dev description to lead with the value and the terms people search.

## 0.1.0

Initial release, vendoring the official BLAKE3 C implementation 1.8.5.

- One-shot hashing: `blake3`, `blake3Hex`.
- Streaming hashing: `Blake3Hasher` with `update`, `finalize`, `reset`,
  and `dispose`.
- Keyed hashing (MAC/PRF): `blake3Keyed`, `Blake3Hasher.keyed`.
- Key derivation (KDF): `blake3DeriveKey`, `Blake3Hasher.deriveKey`.
- Extendable output (XOF) via `outputLength` and `seek`.
- Native code builds automatically via Dart build hooks (Dart 3.10+); no
  manual native setup. arm64 uses the NEON kernel; other architectures use
  the portable C kernel.
- Verified against the official BLAKE3 test vectors (default, keyed, and
  derive-key modes, extended output, and streaming).
