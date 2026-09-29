# GBA BIOS
This is a disassembly and recompile project of the Game Boy Advance BIOS ROM.

<img width="993" height="979" alt="image" src="https://github.com/user-attachments/assets/4b2f048a-db20-4d1d-a2f1-756a2de4b689" />


It builds the following file:
* gba_bios.bin `md5: a860e8c0b6d573d191e4ec7db1b1e4f6`

[devkitARM](http://devkitpro.org/wiki/Getting_Started/devkitARM) is required to assemble the ROM. Because not all of it has been disassembled yet, an original BIOS is required in order to build. Rename this file to baserom.bin. Once that is done, run `make` to build.

# Chicken or egg
This project and repo does not contain any Nintendo assets, the gameboy and Nintendo logo, the boot jingle, etc.
To compile this project into a working bios file, you need the working bios file to extract the assets from first.
```
ASSETS = [
    ('logo_tree.bin',      0x326C,   36, 'Huffman header and tree for the cartridge logo'),
    ('logo_reference.bin', 0x3290,  156, 'The logo the header check compares with'),
    ('gameboy_art.huff',   0x332C,  880, 'G A M E B O Y and the ball, eight 32x32 sprites'),
    ('wave_sine.bin',      0x382C,   50, 'MP2000 wave: 33 samples of a sine'),
    ('wave_39D0.bin',      0x39D0, 1329, 'MP2000 wave: 1312 samples, for the intro voice'),
]
```
Simply place the `gba_bios.bin` into the `orig` folder then run `python lift.py` to lift the assets out of the retail bios image.
Only the assets are lifted from the bios. All code is still our own. And you can replace the assets with your own ones if you so choose, check `convert.py`
