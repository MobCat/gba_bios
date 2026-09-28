"""
convert.py: convert the assets to PNGs for editing, and back.

    python convert.py png [--force]    assets/ -> png/
    python convert.py assets           png/ -> assets/

`png` writes two files:
  - png/gameboy_art.png (256x32): G A M E B O Y and the ball, eight 32x32
    sprites, in four greys.
  - png/logo_reference.png (104x16): the Nintendo logo that the header check
    compares with.
It does not overwrite a PNG that already exists (it can be your edit), unless
you give --force.

`assets` reads the PNGs back. If a picture did not change, its asset stays the
same, byte for byte. Thus an unchanged PNG never stops the build from matching
the retail BIOS. A changed picture is encoded in the BIOS format, decoded again
as a check, and written. Then run build.py.

In gameboy_art.png, white is transparent. The three greys are the three colours
of each letter. The BIOS gives each letter its own colours (intro_colors, in
asm/data.s). Any other colour becomes the nearest of the four greys, and
convert.py shows a message. Each 32x32 square is one sprite. You can change the
art, but not the screen positions of the sprites (intro_oam and the intro code
set them).

logo_reference.png cannot be converted back yet. The logo on the boot screen
comes from the cartridge. This file is only the reference that cartridges are
compared with, so if you change only this file, every cartridge fails the check.

The formats are the formats that the BIOS SWIs decode (HuffUnComp,
LZ77UnCompWram, Diff16bitUnFilter), from the GBATEK descriptions. The decoders
were checked against the retail assets on 27 Sep 2026: both logos decoded to
correct pictures.

    gameboy_art.huff    Huffman (4-bit) -> LZ77 -> 2 KiB of 2bpp
    logo_tree.bin +     Huffman (4-bit) -> Diff16 -> 208 bytes of 1bpp,
    logo_reference.bin  13x2 tiles

No installation is necessary: the PNG reader and writer are in this file.
"""
import argparse, heapq, os, struct, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))

# The four values of a 2bpp pixel, as greys: 0 is white (transparent).
GREYS = [(255, 255, 255), (170, 170, 170), (85, 85, 85), (0, 0, 0)]


# --------------------------------------------------------------------------
# Decoding: what the BIOS does
# --------------------------------------------------------------------------
def huff_decode(buf, src=0):
    """SWI 0x13. Returns (data, bytes consumed)."""
    hdr = struct.unpack_from('<I', buf, src)[0]
    bits, kind, size = hdr & 15, (hdr >> 4) & 15, hdr >> 8
    if kind != 2 or bits not in (4, 8):
        raise ValueError('not Huffman: %#x' % hdr)
    tree = src + 4
    stream = tree + (buf[tree] + 1) * 2
    out = bytearray()
    acc = nacc = 0
    node = tree + 1
    val = buf[node]
    while len(out) < size:
        word = struct.unpack_from('<I', buf, stream)[0]
        stream += 4
        for i in range(31, -1, -1):
            bit = (word >> i) & 1
            child = (node & ~1) + (val & 63) * 2 + 2 + bit
            if (val >> (7 - bit)) & 1:          # bit 7: child 0 is data; bit 6: child 1
                acc |= buf[child] << nacc
                nacc += bits
                if nacc == 32:
                    out += struct.pack('<I', acc)
                    acc = nacc = 0
                    if len(out) >= size:
                        break
                node = tree + 1
            else:
                node = child
            val = buf[node]
    return bytes(out[:size]), stream - src


def lz77_decode(buf, src=0):
    """SWI 0x11/0x12. Returns (data, bytes consumed)."""
    hdr = struct.unpack_from('<I', buf, src)[0]
    if (hdr >> 4) & 15 != 1:
        raise ValueError('not LZ77: %#x' % hdr)
    size = hdr >> 8
    p = src + 4
    out = bytearray()
    while len(out) < size:
        flags = buf[p]
        p += 1
        for i in range(8):
            if len(out) >= size:
                break
            if flags & (0x80 >> i):
                n = (buf[p] >> 4) + 3
                disp = ((buf[p] & 15) << 8 | buf[p + 1]) + 1
                p += 2
                for _ in range(n):
                    out.append(out[-disp])
            else:
                out.append(buf[p])
                p += 1
    return bytes(out[:size]), p - src


def diff16_decode(buf, src=0):
    """SWI 0x18."""
    size = struct.unpack_from('<I', buf, src)[0] >> 8
    out = bytearray()
    acc = 0
    for i in range(0, size, 2):
        acc = (acc + struct.unpack_from('<H', buf, src + 4 + i)[0]) & 0xFFFF
        out += struct.pack('<H', acc)
    return bytes(out)


# --------------------------------------------------------------------------
# Encoding: the reverse
# --------------------------------------------------------------------------
def lz77_encode(data):
    """The input format of SWI 0x11: a 4-byte header, then flag bytes. After each
    flag byte come up to eight literals or back-references (3-18 bytes, from up
    to 4096 bytes back). Greedy longest match. Padded to a multiple of 4."""
    out = bytearray(struct.pack('<I', 0x10 | (len(data) << 8)))
    seen = {}                                   # 3-byte prefix -> its start positions
    i = 0
    while i < len(data):
        flag_at = len(out)
        out.append(0)
        for bit in range(8):
            if i >= len(data):
                break
            best, best_disp = 0, 0
            for j in reversed(seen.get(bytes(data[i:i + 3]), ())):
                if i - j > 4096:
                    break
                n = 0
                while n < 18 and i + n < len(data) and data[j + n] == data[i + n]:
                    n += 1
                if n > best:
                    best, best_disp = n, i - j
                    if n == 18:
                        break
            step = best if best >= 3 else 1
            if best >= 3:
                out[flag_at] |= 0x80 >> bit
                out += bytes([((best - 3) << 4) | ((best_disp - 1) >> 8), (best_disp - 1) & 0xFF])
            else:
                out.append(data[i])
            for k in range(i, i + step):
                if k + 3 <= len(data):
                    seen.setdefault(bytes(data[k:k + 3]), []).append(k)
            i += step
    while len(out) % 4:
        out.append(0)
    return bytes(out)


def huff_encode(data):
    """The input format of SWI 0x13, 4-bit: a header, the tree, then the codes
    of the low nibble and the high nibble of each byte. The first bit is in
    bit 31 of each word."""
    freq = [0] * 16
    for b in data:
        freq[b & 15] += 1
        freq[b >> 4] += 1
    heap = [(f, s, s) for s, f in enumerate(freq) if f]
    if len(heap) == 1:                          # a tree needs two leaves
        heap.append((0, 16, (heap[0][2] + 1) & 15))
    heapq.heapify(heap)
    order = 17
    while len(heap) > 1:
        f0, _, n0 = heapq.heappop(heap)
        f1, _, n1 = heapq.heappop(heap)
        heapq.heappush(heap, (f0 + f1, order, (n0, n1)))
        order += 1
    root = heap[0][2]

    # The tree table, as the BIOS reads it: a size byte, the root, then the two
    # children of each node, next to each other. A node byte holds the offset
    # to its children and which children are leaves (bit 7: the first, bit 6:
    # the second). A leaf byte is its value.
    table = [0, 0]
    codes = {}
    queue = [(root, 1, '')]
    while queue:
        node, at, path = queue.pop(0)
        pair = len(table)
        table += [0, 0]
        offset = (pair - (at & ~1) - 2) // 2
        if offset > 63:
            raise ValueError('Huffman tree too deep to lay out')
        byte = offset
        for k, child in enumerate(node):
            if isinstance(child, int):
                table[pair + k] = child
                codes[child] = path + str(k)
                byte |= 0x80 >> k
            else:
                queue.append((child, pair + k, path + str(k)))
        table[at] = byte
    while len(table) % 4:
        table.append(0)
    table[0] = len(table) // 2 - 1

    bits = []
    for b in data:
        bits.append(codes[b & 15])
        bits.append(codes[b >> 4])
    bits = ''.join(bits)
    bits += '0' * (-len(bits) % 32)
    words = b''.join(struct.pack('<I', int(bits[i:i + 32], 2)) for i in range(0, len(bits), 32))
    return struct.pack('<I', 0x24 | (len(data) << 8)) + bytes(table) + words


# --------------------------------------------------------------------------
# The two logos, as the BIOS draws them
# --------------------------------------------------------------------------
def gameboy_letters(art_huff):
    """The eight 32x32 sprites: a list of 32 rows of 256 values, 0-3."""
    lz, _ = huff_decode(art_huff)
    art, _ = lz77_decode(lz)
    rows = [[0] * 256 for _ in range(32)]
    for k in range(8):                                  # letter k is tiles 16k..16k+15, 4x4
        for t in range(16):
            tile = 16 * k + t
            for y in range(8):
                for x in range(8):
                    i = tile * 64 + y * 8 + x
                    rows[(t // 4) * 8 + y][k * 32 + (t % 4) * 8 + x] = (art[i >> 2] >> ((i & 3) * 2)) & 3
    return rows


def gameboy_art(rows):
    """The reverse of gameboy_letters: 32 rows of 256 values to the encoded art."""
    art = bytearray(2048)
    for k in range(8):
        for t in range(16):
            tile = 16 * k + t
            for y in range(8):
                for x in range(8):
                    i = tile * 64 + y * 8 + x
                    art[i >> 2] |= rows[(t // 4) * 8 + y][k * 32 + (t % 4) * 8 + x] << ((i & 3) * 2)
    encoded = huff_encode(lz77_encode(bytes(art)))
    if gameboy_letters(encoded) != rows:
        raise ValueError('the encoded art does not decode to the picture')
    return encoded


def cart_logo(tree, logo):
    """The 104x16 logo from the BIOS tree and the 156 logo bytes of a header: rows of 0/1."""
    h, _ = huff_decode(tree + logo + bytes(16))
    h = bytearray(h)
    h[0:4] = struct.pack('<I', 0xD082)                  # what decode_cart_logo stores there
    bits = diff16_decode(h)
    rows = [[0] * 104 for _ in range(16)]
    for t in range(26):                                 # 13 tiles across, 2 down, 1bpp
        for y in range(8):
            for x in range(8):
                rows[(t // 13) * 8 + y][(t % 13) * 8 + x] = (bits[t * 8 + y] >> x) & 1
    return rows


# --------------------------------------------------------------------------
# PNG: read and write
# --------------------------------------------------------------------------
def write_png(path, rows):
    """rows: a list of rows of (r, g, b). 8-bit RGB."""
    h, w = len(rows), len(rows[0])
    raw = b''.join(b'\0' + bytes(c for px in r for c in px) for r in rows)

    def chunk(kind, data):
        return (struct.pack('>I', len(data)) + kind + data
                + struct.pack('>I', zlib.crc32(kind + data) & 0xFFFFFFFF))
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def read_png(path):
    """Returns (width, height, rows of (r, g, b, a)). Reads all colour types and
    bit depths that a paint program saves. Interlaced PNGs are not supported."""
    d = open(path, 'rb').read()
    if d[:8] != b'\x89PNG\r\n\x1a\n':
        sys.exit('convert: %s is not a PNG' % path)
    p, idat, palette, trns = 8, b'', [], b''
    while p < len(d):
        n, kind = struct.unpack('>I4s', d[p:p + 8])
        body = d[p + 8:p + 8 + n]
        if kind == b'IHDR':
            w, h, depth, ctype, _, _, interlace = struct.unpack('>IIBBBBB', body)
        elif kind == b'PLTE':
            palette = [tuple(body[i:i + 3]) for i in range(0, len(body), 3)]
        elif kind == b'tRNS':
            trns = body
        elif kind == b'IDAT':
            idat += body
        p += 12 + n
    if interlace:
        sys.exit('convert: %s is interlaced; save it without' % path)
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    pixel_bits = channels * depth
    step = max(1, pixel_bits // 8)                      # how many bytes back the filters look
    stride = (w * pixel_bits + 7) // 8
    raw = zlib.decompress(idat)
    prev = bytearray(stride)
    rows = []
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - step] if x >= step else 0
            b = prev[x]
            c = prev[x - step] if x >= step else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        # samples, scaled to 8 bits
        samples = []
        if depth < 8:
            for byte in line:
                for s in range(8 - depth, -1, -depth):
                    samples.append((byte >> s) & ((1 << depth) - 1))
            samples = samples[:w * channels]
        elif depth == 8:
            samples = list(line)
        else:
            samples = [line[i] for i in range(0, len(line), 2)]
        px = []
        for x in range(w):
            s = samples[x * channels:(x + 1) * channels]
            if ctype == 3:
                r, g, b_ = palette[s[0]]
                px.append((r, g, b_, trns[s[0]] if s[0] < len(trns) else 255))
                continue
            if depth < 8:
                s = [v * 255 // ((1 << depth) - 1) for v in s]
            if ctype == 0:
                px.append((s[0], s[0], s[0], 255))
            elif ctype == 4:
                px.append((s[0], s[0], s[0], s[1]))
            elif ctype == 2:
                px.append((s[0], s[1], s[2], 255))
            else:
                px.append(tuple(s))
        rows.append(px)
    return w, h, rows


def to_values(rows, levels):
    """Converts each pixel to the nearest of the `levels` greys (a pixel with
    alpha below 128 becomes the first). Also returns how many pixels were
    not an exact match."""
    out, near = [], 0
    for r in rows:
        line = []
        for red, green, blue, alpha in r:
            if alpha < 128:
                line.append(0)
                near += alpha != 0
                continue
            exact = [v for v, g in enumerate(levels) if g == (red, green, blue)]
            if exact:
                line.append(exact[0])
            else:
                lum = (red * 299 + green * 587 + blue * 114) // 1000
                line.append(min(range(len(levels)), key=lambda v: abs(levels[v][0] - lum)))
                near += 1
        out.append(line)
    return out, near


# --------------------------------------------------------------------------
# The two conversions
# --------------------------------------------------------------------------
def asset(name):
    path = os.path.join(HERE, 'assets', name)
    if not os.path.isfile(path):
        sys.exit('convert: no assets/%s -- run lift.py first' % name)
    return open(path, 'rb').read()


def to_png(force):
    out = os.path.join(HERE, 'png')
    os.makedirs(out, exist_ok=True)
    pictures = [
        ('gameboy_art.png', [[GREYS[v] for v in r] for r in gameboy_letters(asset('gameboy_art.huff'))]),
        ('logo_reference.png', [[GREYS[3 * v] for v in r]
                                for r in cart_logo(asset('logo_tree.bin'), asset('logo_reference.bin'))]),
    ]
    for name, rows in pictures:
        path = os.path.join(out, name)
        if os.path.isfile(path) and not force:
            print('convert: png/%s is already there -- kept (--force writes over it)' % name)
            continue
        write_png(path, rows)
        print('convert: assets/ -> png/%s (%dx%d)' % (name, len(rows[0]), len(rows)))


def to_assets():
    changed = 0

    path = os.path.join(HERE, 'png', 'gameboy_art.png')
    if os.path.isfile(path):
        w, h, rgba = read_png(path)
        if (w, h) != (256, 32):
            sys.exit('convert: png/gameboy_art.png is %dx%d; it has to be 256x32' % (w, h))
        values, near = to_values(rgba, GREYS)
        if near:
            print('convert: png/gameboy_art.png: %d pixels were not one of the four greys, '
                  'and were taken as the nearest' % near)
        old = asset('gameboy_art.huff')
        if values == gameboy_letters(old):
            print('convert: png/gameboy_art.png is unchanged -- assets/gameboy_art.huff left as it is')
        else:
            new = gameboy_art(values)
            open(os.path.join(HERE, 'assets', 'gameboy_art.huff'), 'wb').write(new)
            changed += 1
            print('convert: png/gameboy_art.png -> assets/gameboy_art.huff, %d bytes (was %d, %+d)'
                  % (len(new), len(old), len(new) - len(old)))

    path = os.path.join(HERE, 'png', 'logo_reference.png')
    if os.path.isfile(path):
        w, h, rgba = read_png(path)
        values, _ = to_values(rgba, [GREYS[0], GREYS[3]])
        if (w, h) != (104, 16) or values != cart_logo(asset('logo_tree.bin'), asset('logo_reference.bin')):
            print('convert: png/logo_reference.png has changed, and cannot go back yet -- '
                  'the logo on screen is the cartridge\'s (see the top of convert.py)')

    if changed:
        print('next: python build.py')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0].strip())
    ap.add_argument('to', choices=['png', 'assets'], help='png: assets/ -> png/; assets: png/ -> assets/')
    ap.add_argument('--force', action='store_true', help='with png: overwrite PNGs already in png/')
    args = ap.parse_args()
    if args.to == 'png':
        to_png(args.force)
    else:
        to_assets()


if __name__ == '__main__':
    main()
