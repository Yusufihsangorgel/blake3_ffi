// Minimal C shim over the vendored BLAKE3 reference implementation.
//
// The Dart side binds the BLAKE3 C API (blake3_hasher_init, _update,
// _finalize, ...) directly, but it needs to allocate the opaque
// blake3_hasher struct without hardcoding its size or internal layout.
// This exposes sizeof(blake3_hasher) so the Dart allocator stays correct
// across BLAKE3 versions.

#include <stddef.h>

#include "third_party/blake3/blake3.h"

// The BLAKE3 headers already mark their own entry points exported
// (visibility("default") on ELF/Mach-O, __declspec(dllexport) on Windows
// when BLAKE3_DLL/BLAKE3_DLL_EXPORTS are defined by the build hook). This
// shim symbol needs the same treatment so @Native can resolve it.
#if defined(_WIN32) || defined(__CYGWIN__)
#define B3_EXPORT __declspec(dllexport)
#elif defined(__GNUC__)
#define B3_EXPORT __attribute__((visibility("default")))
#else
#define B3_EXPORT
#endif

B3_EXPORT size_t blake3_ffi_hasher_size(void) { return sizeof(blake3_hasher); }
