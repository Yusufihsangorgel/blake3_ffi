# blake3_ffi

![blake3_ffi banner](https://raw.githubusercontent.com/Yusufihsangorgel/blake3_ffi/main/doc/banner.png)

Fast BLAKE3 cryptographic hashing for Dart, backed by the official BLAKE3
C implementation over FFI. The native code is compiled automatically at
build time through Dart build hooks; there is nothing to install and no
prebuilt binary to ship.

- One-shot hashing of a byte buffer.
- Incremental (streaming) hashing for data that arrives in pieces or does
  not fit in memory.
- Keyed hashing (a MAC / PRF) and key derivation (KDF).
- Extendable output (XOF): request any number of output bytes.

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

## What BLAKE3 is, and why native

BLAKE3 is a modern cryptographic hash function. It is a tree hash, so a
single input is split into chunks that can be compressed independently.
On top of that, its compression function maps cleanly onto SIMD
instructions, which lets one core hash several chunks at once. A pure-Dart
implementation cannot reach those instructions, so the throughput gap is
large on bulk data. This package compiles the reference C implementation
and, on arm64, its NEON kernel, so you get that throughput from Dart.

BLAKE3 is not a password hash. For passwords use a memory-hard function
(Argon2, scrypt). BLAKE3 is for content addressing, deduplication,
integrity checks, MACs, and key derivation.

## Performance, honestly

Measured with `bench/bench.dart` on an Apple M4 Pro (macOS 26.3, arm64
NEON, Dart 3.11.0, Apple clang 21). The baseline is SHA-256 from the
`crypto` package, the usual pure-Dart choice today. Your numbers will
differ by machine and architecture; run the benchmark on your own data
before drawing conclusions.

![BLAKE3 throughput vs sha256 and pure-Dart](https://raw.githubusercontent.com/Yusufihsangorgel/blake3_ffi/main/doc/benchmark.png)

![Architecture: Dart to FFI to native BLAKE3](https://raw.githubusercontent.com/Yusufihsangorgel/blake3_ffi/main/doc/architecture.png)

Bulk throughput:

| Input | BLAKE3 (this package) | SHA-256 (`crypto`) | Speedup |
|---|---|---|---|
| 1 MB | 1329 MB/s | 184 MB/s | 7.2x |
| 16 MB | 2519 MB/s | 181 MB/s | 13.9x |
| 64 MB | 2490 MB/s | 177 MB/s | 14.0x |

Small inputs (time per call, including FFI overhead):

| Input | BLAKE3 | SHA-256 | Speedup |
|---|---|---|---|
| 64 B | 0.17 µs | 0.81 µs | 4.7x |
| 1 KB | 0.86 µs | 6.23 µs | 7.2x |
| 4 KB | 1.79 µs | 23.6 µs | 13.2x |

The win holds at every size measured here, so there is no small-input
crossover where the FFI call cost dominates. The largest wins are on bulk
data, which is where BLAKE3's SIMD tree hashing pays off.

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

## API notes

- `finalize()` does not consume the hasher: you may keep calling `update`
  and `finalize`, and `reset()` returns it to its initial state (keeping
  the key/mode) so one hasher can hash many independent inputs.
- `dispose()` frees the small native hasher buffer. A finalizer also frees
  forgotten hashers at garbage collection, but that memory is invisible to
  the Dart heap, so prefer explicit disposal. Using a hasher after
  `dispose()` throws `StateError`.
- Digests are returned as `Uint8List`; `blake3Hex` returns lowercase hex.

## Platform support

Requires Dart 3.10+ with build hooks (`dart run`, `dart test`, and
`dart build` compile the C automatically; a C toolchain must be present:
Xcode CLT, gcc/clang, or MSVC).

| Target | Kernel in this release | Status |
|---|---|---|
| arm64 (macOS, Linux, iOS, Android) | NEON SIMD | Developed and tested on macOS arm64; CI covers macOS arm64 |
| x86-64 (Linux, macOS, Windows) | Portable C | Correct (passes the official vectors); CI covers Linux and Windows x64 |

Correctness is identical on both paths: every target passes the official
BLAKE3 test vectors. The difference is throughput. The x86-64 SIMD kernels
(SSE2/SSE4.1/AVX2/AVX512) are vendored in `src/third_party/blake3/` but not
yet compiled, because they need per-source compiler flags the build system
cannot express per file today; enabling them is planned for a later
release. Flutter support arrives when build hooks land in stable Flutter.

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
