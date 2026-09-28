"""
lift.py: extract the assets from the retail BIOS into assets/.

    python lift.py [--force]

Step 2 of 3. Step 1: put your retail dump at orig/gba_bios.bin. Step 3:
build.py builds bios/gba_bios.bin and can compare it with the dump.

An asset is a range of the retail BIOS that the source in asm/ includes with
.incbin, instead of as source text: the logos, the GAME BOY art and the sound
samples, in the byte format that the BIOS stores them in. ASSETS below gives
the location of each asset. The assets are Nintendo data, so lift.py takes
them only from your dump.

If an asset in assets/ is not the retail one, it was edited, and lift.py keeps
it. --force restores the retail assets.

lift.py also checks ASSETS against asm/: every file that the source includes
with .incbin must be in ASSETS. An entry in ASSETS that nothing uses gets a note.
"""
import argparse, glob, hashlib, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RETAIL_MD5 = 'a860e8c0b6d573d191e4ec7db1b1e4f6'

# (file in assets/, address in the retail BIOS, size, description)
ASSETS = [
    ('logo_tree.bin',      0x326C,   36, 'Huffman header and tree for the cartridge logo'),
    ('logo_reference.bin', 0x3290,  156, 'The logo the header check compares with'),
    ('gameboy_art.huff',   0x332C,  880, 'G A M E B O Y and the ball, eight 32x32 sprites'),
    ('wave_sine.bin',      0x382C,   50, 'MP2000 wave: 33 samples of a sine'),
    ('wave_39D0.bin',      0x39D0, 1329, 'MP2000 wave: 1312 samples, for one of the intro voices'),
]


def read_bios():
    """Reads orig/gba_bios.bin (your dump) and checks that it is the retail BIOS."""
    path = os.path.join(HERE, 'orig', 'gba_bios.bin')
    if not os.path.isfile(path):
        sys.exit('lift: no orig/gba_bios.bin -- put your retail GBA BIOS dump there')
    data = open(path, 'rb').read()
    if hashlib.md5(data).hexdigest() != RETAIL_MD5:
        sys.exit('lift: orig/gba_bios.bin is not the retail BIOS (MD5 %s, the AGB-001/AGS-001 one)'
                 % RETAIL_MD5)
    return data


def incbins():
    """Returns every assets/ file that the source in asm/ includes with .incbin."""
    used = set()
    for s in glob.glob(os.path.join(HERE, 'asm', '*.s')):
        for m in re.finditer(r'\.incbin\s+"assets/([^"]+)"', open(s, encoding='utf-8').read()):
            used.add(m.group(1))
    return used


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0].strip())
    ap.add_argument('--force', action='store_true', help='restore the retail assets and overwrite edited ones')
    args = ap.parse_args()

    rom = read_bios()

    # ASSETS and the source must agree before lift.py writes a file.
    listed = set(name for name, _, _, _ in ASSETS)
    used = incbins()
    if used - listed:
        sys.exit('lift: asm/ .incbins %s, which ASSETS in lift.py does not list'
                 % ', '.join(sorted(used - listed)))
    if listed - used:
        print('lift: note: nothing in asm/ uses %s' % ', '.join(sorted(listed - used)))

    out = os.path.join(HERE, 'assets')
    os.makedirs(out, exist_ok=True)
    print('lift: %d assets from orig/gba_bios.bin into assets/' % len(ASSETS))
    kept = 0
    for name, addr, size, what in ASSETS:
        data = rom[addr:addr + size]
        path = os.path.join(out, name)
        have = open(path, 'rb').read() if os.path.isfile(path) else None
        if have == data:
            state = 'unchanged'
        elif have is not None and not args.force:
            state = 'kept (edited)'
            kept += 1
        else:
            open(path, 'wb').write(data)
            state = 'written'
        print('      %-19s %#06x %5d bytes  %-14s %s' % (name, addr, size, state, what))
    if kept:
        print('      edited assets were kept; --force puts the retail ones back')
    print('next: python build.py --check')


if __name__ == '__main__':
    main()
