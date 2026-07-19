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
