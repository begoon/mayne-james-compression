# Mayne-James compression

An experimental two-pass dictionary compressor in Go 1.27 or later.

```sh
go run . c input.txt /tmp/input.mjc
go run . d /tmp/input.mjc /tmp/restored.txt
go test ./...
go vet ./...
go test -fuzz=FuzzRoundTrip -fuzztime=10s
go test -run='^$' -bench=. -benchmem -count=3
```

With `just` installed, run `just` to list convenience commands:

```sh
just build                         # Build bin/mjc
just check                         # Formatting, tests, and vet
just bench                         # Three benchmark samples
just fuzz 30s                      # Fuzz for 30 seconds
just compress input.txt /tmp/input.mjc
just decompress /tmp/input.mjc /tmp/restored.txt
just sample                        # Regenerate output.txt
just clean                         # Remove bin/mjc
```

Input and output must be different files (including hard-link and symlink
aliases). Output is written to a temporary file in the destination directory
and renamed into place only after successful processing and close. A failure
preserves an existing destination. Newly written archives use private file
permissions. Statistics go to stderr and include the entire archive size;
no ratio is reported for empty input.

Dictionary entries are unique, bounded to 1,024 bytes, and matched even when
intermediate prefixes are absent. Pruning recycles inactive slots while keeping
single-byte literals. Newlines delimit phrase construction and matching. The
codebook retains only phrases whose measured payload savings exceed their
stored table cost, re-encoding after pruning.

## Comparison with LZ and Huffman coding

This implementation stores an explicit phrase dictionary. LZ77-style compression
refers back to earlier text, while Huffman coding gives frequent symbols shorter
bit codes. They exploit different kinds of redundancy.

| | This Mayne-James implementation | LZ77-style compression | Huffman coding |
|---|---|---|---|
| Main idea | Replace selected phrases with dictionary codes | Replace repeated sequences with backward references | Use fewer bits for more frequent symbols |
| Example | `compression` becomes dictionary entry A | “Copy 11 bytes from 40 bytes ago” | A common symbol might take 2 bits; a rare one 10 |
| What the decoder needs | Phrase table stored in the archive | Previously decoded bytes | A code tree/table |
| Main opportunity | Recurring phrases worth storing explicitly | Repeated sequences within the history window | Unequal symbol frequencies |

### How this implementation works

The encoder scans the input and builds candidate phrases by joining adjacent
dictionary matches. It chooses up to 94 phrases, stores them in the archive
header, and replaces each selected phrase in the payload with two bytes:
a sentinel and a code.

For example, assuming `banana` is selected and `!` is the sentinel:

```text
Dictionary: A = banana
Input:      banana banana banana
Payload:    !A !A !A
```

The payload shrinks, but the dictionary has a cost. A six-byte phrase costs nine
bytes in the table and saves four bytes per replacement. Three uses therefore
save only three bytes before the archive's fixed seven-byte header. The encoder
removes entries whose measured payload savings do not exceed their table cost,
then re-encodes the input.

### What LZ changes

LZ77-style compression uses earlier output as its dictionary. The same example
can be represented conceptually as:

```text
Input:  banana banana banana
Output: "banana " + [copy 13 bytes from 7 bytes back]
```

Overlapping copies allow the reference to reproduce both remaining occurrences.
No separate `banana` phrase entry is required.

LZ77 can also exploit repetitions this implementation misses: here, phrase
matching stops at newlines, and only the selected 94 phrases receive codes.
Conversely, stored phrases remain available throughout the file, whereas a
bounded LZ history window eventually forgets old text.

LZ is a family of algorithms. LZ78 and LZW build synchronized phrase dictionaries
as encoding and decoding proceed, so their organization is closer to this
implementation, though they do not normally transmit a complete phrase table
upfront.

### What Huffman changes

Huffman coding does not discover repeated phrases by itself. It encodes an
existing sequence of symbols efficiently. With byte symbols, a file containing
many `e` characters can benefit even without long repeated substrings.

This compressor leaves ordinary literals at eight bits and every phrase
reference at sixteen bits. A Huffman stage could make frequent literals or
phrase tokens cheaper. The techniques can be combined:
[DEFLATE, used by gzip](https://www.rfc-editor.org/rfc/rfc1951), applies LZ77
matching and Huffman coding to the resulting literals and match information.

### Practical relevance

This project is primarily of historical and educational interest. It demonstrates
phrase discovery, dictionary selection, and the tradeoff between replacement
savings and dictionary overhead. The small phrase codebook, its storage cost,
fixed two-byte references, and newline boundaries limit this implementation's
competitiveness. Established compressors such as gzip or zstd are generally the
practical choice for everyday compression; actual ratio and speed comparisons
with this implementation require benchmarks.

Dictionary compression itself remains useful. These limitations belong to this
particular implementation and format, rather than to the general idea of
replacing recurring phrases with dictionary references.

## File format

All integers are unsigned and little-endian. The existing `MJ2C` format is
retained; `output.txt` is the current archive of `input.txt`. The original archive is
retained in `testdata/legacy.mjc` for backward-compatibility testing.

```text
4 bytes : magic "MJ2C"
1 byte  : sentinel
u16     : code_count
repeat code_count times:
  1 byte : code
  u16    : phrase_length (nonzero)
  bytes  : phrase
bytes   : encoded payload, continuing to EOF
```

A payload byte other than the sentinel is literal. A sentinel followed by a
code expands to that code's phrase, without recursive expansion. The encoder
uses printable codes 33–126 for phrases. If the chosen sentinel occurs in the
input, code 0 maps to its single-byte literal value; occurrences are escaped
as `sentinel, 0`. This supports all 256 byte values without changing the format.

The decoder rejects invalid magic, truncated headers/table entries, more than
256 entries, duplicate codes, empty phrases, undefined codes, and dangling
sentinels. There is no checksum or original-length field, so corruption or
truncation at a valid payload boundary cannot always be detected.

Benchmarks exercise the in-memory codec with output discarded and diagnostics
redirected to the null device. They include dictionary construction and normal
diagnostic formatting, but exclude CLI startup and filesystem I/O.

## Limitations

This is an in-memory experimental implementation, not a streaming compressor.
Small or incompressible inputs may expand. Codebook selection is heuristic and
does not guarantee the smallest archive. The format has no raw-storage mode.
