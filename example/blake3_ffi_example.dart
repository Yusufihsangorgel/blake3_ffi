/// Verifying a download nobody watched arrive.
///
/// A release artifact is sitting on disk and the question is whether it is
/// the bytes the publisher meant to ship. That question has three parts, and
/// this file takes them in order: hash a file far larger than you want to
/// hold, look at what a single flipped bit does to the digest, and then ask
/// whether a digest is even the right tool once whoever tampered with the
/// file can also rewrite the digest published beside it.
///
/// Nothing here touches the network. The artifact is generated into a
/// temporary directory from a deterministic PRNG, so every run stages the
/// same 64 MB and prints the same digests, and the directory is removed on
/// the way out.
///
///     dart run example/blake3_ffi_example.dart
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:blake3_ffi/blake3_ffi.dart';

/// The read size for the streaming paths, and the block the artifact is
/// staged in. 64 KiB is also what `File.openRead()` hands out by default.
const int _chunkSize = 64 * 1024;

/// 1024 blocks of [_chunkSize], so the artifact is 64 MiB and the gap between
/// holding it and streaming it is a round number a reader can check.
const int _chunkCount = 1024;

Future<void> main() async {
  // Directory.systemTemp, not the repo: an example that writes into the
  // project it ships with is an example that dirties someone's checkout.
  final workspace = Directory.systemTemp.createTempSync('blake3_download_');
  final artifact = File('${workspace.path}/release.bin');
  try {
    // `dart run` writes its build-hook progress to stdout without a trailing
    // newline, so the first real line lands glued to it. One blank line costs
    // nothing and keeps the opening line readable.
    print('');
    _stage(artifact);
    final total = artifact.lengthSync();
    print(
      'staged ${_size(total)} to verify, '
      '$_chunkCount blocks of ${_size(_chunkSize)}',
    );
    print('');

    final digest = await _threeWays(artifact);
    print('');
    _oneFlippedBit(artifact, digest, total);
    print('');
    _digestVersusTag(artifact, digest);
    print('');
    print(
      'next: bench/bench.dart for throughput, '
      'example/xof.dart for reading past 32 bytes',
    );
  } finally {
    workspace.deleteSync(recursive: true);
  }
}

/// Hashes [artifact] three ways and returns the digest they agree on.
///
/// The one-shot call is the shortest thing to write and the reason to reach
/// for the other two is visible in the same table: it needs the whole file
/// resident first. This is the difference the package README claims over the
/// pure-Dart `blake3_dart`, whose exported API has no incremental entry
/// point, so here it is running rather than asserted.
Future<String> _threeWays(File artifact) async {
  // Way 1: read it all, hash it in one call.
  final bytes = artifact.readAsBytesSync();
  final oneShot = blake3Hex(bytes);
  final oneShotHeld = bytes.lengthInBytes;

  // Way 2: the one-liner from the package README. `openRead()` decides the
  // chunk size, so measure what it actually handed over rather than assuming.
  var streamHeld = 0;
  final streamed = await blake3StreamHex(
    artifact.openRead().map((chunk) {
      streamHeld = max(streamHeld, chunk.length);
      return chunk;
    }),
  );

  // Way 3: your own read loop, for code that already has one. One buffer,
  // reused for every block.
  final manual = _hashInChunks(artifact);

  print('hashing it three ways');
  print(
    '  blake3Hex(bytes)           '
    'held ${_size(oneShotHeld)}  ${_short(oneShot)}',
  );
  print(
    '  blake3StreamHex(openRead)  '
    'held ${_size(streamHeld)}  ${_short(streamed)}',
  );
  print(
    '  Blake3Hasher, own buffer   '
    'held ${_size(manual.held)}  ${_short(manual.digest)}',
  );

  // The hex above is truncated for width; this compares all 64 characters.
  _verify(
    'all three digests are identical',
    oneShot == streamed && streamed == manual.digest,
  );
  // Quote the larger of the two streaming buffers. openRead() picks its own
  // chunk size and is free to change it, so deriving the ratio from the loop's
  // buffer alone would state a number the row above it might not match.
  final streamingPeak = max(streamHeld, manual.held);
  print(
    '  neither streaming path held more than ${_size(streamingPeak)}, '
    '${(oneShotHeld / streamingPeak).toStringAsFixed(0)}x less than the file',
  );
  // updateHasher allocates a native buffer the size of whatever it is given,
  // so the one-shot path pays for the file twice and the loop pays 64 KiB.
  print('  the native copy is the size of the chunk, so is the gap there');
  return manual.digest;
}

/// Flips one bit in the middle of [artifact] and re-streams it.
///
/// The file keeps its length and still opens, which is what makes a silent
/// corruption worth a hash in the first place: nothing else about it looks
/// wrong. Counting how much of the digest moved is the point — BLAKE3 has no
/// notion of a small change.
void _oneFlippedBit(File artifact, String digest, int total) {
  final offset = total ~/ 2;
  _flipBit(artifact, offset);
  final tampered = _hashInChunks(artifact).digest;
  var moved = 0;
  for (var i = 0; i < digest.length; i++) {
    if (digest[i] != tampered[i]) moved++;
  }

  print('what one flipped bit does');
  print('  bit 0 of the byte at offset $offset of $total');
  print('  digest                     ${_short(tampered)}');
  print(
    '  $moved of ${digest.length} hex characters differ from the digest above',
  );

  // Flipping the same bit again restores the byte, so the digest has to come
  // back. If it does not, this example is measuring the wrong thing.
  _flipBit(artifact, offset);
  _verify(
    'flipping the bit back restores the original digest',
    _hashInChunks(artifact).digest == digest,
  );
}

/// Contrasts a digest with a keyed tag over the same, now-restored file.
///
/// A digest establishes that the bytes did not change in transit. It does not
/// establish who produced them: anyone able to replace the artifact can
/// recompute the digest and replace that too. Keyed mode closes that by
/// binding the output to a key the replacer does not have, and it streams the
/// same way the plain hash does.
void _digestVersusTag(File artifact, String digest) {
  // Stand-in for a key both ends already share. A real one is 32 bytes from a
  // CSPRNG, kept out of the repository; this is a literal so the run is
  // reproducible.
  final releaseKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final wrongKey = Uint8List.fromList(releaseKey)..[31] = 0xFF;

  final tag = _hashInChunks(artifact, key: releaseKey).digest;
  final wrongTag = _hashInChunks(artifact, key: wrongKey).digest;

  print('a digest anyone can recompute, a tag only a key holder can');
  print('  digest             ${_short(digest)}');
  print('  tag, release key   ${_short(tag)}');
  print('  tag, wrong key     ${_short(wrongTag)}  one byte off in the key');
  _verify(
    'neither tag equals the digest, and the two tags differ',
    tag != digest && wrongTag != digest && tag != wrongTag,
  );
}

/// Streams [file] through a [Blake3Hasher] one [_chunkSize] block at a time.
///
/// Returns the digest and the number of bytes this function held at once, so
/// the table above quotes a measured buffer rather than a claimed one. Pass
/// [key] for a keyed tag (a MAC) instead of a plain digest; nothing else
/// about the loop changes.
({String digest, int held}) _hashInChunks(File file, {Uint8List? key}) {
  final hasher = key == null ? Blake3Hasher() : Blake3Hasher.keyed(key);
  try {
    final buffer = Uint8List(_chunkSize);
    final handle = file.openSync();
    try {
      while (true) {
        final read = handle.readIntoSync(buffer);
        if (read == 0) break;
        hasher.update(Uint8List.sublistView(buffer, 0, read));
      }
    } finally {
      handle.closeSync();
    }
    return (digest: hasher.finalizeHex(), held: buffer.lengthInBytes);
  } finally {
    hasher.dispose();
  }
}

/// Writes a deterministic 64 MiB artifact to [file].
///
/// xorshift32 rather than `Random`, and `Endian.little` rather than a native
/// word write, so the staged bytes — and therefore every digest printed
/// below — are the same on any machine that runs this.
void _stage(File file) {
  var state = 0x9E3779B9;
  final block = Uint8List(_chunkSize);
  final words = ByteData.sublistView(block);
  final handle = file.openSync(mode: FileMode.write);
  try {
    for (var c = 0; c < _chunkCount; c++) {
      for (var i = 0; i < block.length; i += 4) {
        state ^= (state << 13) & 0xFFFFFFFF;
        state ^= state >> 17;
        state ^= (state << 5) & 0xFFFFFFFF;
        words.setUint32(i, state, Endian.little);
      }
      handle.writeFromSync(block);
    }
  } finally {
    handle.closeSync();
  }
}

/// Flips the low bit of the byte at [offset], in place, leaving the file's
/// length alone. Calling it twice restores the byte.
void _flipBit(File file, int offset) {
  // FileMode.append opens for writing without truncating; the position is
  // then ours to set.
  final handle = file.openSync(mode: FileMode.append);
  try {
    handle.setPositionSync(offset);
    final byte = handle.readSync(1)[0];
    handle.setPositionSync(offset);
    handle.writeFromSync(Uint8List.fromList([byte ^ 0x01]));
  } finally {
    handle.closeSync();
  }
}

/// Prints [claim] once it holds, and throws when it does not.
///
/// Throwing rather than warning: `dart run` leaves asserts off, and a check
/// that cannot fail is decoration. Same reasoning as example/xof.dart.
void _verify(String claim, bool holds) {
  if (!holds) throw StateError('failed: $claim');
  print('  verified: $claim');
}

/// The first 16 bytes of a 32-byte digest, in hex, marked as truncated. Every
/// comparison in this file runs over the full 64 characters.
String _short(String hex) => '${hex.substring(0, 32)}...';

/// Sizes in the units the numbers were chosen in: 1024-based.
String _size(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes bytes';
}
