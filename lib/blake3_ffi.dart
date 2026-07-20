/// Fast BLAKE3 cryptographic hashing for Dart via native FFI.
///
/// The vendored BLAKE3 C implementation is compiled automatically at build
/// time through Dart build hooks; there is nothing to install.
///
/// - [blake3] / [blake3Hex] hash a byte buffer in one call.
/// - [Blake3Hasher] hashes incrementally (streaming).
/// - [blake3Keyed] / [Blake3Hasher.keyed] provide keyed hashing (MAC/PRF).
/// - [blake3DeriveKey] / [Blake3Hasher.deriveKey] provide key derivation.
///
/// All entry points accept an `outputLength` for BLAKE3's extendable
/// output (XOF); it defaults to 32 bytes.
library;

export 'src/functions.dart'
    show
        blake3,
        blake3DeriveKey,
        blake3DeriveKeyHex,
        blake3Hex,
        blake3HexStream,
        blake3Keyed,
        blake3KeyedHex,
        blake3Stream;
export 'src/hasher.dart' show Blake3Hasher, blake3KeyLength, blake3OutLength;
