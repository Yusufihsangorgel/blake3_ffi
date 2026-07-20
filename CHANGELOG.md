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
