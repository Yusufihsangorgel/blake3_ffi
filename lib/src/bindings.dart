import 'dart:ffi';

import 'package:ffi/ffi.dart';

// Bindings to the vendored BLAKE3 C API. The native library is produced by
// hook/build.dart, which registers it under the asset id of this library
// (src/bindings.dart), so every @Native symbol below resolves to it.
// Native heap memory goes through the portable package:ffi allocator
// rather than a direct @Native binding to malloc/free: DynamicLibrary
// symbol lookup for the C runtime does not resolve on Windows.

/// Initializes a hasher for the default (unkeyed) hash.
@Native<Void Function(Pointer<Void>)>(symbol: 'blake3_hasher_init')
external void blake3HasherInit(Pointer<Void> self);

/// Initializes a hasher in keyed mode with a 32-byte key.
@Native<Void Function(Pointer<Void>, Pointer<Uint8>)>(
  symbol: 'blake3_hasher_init_keyed',
)
external void blake3HasherInitKeyed(Pointer<Void> self, Pointer<Uint8> key);

/// Initializes a hasher in key-derivation (KDF) mode from a context of
/// [contextLength] bytes.
@Native<Void Function(Pointer<Void>, Pointer<Uint8>, Size)>(
  symbol: 'blake3_hasher_init_derive_key_raw',
)
external void blake3HasherInitDeriveKeyRaw(
  Pointer<Void> self,
  Pointer<Uint8> context,
  int contextLength,
);

/// Feeds [inputLength] bytes of [input] into the hasher.
@Native<Void Function(Pointer<Void>, Pointer<Uint8>, Size)>(
  symbol: 'blake3_hasher_update',
)
external void blake3HasherUpdate(
  Pointer<Void> self,
  Pointer<Uint8> input,
  int inputLength,
);

/// Writes [outLength] bytes of output starting at extended-output offset
/// [seek]. BLAKE3 is an unbounded XOF; [seek] selects the window.
@Native<Void Function(Pointer<Void>, Uint64, Pointer<Uint8>, Size)>(
  symbol: 'blake3_hasher_finalize_seek',
)
external void blake3HasherFinalizeSeek(
  Pointer<Void> self,
  int seek,
  Pointer<Uint8> out,
  int outLength,
);

/// Resets the hasher to its post-init state, keeping the key/mode.
@Native<Void Function(Pointer<Void>)>(symbol: 'blake3_hasher_reset')
external void blake3HasherReset(Pointer<Void> self);

/// Returns `sizeof(blake3_hasher)` from the shim, so the Dart side can
/// allocate the opaque struct without hardcoding its layout.
@Native<Size Function()>(symbol: 'blake3_ffi_hasher_size')
external int blake3HasherSize();

/// The size in bytes of the native hasher struct, cached after the first
/// call.
final int hasherSize = blake3HasherSize();

/// Allocates [bytes] of native memory. Throws when the allocation fails.
Pointer<Uint8> allocateBytes(int bytes) =>
    // malloc(0) may legally return null; always request at least one byte.
    malloc.allocate<Uint8>(bytes < 1 ? 1 : bytes);

/// Frees memory from [allocateBytes].
void freeBytes(Pointer<Uint8> pointer) => malloc.free(pointer);

/// The native free function, used to release forgotten hashers from a
/// [NativeFinalizer].
final Pointer<NativeFinalizerFunction> freeFunction = malloc.nativeFree;
