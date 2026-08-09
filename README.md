# blake3_ffi

![blake3_ffi banner](https://raw.githubusercontent.com/Yusufihsangorgel/blake3_ffi/main/doc/banner.png)

Fast BLAKE3 cryptographic hashing for Dart, backed by the official BLAKE3
C implementation over FFI. The native code is compiled automatically at
build time through Dart build hooks; there is nothing to install and no
prebuilt binary to ship.

- One-shot hashing of a byte buffer.
- Incremental (streaming) hashing for data that arrives in pieces or does
  not fit in memory, either through `Blake3Hasher` or the one-call
  `blake3Stream` over a `Stream<List<int>>`.
- Keyed hashing (a MAC / PRF) and key derivation (KDF).
- Extendable output (XOF): request any number of output bytes.

Dart also has a pure-Dart BLAKE3. On a 16 MiB buffer this package ran at 22x its
throughput, for the same digest, and gave up everything but the Dart VM on
desktop to get there: no web, and no Flutter yet on any platform.
[Which one to take](#which-blake3-package).

```dart
import 'dart:convert';
import 'package:blake3_ffi/blake3_ffi.dart';

void main() {
  // One-shot, as a hex string.
  print(blake3Hex(utf8.encode('hello')));

  // Streaming: feed chunks, then finalize.
  final hasher = Blake3Hasher();
  try {
    hasher.update(utf8.encode('hel'));
    hasher.update(utf8.encode('lo'));
    final digest = hasher.finalize(); // Uint8List, 32 bytes.
    print(digest.length);
  } finally {
    hasher.dispose();
  }
}
```

## Hashing a file or stream

To hash something too large to load at once, pass its byte stream to
`blake3Stream` (or `blake3StreamHex`). It drives a `Blake3Hasher` for you and
disposes it when the stream ends, so the input is never held in memory all at
once:

```dart
import 'dart:io';
import 'package:blake3_ffi/blake3_ffi.dart';

Future<String> hashFile(String path) =>
    blake3StreamHex(File(path).openRead());
```

This is the same job as binding a `Stream` to a `crypto` SHA-256 sink, but it
runs at BLAKE3's throughput, which is where the win over SHA-256 is largest (see
below).

## What BLAKE3 is, and why native

BLAKE3 is a modern cryptographic hash function. It is a tree hash: a single
input is split into chunks that can be compressed independently. On top of
that, its compression function maps cleanly onto SIMD instructions, which lets
one core hash several chunks at once. Those instructions are what a pure-Dart
implementation cannot reach, and that is where the throughput gap on bulk data
comes from. This package compiles the reference C implementation and, on arm64,
its NEON kernel.

BLAKE3 is not a password hash. For passwords use a memory-hard function
(Argon2, scrypt). BLAKE3 is for content addressing, deduplication,
integrity checks, MACs, and key derivation.

## Which BLAKE3 package

Dart has two. [`blake3_dart`][blake3_dart] is pure Dart: no toolchain, and it
runs everywhere Dart does, web and Flutter mobile included. This package
compiles the reference C instead. That buys throughput and costs reach: it
needs a C compiler at build time and targets Linux, macOS and Windows on the
Dart VM. Flutter is out on every platform until build hooks are stable there.

At 16 MiB on an Apple M4 Pro, this package hashed 2226 MB/s against 100 MB/s for
the pure-Dart path (blake3_dart 1.0.0): a factor of 22. Both return the same
digest, and `bench/bench.dart` verifies that before it times anything.

Take the pure-Dart package if you need web, mobile, or any Flutter app today,
or if a build-time C toolchain is not something you want in your pipeline. Take
this one for bulk hashing on desktop and server, where that gap is the whole
point.

[blake3_dart]: https://pub.dev/packages/blake3_dart

## Performance, honestly

`bench/bench.dart` measures, and writes `doc/benchmark.json`. The two tables
below are written from that file by `tool/readme_tables.dart`, and the chart by
`tool/benchmark_svg.dart`. `test/published_numbers_test.dart` compares the
generated block against a fresh render, and looks for the headline figures
wherever they are still typed by hand: the opening paragraph, "Which BLAKE3
package", the pubspec description and screenshot caption, and
`doc/benchmark.svg`. Your own numbers will differ by machine and architecture;
run the benchmark on your data before drawing conclusions.

![BLAKE3 throughput against pure Dart and SHA-256](https://raw.githubusercontent.com/Yusufihsangorgel/blake3_ffi/main/doc/benchmark.png)

![Architecture: Dart to FFI to native BLAKE3](https://raw.githubusercontent.com/Yusufihsangorgel/blake3_ffi/main/doc/architecture.png)

<!-- benchmark:begin -->
Measured on Apple M4 Pro, macOS 26.3 (Build 25D125), Dart 3.11.0, against
blake3_dart 1.0.0 and crypto 3.0.7. Each figure is the fastest of 5 batches in
the fastest of 3 placements. Input sizes are powers of two, so 1 MiB is
1,048,576 bytes; throughput is decimal, so 1 MB/s is 1,000,000 bytes per second.

Bulk throughput, MB/s:

| Input | this package | blake3_dart 1.0.0 | crypto 3.0.7 SHA-256 | vs pure Dart | vs SHA-256 |
|---|---|---|---|---|---|
| 1 MiB | 2221 | 100 | 166 | 22.2x | 13.4x |
| 16 MiB | 2226 | 100 | 167 | 22.2x | 13.3x |
| 64 MiB | 2253 | 101 | 167 | 22.2x | 13.5x |

Small inputs, microseconds per call including FFI overhead:

| Input | this package | blake3_dart 1.0.0 | crypto 3.0.7 SHA-256 | vs pure Dart | vs SHA-256 |
|---|---|---|---|---|---|
| 64 B | 0.19 | 0.67 | 0.88 | 3.5x | 4.6x |
| 256 B | 0.33 | 2.47 | 2.02 | 7.5x | 6.1x |
| 1 KiB | 0.94 | 9.59 | 6.57 | 10.2x | 7.0x |
| 4 KiB | 2.01 | 40.14 | 24.86 | 20.0x | 12.4x |
<!-- benchmark:end -->

Bulk throughput is flat from 1 MiB up. The 64-byte row is an upper bound on
what a call costs before any hashing happens, and a 1 MiB call costs three
orders of magnitude more. These rows measure the kernel rather than the call.

There is no small-input crossover where the FFI call cost takes the win back:
even at 64 bytes, where that cost is most of the work, the native path stays
ahead. The margin then widens with size, which is where the SIMD tree hashing
pays off.

Two caveats. Ordering barely mattered here: the spread across the three
placements was under 0.6% at 16 MiB, and `doc/benchmark.json` records it per
row. Absolute throughput still tracks machine state, which makes the ratios the
durable part. And this is one arm64 machine, where the NEON kernel is compiled
in; on x86-64 the portable C kernel runs instead (see
[Platform support](#platform-support)) and these figures do not carry over.

## Keyed hashing and key derivation

Keyed mode turns BLAKE3 into a MAC or PRF. The key must be exactly 32
bytes.

```dart
final key = Uint8List(32); // a real, secret 32-byte key
final tag = blake3Keyed(key, utf8.encode('message'));
```

Key-derivation mode produces subkeys from input keying material, separated
by a hardcoded context string. The context should be application-specific
and globally unique; do not let it be attacker-controlled.

```dart
final subkey = blake3DeriveKey(
  'example.com 2026 session cookie v1',
  masterSecret,
);
```

Both modes are also available on `Blake3Hasher` for streaming input:
`Blake3Hasher.keyed(key)` and `Blake3Hasher.deriveKey(context)`.

## Extendable output (XOF)

BLAKE3 produces an unbounded output stream; the default 32 bytes are just
its start. Pass `outputLength` for more, and `seek` to skip into the
stream. Extending never changes earlier bytes.

```dart
final long = blake3(data, outputLength: 64);   // 64 bytes
final tail = Blake3Hasher()
  ..update(data);
// tail.finalize(seek: 32, outputLength: 32) == long bytes 32..63
```

`example/xof.dart` runs that comparison and checks it over every byte, then
reads a cipher key, a MAC key and a short key id out of one derive-key pass.

## Dropping into code that takes a `Hash`

`blake3(bytes)` is the direct way to hash here and it stays the shortest one.
The case this section is about is different: code you did not write that takes
a `package:crypto` `Hash`, such as a checksum helper, a content-addressed cache
or an `Hmac`. `blake3Hash` is BLAKE3 wearing that interface, which lets those
call sites change algorithm without changing shape.

```dart
import 'package:blake3_ffi/blake3_ffi.dart';
import 'package:crypto/crypto.dart';

Digest checksum(List<int> bytes, {Hash algorithm = sha256}) =>
    algorithm.convert(bytes);

checksum(bytes, algorithm: blake3Hash); // same function, faster hash
```

It behaves the way the interface expects: `blockSize` is 64, the same as
SHA-256, which is what `Hmac` needs to pad correctly; `startChunkedConversion`
streams through a `Blake3Hasher` and releases it on close; and one-shot
`convert` skips the sink entirely. `Digest` holds 32 bytes, which is BLAKE3's
default; for the longer outputs BLAKE3 can produce, call `blake3` with
`outputLength` instead.

The digest is the same either way, and a test pins that: if the `Hash` view and
`blake3()` ever disagreed, the view would quietly be a different algorithm.

## API notes

- `finalize()` does not consume the hasher: you may keep calling `update`
  and `finalize`, and `reset()` returns it to its initial state (keeping
  the key/mode) so one hasher can hash many independent inputs.
- `dispose()` frees the small native hasher buffer. A finalizer also frees
  forgotten hashers at garbage collection, but that memory is invisible to
  the Dart heap, so prefer explicit disposal. Using a hasher after
  `dispose()` throws `StateError`.
- Digests are returned as `Uint8List`; `blake3Hex` returns lowercase hex.

## Shipping a standalone binary

`dart compile exe` does not run build hooks, so a program that depends on this
package stops before it starts:

```
$ dart compile exe bin/my_cli.dart
'dart compile' does not support build hooks, use 'dart build' instead.
```

`dart build cli` runs the hook and lays the pieces out for you:

```
$ dart build cli
Generated: build/cli/<os>_<arch>/bundle/bin/my_cli
$ ls build/cli/macos_arm64/bundle/*
bin/  my_cli
lib/  libblake3_ffi.dylib
```

Ship the whole `bundle/` directory. The executable resolves its library through
a relative `../lib` path, so a copy of the binary on its own fails at the first
call:

```
Failed to load dynamic library '../lib/libblake3_ffi.dylib'
```

`dart build cli` takes no positional target. With one file under `bin/` the bare
command is enough; with more than one, pass `-t`. `dart run` and `dart test` are
unaffected, since both run the hook already. The command is marked preview in
Dart 3.11.

## Platform support

Requires Dart 3.10+ with build hooks (`dart run`, `dart test`, and
`dart build` compile the C automatically; a C toolchain must be present:
Xcode CLT, gcc/clang, or MSVC).

Supported platforms are the desktop targets the pubspec declares: Linux,
macOS, and Windows on the Dart VM. The rows below describe which CPU
architecture uses which kernel, not additional platforms.

| Architecture | Kernel in this release | Status |
|---|---|---|
| arm64 (macOS, Linux) | NEON SIMD | Developed and tested on macOS arm64; CI covers macOS arm64 |
| x86-64 (Linux, macOS, Windows) | Portable C | Correct (passes the official vectors); CI covers Linux and Windows x64 |

Correctness is identical on both paths: every target passes the official
BLAKE3 test vectors. The difference is throughput. The x86-64 SIMD kernels
(SSE2/SSE4.1/AVX2/AVX512) are vendored in `src/third_party/blake3/` but not
yet compiled, because they need per-source compiler flags the build system
cannot express per file today; enabling them is planned for a later
release. There is no Flutter, iOS, or Android support yet; it arrives when
build hooks land in stable Flutter.

## Correctness

The package is verified against the
[official BLAKE3 test vectors][vectors]: all 35 cases, in the default,
keyed, and derive-key modes, checking both the 32-byte digest and the
extended (131-byte) output, plus streaming-equals-one-shot for every case.
Correctness is the reason this package exists; if a vector did not match,
there would be no package.

[vectors]: https://github.com/BLAKE3-team/BLAKE3/tree/master/test_vectors

## Credits and licenses

This package is MIT licensed (see `LICENSE`). It vendors the official
[BLAKE3](https://github.com/BLAKE3-team/BLAKE3) C implementation (version
1.8.5), which is released into the public domain via CC0 1.0 or, at your
option, under Apache 2.0. The upstream license texts and a `NOTICE` are in
`src/third_party/blake3/`. BLAKE3 was designed by Jack O'Connor, Jean-Philippe
Aumasson, Samuel Neves, and Zooko Wilcox-O'Hearn.
