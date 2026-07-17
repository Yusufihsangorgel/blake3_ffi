import 'dart:ffi';

// Bindings to the vendored BLAKE3 C API and to libc malloc/free. The
// native library is produced by hook/build.dart, which registers it under
// the asset id of this library (src/bindings.dart), so every @Native
// symbol below resolves to it.

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

/// Allocates [bytes] of native memory. Throws [StateError] when the
/// allocation fails.
Pointer<Uint8> allocateBytes(int bytes) {
  // malloc(0) may legally return null; always request at least one byte.
  final pointer = _mallocNative(bytes < 1 ? 1 : bytes);
  if (pointer == nullptr) {
    throw StateError('native allocation of $bytes bytes failed');
  }
  return pointer.cast<Uint8>();
}

/// Frees memory from [allocateBytes].
void freeBytes(Pointer<Uint8> pointer) => _freeNative(pointer.cast());

/// The address of libc `free`, used to release forgotten hashers from a
/// [NativeFinalizer].
final Pointer<NativeFinalizerFunction> freeFunction =
    Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(
      _freeNative,
    ).cast();

@Native<Pointer<Void> Function(IntPtr)>(symbol: 'malloc')
external Pointer<Void> _mallocNative(int size);

@Native<Void Function(Pointer<Void>)>(symbol: 'free')
external void _freeNative(Pointer<Void> pointer);
