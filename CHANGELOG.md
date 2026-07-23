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
