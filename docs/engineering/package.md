# Package engineering rules: blake3_ffi

Rules-Version: blake3_ffi/73e3baba35632ba9b57544ad7ad03f4a4fdc192a4185c393cdbd8af399110d3b
Core-Version: 1
Core-Digest: 1825fa7ff346dca23e65b1b3bf9b2e3e06959f1414bae9952d596d2f62f09b8f
Survey-Digest: f90f45c8a172068c3ed3b9488ba5a7cb4e58efa93c380d2d9a70b399349ec35e
Evidence-Revision: 32494b8
Verified-Revision: unverified

Read CONTRIBUTING.md and docs/engineering/debt.json before editing.

## Current architecture
HEAD 32494b8 (1.2.5). A small FFI package wrapping vendored BLAKE3 C (1.8.5). Its layers form no cycle. `bindings.dart` carries the FFI declarations, memory helpers, the opaque struct size read from the shim, and the finalizer pointer. `hasher.dart` holds `Blake3Hasher` (Finalizable, dispose, reset, XOF seek) and the shared `updateHasher`/`finalizeHasher` helpers. `functions.dart` is the one-shot, keyed, KDF, and Stream API. The hot path uses try/finally without a finalizer. `crypto_hash.dart` is the `package:crypto` `Hash` adapter. `hex.dart` produces the shared lowercase hex. The hook picks the kernel for the architecture: NEON on arm64 and portable code elsewhere. x86 SIMD is vendored but not compiled. Documentation numbers come from doc/benchmark.json and are pinned by a test.

## Layers and responsibilities
- lib/blake3_ffi.dart: Only `export ... show` (lines 15-27).
- lib/src/crypto_hash.dart: `Blake3Hash`/`blake3Hash` (package:crypto Hash) and `_Blake3Sink` chunked conversion.
- lib/src/functions.dart: blake3/Hex/Keyed/DeriveKey/Stream; the `_oneShot` skeleton; the @Deprecated alias.
- lib/src/hasher.dart: `Blake3Hasher`, `blake3KeyLength`/`blake3OutLength`, `updateHasher`, `finalizeHasher`.
- lib/src/hex.dart: `toHex` lowercase hex.
- lib/src/bindings.dart: 7 `@Native`, `hasherSize`, `allocateBytes`/`freeBytes`, `freeFunction` (malloc.nativeFree).
- src/blake3_shim.c, src/third_party/blake3/: A 25-line shim (`B3_EXPORT`, `blake3_ffi_hasher_size`); vendored BLAKE3 C.
- hook/build.dart: Early return on `buildCodeAssets`; arm64 NEON, others portable plus `BLAKE3_NO_*`.
- bench/, tool/, doc/benchmark.json: Benchmark, README table, and SVG generation.
- test/ (+ test_vectors.json): Official vectors, lifecycle, stream, crypto adapter, published numbers, hook.

## Public API and dependency direction
Functions: blake3, blake3Hex, blake3Keyed, blake3KeyedHex, blake3DeriveKey, blake3DeriveKeyHex, blake3Stream, blake3StreamHex, blake3HexStream (@Deprecated, to be removed in 2.0.0). All take `outputLength` (default 32, XOF). Types: Blake3Hasher (factory (), .keyed, .deriveKey; update(List<int>), finalize({outputLength, seek}), finalizeHex, reset, dispose, isDisposed), Blake3Hash, and the `blake3Hash` constant. Constants: blake3KeyLength, blake3OutLength. The boundary is lib/blake3_ffi.dart:15-27.

blake3_ffi.dart -> {functions, crypto_hash, hasher}. crypto_hash -> functions, hasher, package:crypto. functions -> bindings, hasher, hex. hasher -> bindings, hex. bindings -> dart:ffi, package:ffi. hex -> dart:typed_data. No cycle. package:crypto stays in the adapter layer only. Only bindings touches native code.

## Error, state and platform contracts
- Resource-owning type: `final class ... implements Finalizable`, `_finalizer.attach(this, ptr, detach: this)` in a private constructor, idempotent `dispose()` (detach + free + nullptr), `isDisposed`, `_checkNotDisposed()` -> StateError (hasher.dart:36-39, 91-97, 141-155).
- One-shot hot path without a finalizer: try/finally for a native object with a lifetime bounded by the call (functions.dart:85-102).
- Memory goes through `allocateBytes` (at least 1 byte) / `freeBytes` on package:ffi `malloc`. There is no `@Native` binding to the C runtime. The reason is Windows symbol lookup (bindings.dart:5-10, 68-74).
- The opaque struct size is read from the shim (`blake3_ffi_hasher_size`). The layout is not pinned in Dart (bindings.dart:59-66).
- Errors: only `ArgumentError.value` (key of 32 bytes, negative outputLength/seek) and `StateError` (after dispose). There is no dedicated exception type.
- The `*Hex` variants are thin wrappers over the base function with a single `toHex` (hex.dart:5-15).
- Streams: `await for` plus try/finally dispose (functions.dart:117-130). The chunked sink is a no-op on a second `close` (crypto_hash.dart:80-91).
- Renaming is done with a `@Deprecated('Use X instead. Will be removed in 2.0.0.')` wrapper (functions.dart:142-149).
- Published-number discipline: doc/benchmark.json -> tool/readme_tables.dart + tool/benchmark_svg.dart. test/published_numbers_test.dart fails on drift.
- pubspec comments state the reason for every dependency and every platform declaration (pubspec.yaml:30-42, 45-47).
- Global state is only `final`/`const` (hasherSize, freeFunction, NativeFinalizer, constants).
- Documentation layout: AGENTS.md targets users (Usage/Contracts/Mistakes/Layout).

## Package rules
### blake3_ffi/B3-01 [MUST]
The public API is exposed only through the `export ... show` lists in `lib/blake3_ffi.dart`; src helpers such as `updateHasher`, `finalizeHasher`, `allocateBytes` and `toHex` are not exported.
Reason: The show list is the only guard keeping the public helpers inside src from leaking.
Evidence: lib/blake3_ffi.dart:15-27
Evidence role: current-pattern
Existing violation: none

### blake3_ffi/B3-02 [MUST]
A public type that holds a native resource is `final class ... implements Finalizable`: `NativeFinalizer.attach(..., detach: this)` in a private constructor, an idempotent `dispose()` (detach first, then free, then a nullptr pointer), an `isDisposed` getter; every operation after dispose throws `StateError`.
Reason: Forgotten objects must not leak and double frees must not happen; the current single resource-owning type follows this pattern.
Evidence: lib/src/hasher.dart:36-39, 91-97, 141-155
Evidence role: current-pattern
Existing violation: none

### blake3_ffi/B3-03 [MUST]
A native object with a lifetime limited to a single call is not attached to a finalizer; it is freed with try/finally.
Reason: Avoid finalizer cost on the one-shot hot path.
Evidence: lib/src/functions.dart:85-102
Evidence role: current-pattern
Existing violation: none

### blake3_ffi/B3-04 [MUST_NOT]
C runtime `malloc`/`free` are not bound with `@Native`; native memory is taken only through `allocateBytes`/`freeBytes` (package:ffi, at least 1 byte).
Reason: C runtime symbol lookup does not resolve on Windows; malloc(0) may return null.
Evidence: lib/src/bindings.dart:5-10, 68-74
Evidence role: current-pattern
Existing violation: none

### blake3_ffi/B3-05 [MUST]
The size or layout of the opaque native struct is not fixed in Dart; it is read from the shim.
Reason: The Dart side must not silently allocate the wrong size when the vendored C version changes.
Evidence: lib/src/bindings.dart:59-66; src/blake3_shim.c
Evidence role: current-pattern
Existing violation: none

### blake3_ffi/B3-06 [MUST]
Inside `lib/`, hex output is produced only by `toHex` (lowercase); every hex variant is a thin wrapper named `<taban>Hex`.
Reason: A single formatting path; one name was already changed in 1.x for naming consistency.
Evidence: lib/src/hex.dart:5-15; lib/src/functions.dart:18-20, 49-54, 78-83, 132-149
Evidence role: current-pattern
Existing violation: none

### blake3_ffi/B3-07 [MUST]
Parameter errors are `ArgumentError.value(value, 'name', message)`; lifecycle errors are `StateError`; no new custom exception type is introduced.
Reason: Native calls do not fail; the error space is limited to two classes and is documented with exact messages in the AGENTS.md 'Mistakes' section.
Evidence: lib/src/functions.dart:31-37; lib/src/hasher.dart:53-59, 151-155, 177-186; AGENTS.md:80-92
Evidence role: current-pattern
Existing violation: none

### blake3_ffi/B3-08 [MUST]
On a public rename, the old name stays as a wrapper that delegates to the new name with `@Deprecated('Use X instead. Will be removed in <major>.')`.
Reason: Breaking changes are deferred to a major release and the removal is tracked.
Evidence: lib/src/functions.dart:142-149
Evidence role: current-pattern
Existing violation: none

### blake3_ffi/B3-09 [MUST]
Performance numbers in the README and pubspec come from doc/benchmark.json; a diff that changes a number or a measurement runs the tool/ generators and keeps test/published_numbers_test.dart green.
Reason: This test exists because of a measured incident where three documents carried three different numbers for the same line.
Evidence: pubspec.yaml:21-22; test/published_numbers_test.dart:1-8
Evidence role: current-pattern
Existing violation: none

### blake3_ffi/B3-10 [MUST]
Every diff touching the hash core, the hook's source/define selection or bindings passes test/test_vectors_test.dart (official vectors, streaming==one-shot, seek). test/test_vectors.json is not edited by hand.
Reason: The official vectors are the correctness proof; the NEON and portable kernels are matched against them.
Evidence: test/test_vectors_test.dart:30-115; hook/build.dart:20-21
Evidence role: current-pattern
Existing violation: none

### blake3_ffi/B3-11 [MUST]
The hook keeps the `buildCodeAssets` early return and selects the core per architecture: on arm64 `blake3_neon.c` + `BLAKE3_USE_NEON`, elsewhere portable code + `BLAKE3_NO_SSE2/SSE41/AVX2/AVX512`. Adding a SIMD core is done together with test vectors and the CI matrix.
Reason: Per-file flags for x86 SIMD cannot be expressed today; the packager must not reference an uncompiled kernel.
Evidence: hook/build.dart:8-21, 26-52
Evidence role: current-pattern
Existing violation: none

### blake3_ffi/B3-12 [MUST_NOT]
`package:crypto` is imported only in the `crypto_hash.dart` adapter; functions, hasher and bindings do not depend on it.
Reason: The dependency exists only for the `Hash` view; the core path must stay independent.
Evidence: pubspec.yaml:45-47; lib/src/crypto_hash.dart:4; lib/src/functions.dart:1-7; lib/src/hasher.dart:1-6
Evidence role: current-pattern
Existing violation: none

### blake3_ffi/B3-13 [SHOULD]
`platforms:` lists only linux/macos/windows, the ones CI runs; android/ios are not added without a real and tested build.
Reason: Prevent pana from inferring wrong mobile support from the import graph.
Evidence: pubspec.yaml:30-42
Evidence role: current-pattern
Existing violation: none

### blake3_ffi/B3-14 [MUST]
Package level contains only `const`/`final` fields (hasherSize, freeFunction, NativeFinalizer, constants); no mutable global state is added.
Reason: No shared mutable state across isolates; the current code follows this.
Evidence: lib/src/bindings.dart:66, 78; lib/src/hasher.dart:9, 12, 91
Evidence role: current-pattern
Existing violation: none

### blake3_ffi/B3-15 [MUST]
A new hash mode comes with two sides: an init helper and a factory in hasher.dart, and a one-shot function plus a `Hex` wrapper through `_oneShot` in functions.dart. The same init logic is not written separately in both files.
Reason: The current extension point; the current keyed/KDF duplication is in the debt register.
Evidence: lib/src/functions.dart:15-20, 85-102; lib/src/hasher.dart:41-89
Evidence role: both
Existing violation: blake3_ffi-D001

## Required verification
- Working directory: repository root; command: dart pub get; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:23.
- Working directory: repository root; command: dart format --output=none --set-exit-if-changed lib test bench example hook tool; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:24.
- Working directory: repository root; command: dart analyze --fatal-infos; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:25.
- Working directory: repository root; command: dart test; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:26.
Not verified by the survey:
- `dart analyze`/`dart test` were not run (read-only scope).
- The throughput effect of not compiling x86 SIMD was not measured.
- The claim that tool/ generator output is current with doc/benchmark.json was inferred only from the presence of a test. It was not run.
- Latest CI run status (no network).
- Whether the shim and vendored C are identical to upstream 1.8.5 (no network).

## Existing debt
The complete register is docs/engineering/debt.json.
- blake3_ffi-D001 | small | lib/src/functions.dart:31-46, 66-75 <-> lib/src/hasher.dart:52-69, 78-89 | duplicated logic
  Fix: Helpers in hasher.dart: `_checkKey`, `initKeyed(Pointer<Void>, Uint8List)`, `initDeriveKey(Pointer<Void>, String)`; both paths call them. The test vectors must pass unchanged.
  Closure: Both the one-shot functions and the factories obtain keyed and KDF initialization through shared _checkKey, initKeyed and initDeriveKey helpers in hasher.dart. test/test_vectors_test.dart passes unchanged.
- blake3_ffi-D002 | small | lib/src/functions.dart:124 | redundant code
  Fix: `hasher.update(chunk)`.
  Closure: lib/src/functions.dart passes chunk directly to hasher.update with no local Uint8List.fromList conversion.
- blake3_ffi-D003 | large | hook/build.dart:14-18; src/third_party/blake3/blake3_{sse2,sse41,avx2,avx512}.c | vendored dead source / deferred performance
  Fix: Enter it in the debt register. Compile when native_toolchain_c supports per-file flags or with separate static CBuilders; until then consider removing it from the published archive.
  Closure: The deferred x86 SIMD work is tracked in the debt register or the unused vendored kernels are removed from the published archive. A later compile of the kernels ships with test/test_vectors_test.dart green and x86 targets in the CI matrix.
- blake3_ffi-D004 | small | analysis_options.yaml:1 | analysis strictness
  Fix: Turn on the image_ffi settings and fix the resulting diagnostics.
  Closure: analysis_options.yaml enables strict-casts, strict-inference, strict-raw-types and public_member_api_docs and dart analyze reports no new diagnostics.
