#!/usr/bin/env python3
"""Raw DEFLATE streams for tools/share/test_inflate.lua (review F08).

Prints one case per line: name, expected result, limit, stream as hex
(tab-separated), then "#end" and the number of cases. The expected result
is what zlib says: the unpacked size, "damaged" where zlib fails, or "long"
for a stream that unpacks past the limit. The only cases where the walk and
zlib differ on purpose are marked "(block limit)": the walk refuses streams
of many tiny blocks, which no encoder writes.

Name prefixes: "fast:" must finish in well under a second, "slow:" prints
how long it took.
"""
import random
import sys
import zlib

BIG = 1 << 24
MB = 1024 * 1024


def raw(data, level=6, strategy=zlib.Z_DEFAULT_STRATEGY, mem=8, chunk=None, flush=zlib.Z_NO_FLUSH):
    packer = zlib.compressobj(level, zlib.DEFLATED, -15, mem, strategy)
    if not chunk:
        return packer.compress(data) + packer.flush()
    out = []
    for start in range(0, len(data), chunk):
        out.append(packer.compress(data[start:start + chunk]))
        if flush != zlib.Z_NO_FLUSH:
            out.append(packer.flush(flush))
    out.append(packer.flush())
    return b"".join(out)


def zlib_says(stream, limit):
    try:
        unpacker = zlib.decompressobj(-15)
        out = unpacker.decompress(stream)
        if not unpacker.eof:
            return "damaged"
    except zlib.error:
        return "damaged"
    return "long" if len(out) > limit else len(out)


class Bits:
    """Writes a DEFLATE bit stream: values lowest bit first, Huffman codes first bit first."""

    def __init__(self):
        self.out, self.byte, self.used = bytearray(), 0, 0

    def put(self, value, count):
        for i in range(count):
            self.byte |= ((value >> i) & 1) << self.used
            self.used += 1
            if self.used == 8:
                self.out.append(self.byte)
                self.byte, self.used = 0, 0

    def code(self, pair):
        value, length = pair
        for i in range(length - 1, -1, -1):
            self.put((value >> i) & 1, 1)

    def done(self):
        if self.used:
            self.out.append(self.byte)
        return bytes(self.out)


def canonical(lengths):
    count = [0] * 16
    for length in lengths:
        if length:
            count[length] += 1
    code, start = 0, [0] * 16
    for length in range(1, 16):
        code = (code + count[length - 1]) << 1
        start[length] = code
    codes = {}
    for symbol, length in enumerate(lengths):
        if length:
            codes[symbol] = (start[length], length)
            start[length] += 1
    return codes


FIXED = canonical([8] * 144 + [9] * 112 + [7] * 24 + [8] * 8)
FIXED_DIST = canonical([5] * 32)                 # 30 and 31 are not used, but have codes
ORDER = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]


def dynamic_header(bits, literal_lengths, distance_lengths, code_lengths=None):
    """A dynamic block header listing every length as is (no repeat codes)."""
    if code_lengths is None:
        code_lengths = [4] * 13 + [5] * 6        # a complete code over all 19 symbols
    bits.put(len(literal_lengths) - 257, 5)
    bits.put(len(distance_lengths) - 1, 5)
    bits.put(19 - 4, 4)
    for symbol in ORDER:
        bits.put(code_lengths[symbol], 3)
    lengths_code = canonical(code_lengths)
    for length in literal_lengths + distance_lengths:
        bits.code(lengths_code[length])
    return canonical(literal_lengths), canonical(distance_lengths)


def crafted():
    cases = []

    bits = Bits()
    bits.put(1, 1); bits.put(3, 2)
    cases.append(("crafted: block type 3", bits.done()))

    cases.append(("crafted: stored LEN and NLEN disagree", bytes([1, 5, 0, 0, 0]) + b"hello"))
    cases.append(("crafted: stored block cut short", bytes([1, 5, 0, 0xFA, 0xFF]) + b"hel"))
    cases.append(("crafted: stored block", bytes([1, 5, 0, 0xFA, 0xFF]) + b"hello"))

    def fixed(symbols):
        bits = Bits()
        bits.put(1, 1); bits.put(1, 2)
        for kind, value, extra in symbols:
            if kind == "lit":
                bits.code(FIXED[value])
            elif kind == "dist":
                bits.code(FIXED_DIST[value])
            if extra:
                bits.put(*extra)
        return bits.done()

    cases.append(("crafted: fixed literal and copy",
                  fixed([("lit", 97, None), ("lit", 264, None), ("dist", 0, None), ("lit", 256, None)])))
    cases.append(("crafted: copy from before the start",
                  fixed([("lit", 97, None), ("lit", 257, None), ("dist", 1, None), ("lit", 256, None)])))
    cases.append(("crafted: length code 286", fixed([("lit", 97, None), ("lit", 286, None), ("lit", 256, None)])))
    cases.append(("crafted: distance code 30",
                  fixed([("lit", 97, None), ("lit", 257, None), ("dist", 30, None), ("lit", 256, None)])))
    cases.append(("crafted: no end of block", fixed([("lit", 97, None)])))

    # Dynamic: a block with a complete literal code and two distance codes.
    literal_lengths = [8] * 226 + [9] * 60          # 286 symbols, complete
    distance_lengths = [4] * 2 + [5] * 28           # 30 symbols, complete
    bits = Bits()
    bits.put(1, 1); bits.put(2, 2)
    lit, dist = dynamic_header(bits, literal_lengths, distance_lengths)
    bits.code(lit[120]); bits.code(lit[258]); bits.code(dist[0]); bits.code(lit[256])
    cases.append(("crafted: dynamic block", bits.done()))

    # Over-subscribed code length code: 19 lengths of 1.
    bits = Bits()
    bits.put(1, 1); bits.put(2, 2)
    bits.put(0, 5); bits.put(0, 5); bits.put(15, 4)
    for _ in ORDER:
        bits.put(1, 3)
    bits.put(0, 32)
    cases.append(("crafted: code length code with too many codes", bits.done()))

    # No length for the end-of-block code.
    bits = Bits()
    bits.put(1, 1); bits.put(2, 2)
    dynamic_header(bits, [8] * 226 + [9] * 30 + [0] + [9] * 29, distance_lengths)
    bits.put(0, 32)
    cases.append(("crafted: no end-of-block code", bits.done()))

    # Incomplete literal code with more than one code (zlib refuses it).
    bits = Bits()
    bits.put(1, 1); bits.put(2, 2)
    lit, dist = dynamic_header(bits, [9] * 286, distance_lengths)
    bits.code(lit[256])
    cases.append(("crafted: incomplete literal code", bits.done()))

    # Incomplete distance code with a single code (zlib takes it).
    bits = Bits()
    bits.put(1, 1); bits.put(2, 2)
    lit, dist = dynamic_header(bits, literal_lengths, [1] + [0] * 29)
    bits.code(lit[120]); bits.code(lit[257]); bits.code(dist[0]); bits.code(lit[256])
    cases.append(("crafted: single distance code", bits.done()))

    return cases


def at_block_limit(blocks):
    """A literal, then dynamic blocks with full headers that copy 64 bytes each:
    the most work per byte the block limit lets through."""
    literal_lengths = [8] * 226 + [9] * 60
    distance_lengths = [4] * 2 + [5] * 28
    bits = Bits()
    bits.put(0, 1); bits.put(1, 2)
    bits.code(FIXED[97]); bits.code(FIXED[276]); bits.put(4, 3); bits.code(FIXED_DIST[0]); bits.code(FIXED[256])
    for index in range(blocks):
        bits.put(1 if index == blocks - 1 else 0, 1); bits.put(2, 2)
        lit, dist = dynamic_header(bits, literal_lengths, distance_lengths)
        bits.code(lit[276]); bits.put(5, 3); bits.code(dist[0]); bits.code(lit[256])
    return bits.done()


def sample(rng):
    size = rng.choice([0, 1, 2, 5, 50, 300, 2000, 9000, 40000])
    kind = rng.randrange(6)
    if kind == 0:
        return bytes(rng.randrange(256) for _ in range(size))
    if kind == 1:
        return bytes(rng.choice(b"ab") for _ in range(size))
    if kind == 2:
        return (b'["fontSize"] = 14, ["layout"] = "EldoCenter1000", ' * (size // 40 + 1))[:size]
    if kind == 3:
        return bytes(size)
    if kind == 4:
        words = [b"Unit", b"Frame", b"Bar", b"anchor", b"TOPLEFT", b"12", b"true", b",", b"{", b"}"]
        return b"".join(rng.choice(words) for _ in range(size // 4))
    return bytes(rng.randrange(40, 60) for _ in range(size))


def main():
    rng = random.Random(8)
    cases = []

    def add(name, stream, limit=BIG, expect=None):
        said = zlib_says(stream, limit)
        if expect is None:
            expect = said
        cases.append((name, expect, limit, stream))

    strategies = [zlib.Z_DEFAULT_STRATEGY, zlib.Z_FILTERED, zlib.Z_HUFFMAN_ONLY, zlib.Z_RLE, zlib.Z_FIXED]
    for index in range(250):
        data = sample(rng)
        options = dict(level=rng.choice([0, 1, 6, 9]), strategy=rng.choice(strategies), mem=rng.choice([1, 8, 9]),
                       chunk=rng.choice([None, None, 2048, 8192]),
                       flush=rng.choice([zlib.Z_NO_FLUSH, zlib.Z_SYNC_FLUSH, zlib.Z_FULL_FLUSH]))
        stream = raw(data, **options)
        assert zlib_says(stream, BIG) == len(data)
        add("zlib %d (%d bytes)" % (index, len(data)), stream)
        if len(stream) > 1:
            add("zlib %d cut short" % index, stream[:rng.randrange(1, len(stream))])
            flipped = bytearray(stream)
            spot = rng.randrange(len(flipped))
            flipped[spot] ^= 1 << rng.randrange(8)
            add("zlib %d with a bit flipped" % index, bytes(flipped))

    for name, stream in crafted():
        add(name, stream)
    add("empty input", b"")
    add("zlib wrapper instead of raw DEFLATE", zlib.compress(b"hello hello hello"))
    add("bytes after the last block", raw(b"hello") + b"more")

    # The limit.
    add("zeros at the limit", raw(bytes(MB), 9), MB)
    add("zeros past the limit", raw(bytes(MB + 1), 9), MB)
    add("zeros past the limit, under a bigger one", raw(bytes(MB + 1), 9), 2 * MB)
    add("fast: 64 MB of zeros", raw(bytes(64 * MB), 9), MB)
    add("fast: 64 MB of one letter, fixed codes", raw(b"x" * (64 * MB), 9, zlib.Z_FIXED), MB)
    add("fast: stored block past the limit", bytes([1, 0xFF, 0xFF, 0, 0]) + bytes(65535), 1000)

    # The block limit. Every one of these is fine for zlib.
    tiny = raw(bytes(rng.randrange(256) for _ in range(20000)), 6, chunk=16, flush=zlib.Z_SYNC_FLUSH)
    assert zlib_says(tiny, BIG) == 20000
    add("tiny blocks (block limit)", tiny, BIG, "damaged")
    stored = b"\x00\x00\x00\xff\xff" * 200000 + b"\x03\x00"
    assert zlib_says(stored, BIG) == 0
    add("fast: empty stored blocks (block limit)", stored, BIG, "damaged")
    bits = Bits()
    for index in range(200000):
        bits.put(1 if index == 199999 else 0, 1); bits.put(1, 2); bits.code(FIXED[256])
    empty = bits.done()
    assert zlib_says(empty, BIG) == 0
    add("fast: empty fixed blocks (block limit)", empty, BIG, "damaged")

    # The slowest kinds of stream.
    add("slow: dynamic blocks at the block limit", at_block_limit(3000))
    literals = bytes(rng.randrange(128) for _ in range(600000))
    add("slow: Huffman-coded literals", raw(literals, 9, zlib.Z_HUFFMAN_ONLY))
    profile = b"".join(b'["%s%d"] = { ["point"] = "TOPLEFT", ["x"] = %d, ["y"] = %d, ["shown"] = %s },\n'
                       % (rng.choice([b"Bar", b"Frame", b"Unit", b"Aura"]), i, rng.randrange(-900, 900),
                          rng.randrange(-600, 600), rng.choice([b"true", b"false"])) for i in range(12000))
    add("slow: a big profile-like table", raw(profile, 6))

    out = sys.stdout
    for name, expect, limit, stream in cases:
        out.write("%s\t%s\t%d\t%s\n" % (name, expect, limit, stream.hex()))
    out.write("#end\t%d\n" % len(cases))


if __name__ == "__main__":
    main()
