# blake3_ffi examples

## The four everyday operations

`blake3_ffi_example.dart` covers the four things the package does: hash a buffer
in one call, hash a large file in a stream without holding it in memory, compute
a keyed MAC, and derive a purpose-bound subkey from a shared secret.

```dart
// One-shot hash, straight to hex.
print(blake3Hex(utf8.encode('The quick brown fox jumps over the lazy dog')));

// Streaming: feed a file 64 KiB at a time so memory stays flat at any size.
final hasher = Blake3Hasher();
hasher.update(chunk);         // any number of times
final digest = hasher.finalizeHex();
hasher.dispose();

// Keyed hashing (a MAC): both sides share a 32-byte key.
print(blake3KeyedHex(key, message));

// Key derivation: a shared secret plus a context string becomes a subkey.
print(blake3DeriveKeyHex('example.com 2026 session cookie v1', secret));
```

Run it:

```
dart run example/blake3_ffi_example.dart
```

Output (the `this file` line is the hash of the example's own source, so it
changes if the file does; the rest are fixed test vectors):

```
blake3("...dog") = 2f1514181aadccd913abd94cfa592701a5686ab23f8df1dff1b74710febc6d4a
this file        = <hash of this source file>
keyed("...dog")  = f1c78a63454ec51f42b9d88ac49133942182b5ecb380dc9ec90dcd7e6ad675e8
derived key      = fdd449d5d0a0ccab6a584896574ce5157c26cd55b7af506f858c769e515d4c32
```

The streaming `hashFile` helper in the example is the pattern for anything too
big to hold in memory: open the file, `update` in fixed-size chunks, `finalizeHex`,
`dispose`. See the package README for the throughput this runs at.

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
