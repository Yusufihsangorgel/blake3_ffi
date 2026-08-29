# blake3_ffi

Native BLAKE3 hashing for Dart: FFI to the vendored C (1.8.5) for one-shot,
streaming, keyed MAC, key derivation, and extendable output. `hook/build.dart`
compiles that C at `dart run`, `dart test`, and `dart build`; there is no
prebuilt binary.

Use SHA-256 from `package:crypto` when the digest must be SHA-256 (interop,
published checksums, compliance) or the program must run on web, Flutter, iOS,
or Android. This package is Linux, macOS, and Windows on the Dart VM only. Use
it there when SHA-256 is the bulk-hash bottleneck you measured, or you need
BLAKE3 keyed / KDF / XOF. At 16 MiB on an Apple M4 Pro, `doc/benchmark.json`
records 2226 MB/s here versus 167 MB/s for SHA-256 from crypto 3.0.7 (13.3x)
and 100 MB/s for blake3_dart 1.0.0; 64 B is 0.19 microseconds versus 0.88, so
there is no small-input crossover. The native dependency is not worth it for
SHA-256-shaped work or for Flutter, mobile, or web.

## Usage

Direct:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:blake3_ffi/blake3_ffi.dart';

Future<void> main() async {
  print(blake3Hex(utf8.encode('hello')));
  print(await blake3StreamHex(File('README.md').openRead()));
}
```

Drop-in through `package:crypto`'s `Hash`, so a call site you do not own can
swap the algorithm:

```dart
import 'dart:convert';

import 'package:blake3_ffi/blake3_ffi.dart';
import 'package:crypto/crypto.dart';

Digest checksum(List<int> bytes, {Hash algorithm = sha256}) =>
    algorithm.convert(bytes);

void main() {
  print(checksum(utf8.encode('hello'), algorithm: blake3Hash));
}
```

`blake3` / `blake3Hex` hash a `Uint8List`. `blake3StreamHex(File(path).openRead())`
hashes without holding the file. `blake3Hash.convert` returns a 32-byte `Digest`;
longer output is `blake3(..., outputLength: ...)`. Hex is lowercase.
`blake3Hash.blockSize` is 64, same as SHA-256.

## Contracts

- **`Blake3Hasher` lifecycle.** `update` (any `List<int>`), then `finalize` /
  `finalizeHex`. `finalize` does not consume the hasher: further `update` /
  `finalize` are valid. `reset` restores just-created state, keeping the key
  and mode. `dispose` frees the native hasher; after it, `update` / `finalize`
  / `reset` throw. A finalizer also frees forgotten hashers; still `dispose` in
  `finally`. `blake3Stream` / `blake3StreamHex` dispose for you. A `blake3Hash`
  chunked sink (`startChunkedConversion`) must be `close`d: `close` finalizes,
  emits the `Digest`, and disposes. `convert` does not need that.
- **Keyed hashing.** `blake3Keyed` and `Blake3Hasher.keyed` require
  `key.length == blake3KeyLength` (32). `Hmac(blake3Hash, key)` is HMAC, not
  keyed BLAKE3.
- **XOF.** `outputLength` defaults to `blake3OutLength` (32) and may be any
  non-negative int; 0 returns empty; this package enforces no upper bound.
  `Blake3Hasher.finalize(seek:, outputLength:)` reads a window of the same
  stream. Extending never changes earlier bytes. Negative `outputLength` or
  `seek` throws. `blake3Hash` cannot return more than 32 bytes.
- **Reuse after finishing.** `Blake3Hasher` is reusable after `finalize`, not
  after `dispose`. `Blake3Hash.convert` is reusable. The chunked sink is not
  reusable after `close`.

## Mistakes

- 16-byte (or any non-32) key to `blake3Keyed` / `Blake3Hasher.keyed`:
  `Invalid argument (key.length): BLAKE3 key must be exactly 32 bytes: 16`
  Pass exactly `blake3KeyLength` (32) bytes.
- `update` / `finalize` / `reset` after `dispose`:
  `Bad state: Blake3Hasher has been disposed`
  `dispose` last, in `finally`. Use `reset` to hash another independent input.
- `finalize(outputLength: -1)` or `finalize(seek: -1)`:
  `Invalid argument (outputLength): must not be negative: -1`
  `Invalid argument (seek): must not be negative: -1`
  Non-negative only.
- `add` on a `blake3Hash` sink after `close`:
  `Bad state: cannot add to a closed sink`
  Close once when input ends.
- `dart compile exe` of a program that depends on this compiles, then fails at
  the first hash:
  `Couldn't resolve native function 'blake3_ffi_hasher_size' in 'package:blake3_ffi/src/bindings.dart' : No asset with id 'package:blake3_ffi/src/bindings.dart' found. No available native assets.`
  Use `dart build cli` and ship the whole `bundle/` (native lib beside the binary).

## Layout

- `lib/blake3_ffi.dart` — public exports.
- `lib/src/functions.dart` — `blake3`, `blake3Hex`, `blake3Keyed`,
  `blake3DeriveKey`, `blake3Stream`, hex variants.
- `lib/src/hasher.dart` — `Blake3Hasher`, `blake3KeyLength`, `blake3OutLength`.
- `lib/src/crypto_hash.dart` — `Blake3Hash`, `blake3Hash`.
- `lib/src/bindings.dart` — FFI; hook asset id.
- `hook/build.dart` — `CBuilder.library(name: 'blake3_ffi')`; sources
  `src/blake3_shim.c` and `src/third_party/blake3/{blake3,blake3_dispatch,blake3_portable}.c`,
  plus `blake3_neon.c` on arm64. Other archs set `BLAKE3_NO_SSE2` / `SSE41` /
  `AVX2` / `AVX512` (x86 SIMD is vendored, not compiled).
- Tests: `dart test` from the repo root. CI also runs `dart analyze --fatal-infos`.
- Examples: `dart run example/blake3_ffi_example.dart`, `dart run example/xof.dart`.
- Numbers: `dart run bench/bench.dart` writes `doc/benchmark.json`.
- Needs Dart 3.10+ and a C toolchain (Xcode CLT, gcc/clang, or MSVC).
