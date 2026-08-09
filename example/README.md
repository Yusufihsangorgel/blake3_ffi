# blake3_ffi examples

## Verifying a download nobody watched arrive

`blake3_ffi_example.dart` takes one job end to end. A release artifact is
sitting on disk and the question is whether it is the bytes the publisher meant
to ship. That splits into three questions, and the file answers them in order.

**Can you hash a file you do not want to hold?** It stages a 64 MiB artifact in
a temporary directory and hashes it three ways: `blake3Hex` over the whole
buffer, the `blake3StreamHex(openRead())` one-liner, and a hand-written
`Blake3Hasher` loop over one reused 64 KiB buffer. All three print the digest
they agree on, next to the bytes each one had to hold at once. The 1024-to-1 gap
between the first row and the other two is what the package claims over the
pure-Dart `blake3_dart`, whose exported API has no incremental entry point.

**What does one flipped bit do?** It flips bit 0 of the byte at the middle of
the file, re-hashes, and counts how many of the 64 hex characters moved. The
file keeps its length and still opens, which is the reason silent corruption is
worth a hash in the first place. Flipping the bit back has to restore the
original digest, and the run fails loudly if it does not.

**Is a digest even the right tool?** Whoever can replace an artifact can also
recompute the digest published beside it. The last block puts three values side
by side: the plain digest, a tag under a shared release key, and a tag under a
key that is wrong in one byte.

Nothing here touches the network, and nothing lands in your checkout: the
artifact comes out of a deterministic PRNG into `Directory.systemTemp`, and the
directory is removed on the way out. Every run stages the same bytes, so the
digests below are the digests you will get.

```
dart run example/blake3_ffi_example.dart
```

```
staged 64.0 MB to verify, 1024 blocks of 64.0 KB

hashing it three ways
  blake3Hex(bytes)           held 64.0 MB  9316ce7115ec325adfc088851d929952...
  blake3StreamHex(openRead)  held 64.0 KB  9316ce7115ec325adfc088851d929952...
  Blake3Hasher, own buffer   held 64.0 KB  9316ce7115ec325adfc088851d929952...
  verified: all three digests are identical
  neither streaming path held more than 64.0 KB, 1024x less than the file
  the native copy is the size of the chunk, so is the gap there

what one flipped bit does
  bit 0 of the byte at offset 33554432 of 67108864
  digest                     3fa09fa4db758ca69c3243edd2af5893...
  62 of 64 hex characters differ from the digest above
  verified: flipping the bit back restores the original digest

a digest anyone can recompute, a tag only a key holder can
  digest             9316ce7115ec325adfc088851d929952...
  tag, release key   b8b92745ccc71532bd64c620ff681a00...
  tag, wrong key     5137c72a90f9cd0b214edb0e5ee27423...  one byte off in the key
  verified: neither tag equals the digest, and the two tags differ

next: bench/bench.dart for throughput, example/xof.dart for reading past 32 bytes
```

The `verified:` lines are real checks over the full 64 characters, not over the
truncated hex printed above them, and they throw rather than warn. Key
derivation and reading past 32 bytes are in `xof.dart` next; the throughput this
runs at is in `bench/bench.dart`, at the end.

## Reading more than 32 bytes

```
dart run example/xof.dart
```

`xof.dart` is about the feature SHA-256 has no equivalent for: the digest is
the opening of an unbounded output stream, and you can keep reading.
`outputLength` asks for more bytes and `seek` skips ahead to a window. The file
checks the two properties worth building on, comparing every byte rather than
the truncated hex it prints.

Its inputs are fixed. A run gives you this:

```
one input, one output stream
  32 bytes            41454b28f0d0a23d978fbc5c7c3dce3c...
  64 bytes            41454b28f0d0a23d978fbc5c7c3dce3c...
  bytes 32..63, seek  ac814b1cae91ac8826f9ee8ec45893af...
  verified: the 32-byte digest is the first half of the 64-byte read
  verified: the seeked window is the second half of that same read

one derivation, three purpose-bound values
  cipher key  bytes  0..31  fb26375bb6b31dfddd421b96ef0b7610...
  mac key     bytes 32..63  73e5bcbd4225687802329d497497833a...
  key id      bytes 64..71  58dc9fbd9e557b44
  verified: the cipher key is bytes 0..31 of one 72-byte derivation
  verified: the mac key is bytes 32..63 of it
  verified: the key id is bytes 64..71 of it
```

Compare the first two hex lines: the 64-byte read opens with the 32-byte digest
untouched, which is what lets a digest you stored last year stay valid the day
you decide you need 64 bytes. The second block spends that property, taking a
cipher key, a MAC key and a short key id out of one derivation instead of
running three.

## The throughput the README quotes

```
dart run bench/bench.dart
```

The 22x figure comes from here rather than from an example. `bench.dart` hashes
the same buffers with this package, the pure-Dart `blake3_dart` and SHA-256
from `crypto`. It measures each candidate once in every position, because
whichever runs first pays the VM's warm-up and reads slower than it is, and it
requires the two BLAKE3 implementations to agree byte for byte before it times
anything. A `Stopwatch` dropped into an example would clear neither bar.
