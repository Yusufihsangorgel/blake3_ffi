# blake3_ffi example

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
