"""
build.py: assemble asm/ and assets/ into bios/gba_bios.bin.

    python build.py [--check] [--retail]

asm/bios.s includes the other files of asm/ in address order. The assets come
from assets/ with .incbin. Thus the build uses the contents of these two
folders: the output of lift.py, unchanged or edited.

Output: the BIOS goes to bios/. The object, the ELF (all labels, for nm and a
debugger) and the link script go to build/.

build.py shows how much of the 16 KiB BIOS is free, and the value that
GetBiosChecksum (SWI 0x0D) will return. The retail BIOS returns 0xBAAE187F.
An assembly that does not fit fails, because the source ends with `.org 0x4000`.

--check compares the result with orig/gba_bios.bin (your retail dump) byte for
byte. Directly after lift.py, they are identical. After an edit, they are not,
and --check shows where they differ, by label.

--retail checks that the source itself is still correct. It builds asm/ with
the retail assets, which it extracts from orig/gba_bios.bin into a temporary
folder (it ignores assets/). Then it compares the result with the dump. While
you only name, comment and tidy asm/, the result stays identical, also with
edited art in assets/. --retail does not change bios/ or build/.

Requires the GNU Arm Embedded toolchain (arm-none-eabi-as, -ld, -objcopy, -nm),
on PATH or in the folder where its Windows installer puts it.
"""
import argparse, hashlib, os, shutil, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BIOS_SIZE = 0x4000
RETAIL_MD5 = 'a860e8c0b6d573d191e4ec7db1b1e4f6'
RETAIL_CHECKSUM = 0xBAAE187F
RETAIL_USED = 0x3F01            # bios_end: after the last non-zero byte of the retail BIOS
LDSCRIPT = 'OUTPUT_ARCH(arm)\nSECTIONS\n{\n\t. = 0;\n\t.text : { *(.text) }\n\t/DISCARD/ : { *(*) }\n}\n'


def tool(name):
    """Find arm-none-eabi-<name> on PATH or in the GNU Arm Embedded install folder."""
    exe = 'arm-none-eabi-' + name
    for d in os.environ.get('PATH', '').split(os.pathsep):
        for cand in (exe, exe + '.exe'):
            if os.path.isfile(os.path.join(d, cand)):
                return os.path.join(d, cand)
    base = r'C:\Program Files (x86)\GNU Arm Embedded Toolchain'
    if os.path.isdir(base):
        for v in sorted(os.listdir(base), reverse=True):
            p = os.path.join(base, v, 'bin', exe + '.exe')
            if os.path.isfile(p):
                return p
    sys.exit('%s not found: install the GNU Arm Embedded toolchain, or put it on PATH' % exe)


def assemble(root, main_path, out_path, work=None):
    """Assemble <root>/<main_path> to out_path. Paths in .include and .incbin
    are relative to root. The object, ELF and link script go to work (default:
    the folder of out_path). Returns (bytes, '') or (None, the tool errors)."""
    as_, ld, oc = tool('as'), tool('ld'), tool('objcopy')
    work = work or os.path.dirname(out_path)
    os.makedirs(work, exist_ok=True)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    stem = os.path.join(work, os.path.splitext(os.path.basename(out_path))[0])
    obj, elf, ldscript = stem + '.o', stem + '.elf', os.path.join(work, 'bios.ld')
    with open(ldscript, 'w', newline='\n') as f:
        f.write(LDSCRIPT)
    for cmd in ([as_, '-mcpu=arm7tdmi', '-I', root, '-o', obj, main_path],
                [ld, '-T', ldscript, '-o', elf, obj],
                [oc, '-O', 'binary', '-j', '.text', elf, out_path]):
        r = subprocess.run(cmd, capture_output=True, text=True, cwd=root)
        if r.returncode:
            return None, r.stderr
    return open(out_path, 'rb').read(), ''


def symbols(elf):
    """Returns [(address, label)] from the ELF, in address order."""
    out = subprocess.run([tool('nm'), '-n', elf], capture_output=True, text=True, check=True).stdout
    syms = []
    for line in out.splitlines():
        f = line.split()
        if len(f) == 3 and not f[2].startswith('$'):
            syms.append((int(f[0], 16), f[2]))
    return syms


def where(syms, addr):
    """Returns an address as 'label + n'."""
    best = None
    for a, name in syms:
        if a > addr:
            break
        best = (a, name)
    if best is None:
        return '%#06x' % addr
    return best[1] if best[0] == addr else '%s + %#x' % (best[1], addr - best[0])


def checksum(data):
    return sum(struct.unpack('<%dI' % (len(data) // 4), data)) & 0xFFFFFFFF


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0].strip())
    ap.add_argument('--check', action='store_true', help='compare the result with orig/gba_bios.bin (your dump)')
    ap.add_argument('--retail', action='store_true',
                    help='build with the retail assets in a temporary folder, and check that asm/ is still correct')
    args = ap.parse_args()

    if not os.path.isfile(os.path.join(HERE, 'asm', 'bios.s')):
        sys.exit('build: no asm/bios.s run lift.py first')

    root, temp = HERE, None
    if args.retail:
        import lift
        rom = lift.read_bios()
        root = temp = tempfile.mkdtemp(prefix='agbbios-')
        shutil.copytree(os.path.join(HERE, 'asm'), os.path.join(root, 'asm'))
        os.makedirs(os.path.join(root, 'assets'))
        for name, addr, size, _ in lift.ASSETS:
            open(os.path.join(root, 'assets', name), 'wb').write(rom[addr:addr + size])
        args.check = True
    try:
        out, work = os.path.join(root, 'bios', 'gba_bios.bin'), os.path.join(root, 'build')
        built, err = assemble(root, os.path.join('asm', 'bios.s'), out, work)
        if built is None:
            sys.exit('build: failed\n' + err)
        if len(built) != BIOS_SIZE:
            sys.exit('build: %d bytes, not %d' % (len(built), BIOS_SIZE))
        syms = symbols(os.path.join(work, 'gba_bios.elf'))
    finally:
        if temp:
            shutil.rmtree(temp, ignore_errors=True)

    end = dict((n, a) for a, n in syms).get('bios_end')
    if args.retail:
        print('build: asm/ with the retail assets (not assets/), MD5 %s' % hashlib.md5(built).hexdigest())
    else:
        print('build: bios/gba_bios.bin, MD5 %s' % hashlib.md5(built).hexdigest())
    if end is not None:
        print('       %d of %d bytes used, %d free' % (end, BIOS_SIZE, BIOS_SIZE - end))
    cs = checksum(built)
    print('       GetBiosChecksum 0x%08X%s' % (cs, ' (as retail)' if cs == RETAIL_CHECKSUM
                                              else ' (retail: 0x%08X)' % RETAIL_CHECKSUM))

    if args.check:
        path = os.path.join(HERE, 'orig', 'gba_bios.bin')
        if not os.path.isfile(path):
            sys.exit('build: --check needs your dump at orig/gba_bios.bin')
        want = open(path, 'rb').read()
        if built == want:
            print('check: identical to orig/gba_bios.bin%s'
                  % (' (the retail BIOS)' if hashlib.md5(want).hexdigest() == RETAIL_MD5 else ''))
            return
        diff = [a for a in range(min(len(built), len(want))) if built[a] != want[a]]
        print('check: differs from orig/gba_bios.bin in %d byte%s, the first at %#06x (%s)'
              % (len(diff), 's' if len(diff) != 1 else '', diff[0], where(syms, diff[0])))
        if end is not None and end != RETAIL_USED:
            print('       %d bytes %s than the retail BIOS, so what comes after the change has moved, '
                  'and so has every reference to it'
                  % (abs(end - RETAIL_USED), 'longer' if end > RETAIL_USED else 'shorter'))
        sys.exit(1)


if __name__ == '__main__':
    main()
