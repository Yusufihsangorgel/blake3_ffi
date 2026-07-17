import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles the vendored BLAKE3 reference implementation and the shim into
/// a dynamic library at build time.
///
/// SIMD selection is per target architecture:
///
///   * arm64  -> the NEON kernel (blake3_neon.c). The upstream headers
///     auto-enable `BLAKE3_USE_NEON` on AArch64 only when the define is
///     absent; it is set explicitly here so the intent is visible and the
///     kernel source is compiled to match.
///   * everything else (x86_64, ...) -> the portable C kernel only. The
///     x86 SIMD kernels (SSE2/SSE4.1/AVX2/AVX512) need per-source compiler
///     flags that the build system cannot express per file yet, so they
///     are vendored but not compiled in this release. `BLAKE3_NO_*` keeps
///     the runtime dispatcher from referencing them.
///
/// The portable and NEON kernels both pass the official BLAKE3 test
/// vectors; the difference is throughput, not correctness.
void main(List<String> args) async {
  await build(args, (input, output) async {
    final architecture = input.config.code.targetArchitecture;
    final isArm64 = architecture == Architecture.arm64;

    final sources = <String>[
      'src/blake3_shim.c',
      'src/third_party/blake3/blake3.c',
      'src/third_party/blake3/blake3_dispatch.c',
      'src/third_party/blake3/blake3_portable.c',
      if (isArm64) 'src/third_party/blake3/blake3_neon.c',
    ];

    final defines = <String, String?>{
      // Export the BLAKE3 C ABI from the DLL on Windows; a no-op elsewhere,
      // where visibility("default") already exports the symbols.
      'BLAKE3_DLL': null,
      'BLAKE3_DLL_EXPORTS': null,
      if (isArm64)
        'BLAKE3_USE_NEON': '1'
      else ...{
        'BLAKE3_NO_SSE2': null,
        'BLAKE3_NO_SSE41': null,
        'BLAKE3_NO_AVX2': null,
        'BLAKE3_NO_AVX512': null,
      },
    };

    final builder = CBuilder.library(
      name: 'blake3_ffi',
      assetName: 'src/bindings.dart',
      sources: sources,
      defines: defines,
      language: Language.c,
    );
    await builder.run(input: input, output: output);
  });
}
