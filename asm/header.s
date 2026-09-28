@ header.s 0x05A4-0x09C1: the cartridge header and the intro graphics.
@
@ boot_intro (intro.s) calls intro_load_graphics once, before its first frame.
@ intro_load_graphics does these steps:
@   1. Reads 20 bytes near the top of the cartridge space and discards them.
@      Header byte 0xB4 bit 7 selects the address. Why it does this is not known.
@   2. copy_cart_header: copies header bytes 0x04-0xDF to IWRAM at 0x03000088,
@      in 20-byte pieces. Between the pieces it does six dummy reads of ROM,
@      selected from cart_read_offsets by header_hash and byte 0x9E.
@   3. THE 0x96 CHECK: if header byte 0xB2 is not 0x96, it fills the logo in the
@      copy (0x04-0x9F) with 0xFF. The intro does not stop: it draws the blank
@      logo, and check_cart_header fails at the end of the intro.
@   4. Decodes gameboy_art (Huffman, then LZ77) and unpacks its eight 32x32
@      cells (G A M E B O Y, the ball) to 8bpp in BG VRAM. Cell k uses colours
@      4k+1 to 4k+3. Then it copies each cell into OBJ VRAM for the sprites.
@   5. Draws the Nintendo logo of the cartridge: decode_cart_logo,
@      unpack_cart_logo, place_cart_logo. The logo goes to OBJ VRAM, where OAM
@      entries 7 and 8 (intro_oam) show it.
@   6. fill_2d: writes the BG3 map, a 4x4-tile square of cell 7 (the ball).
@      BG3 is the shine that crosses the letters from frame 109 (intro.s).
@   7. Sets BG colour 0 to white (the backdrop), copies intro_palette to BG and
@      OBJ colours 28-31, and copies the ten intro_oam sprites to OAM.
@ After its last frame (210), boot_intro calls check_cart_header: THE LOGO CHECK
@ and THE COMPLEMENT CHECK. MultiBoot also calls it, for a received header.
@ Each frame, boot_intro uses intro_letter_path, intro_letter_affine and
@ intro_fade_colors for the letters. It calls intro_reset_letters once, before
@ the first frame.
@ SoundBias (SWI 0x19) is also in this file; boot_intro calls it too.
@
@ IWRAM (the BIOS owns all of IWRAM during the intro):
@   0x03000088-0x03000163  the header copy. Header byte b is at 0x03000084 + b
@                          (0xB2 at 0x03000136). boot_intro checks it.
@   0x03000564, 4 KiB      scratch: packed data in, decoded data out
@   0x03001564             scratch: the other side of each decode.
@                          place_cart_logo overwrites 0x03000564-0x03002563.
@   0x03003580             the letter states (intro_reset_letters; intro.s)
@   INTRO_FLAG             decode_cart_logo writes the low byte of its source here
@ VRAM as the intro uses it (mode 2, BG3 affine, OBJ 2D mapping):
@   VRAM + 0x40 + k*0x400  cell k at 8bpp: BG tiles 1-0x80, 4x4 tiles per cell.
@                          Only cell 7 (tiles 0x71-0x80) is on a BG (BG3).
@   VRAM + 0x2440, 0x2840  staging area for the 8bpp logo: two rows of 13 tiles.
@                          Each row starts 2 tiles (0x80 bytes) in.
@   VRAM + 0xB800          the BG3 map (boot_intro sets BG3CNT)
@   OBJ_VRAM               2D mapping: 32 rows of 1 KiB. One row is 32 tile
@                          numbers (16 8bpp tiles = 128 pixels) by 8 lines.
@                          Cells 0-6 (letters): rows 2-5, 8-11, 14-17, 20-23,
@                          two cells per band. Cell 7 (ball): row 20, byte 0x200.
@                          The logo: rows 27-28 (OBJ_VRAM + 0x6C00, 0x7000).
@ VRAM, PLTT and OAM: written with CpuSet, CpuFastSet, BitUnPack, copy_bios_data,
@ and direct stores (fill_2d, intro_fade_colors, place_cart_logo and others).
@ I/O: only REG_SOUNDBIAS, in SoundBias.
@
@ Baked in here, for a different word or a different number of letters:
@   - intro_load_graphics unpacks and copies exactly 8 cells (cmp r7, #8 and
@     movs r7, #0xE).
@   - intro_reset_letters starts exactly 7 letters (0x78).
@   - intro_letter_path centres the 7 letters on slot 3 (n - 3), 23 pixels apart.
@   - The ball must be cell 7: 0x7271 in fill_2d is its first BG tile, and its
@     colours 29-31 come from intro_palette.
@   - OBJ VRAM rows 0-25 are full (see intro_letter_tiles in data.s).
@   - BG VRAM from 0x2440 is for the logo.

@ Copies cartridge header bytes 0x04-0xDF to 0x03000088, in eleven 20-byte pieces.
@ After each of pieces 3 to 8, it reads one halfword of ROM, at 0x08000000 + 2 x
@ a value from cart_read_offsets (six reads). It discards the values read.
@ GBATEK: "dummy-reads from a stream of pre-defined addresses", perhaps to
@ unlock something in commercial cartridges.
@ The six values: set 4 x (header 0x9E & 3) + header_hash(0x9D-0xB7), of 16 sets.
@ In: nothing. Out: nothing. Reads ROM; writes 0x03000088-0x03000163.
@ Called only from intro_load_graphics.
copy_cart_header:
	.thumb
	push {r3, r4, r5, r6, lr}
	movs r6, #8
	lsls r6, r6, #0x18	@ r6 = 0x08000000 (ROM)
	movs r5, #0x9E
	adds r5, r5, r6	@ r5 = 0x0800009E: the "key" byte, in the logo
	subs r0, r5, #1	@ header_hash over 0x9D-0xB7 (27 bytes)
	movs r1, #0x1B
	bl header_hash
	movs r4, #0xC
	muls r4, r0	@ 12 bytes (six halfwords) per hash value
	ldrb r3, [r5, #0]
	lsls r3, r3, #0x1E
	lsrs r3, r3, #0x1E	@ r3 = header 0x9E bits 0-1 (normally 0: 0xF8)
	movs r2, #0x30
	muls r2, r3	@ 48 bytes (four sets) per value of these bits
	adds r4, r4, r2
	adr r5, cart_read_offsets
	adds r5, r5, r4	@ r5 = the set of six offsets for this cartridge
	movs r4, #0	@ r4 = piece, 0-10
header_piece_loop:	@ each piece
	adds r0, r4, #0
	bl copy_header_piece
	cmp r4, #3
	blt header_piece_next	@ pieces 0-2: no read
	cmp r4, #9
	bge header_piece_next	@ pieces 9-10: no read
	ldrh r1, [r5, #0]
	lsls r1, r1, #1
	orrs r1, r6	@ r1 = 0x08000000 + 2 x offset
	ldrh r0, [r1, #0]	@ dummy read; r0 is not used
	.inst.n 0x1CAD	@ adds r5, r5, #2: next offset
header_piece_next:
	.inst.n 0x1C64	@ adds r4, r4, #1
	cmp r4, #0xB
	bne header_piece_loop	@ 11 pieces x 20 = 220 bytes: 0x04-0xDF
	pop {r3, r4, r5, r6, pc}
	.balign 4
@ ROM halfwords that copy_cart_header reads: one set of six per header_hash and 0x9E.
@ 16 sets of six halfwords. Set s is halfwords 6s to 6s+5. For a value v, the
@ read is of the halfword at 0x08000000 + 2v (all in the first 64 KiB).
@ Set s = 4 x (header 0x9E & 3) + header_hash. Thus each value of the two low
@ bits of 0x9E uses three lines below. Normal cartridges (0xF8) use the first three.
cart_read_offsets:
	.2byte 0x479B, 0x7426, 0x11BC, 0x6D4F, 0x11BD, 0x32F1, 0x7FD9, 0x2CE7	@ 0x9E&3=0: sets 0-3
	.2byte 0x5DA5, 0x11BD, 0x4610, 0x5DA4, 0x4E90, 0x6173, 0x2A84, 0x4E91
	.2byte 0x106A, 0x75FE, 0x29C8, 0x7839, 0x420E, 0x5D1B, 0x7838, 0x12A8
	.2byte 0x3F7D, 0x67B9, 0x26F3, 0x54EF, 0x7C23, 0x26F2, 0x6BC6, 0x4137	@ 0x9E&3=1: 4-7
	.2byte 0x15AB, 0x730D, 0x6BC7, 0x3B4F, 0x5F24, 0x3DDA, 0x253F, 0x1749
	.2byte 0x3DDB, 0x70E6, 0x746C, 0x30F7, 0x531F, 0x6738, 0x531E, 0x1A51
	.2byte 0x1971, 0x5B7D, 0x4ED6, 0x1970, 0x3F27, 0x75CB, 0x3D62, 0x128C	@ 0x9E&3=2: 8-11
	.2byte 0x74B8, 0x2FAD, 0x74B9, 0x64FD, 0x6C9A, 0x4F3A, 0x276D, 0x73EF
	.2byte 0x38B1, 0x4F3B, 0x571E, 0x7EA3, 0x6249, 0x3587, 0x1B7C, 0x3586
	.2byte 0x7AFB, 0x67E4, 0x5C92, 0x67E5, 0x2BCA, 0x438C, 0x2E6F, 0x587F	@ 0x9E&3=3: 12-15
	.2byte 0x14B7, 0x2E6E, 0x4CB9, 0x6FA2, 0x38F0, 0x719E, 0x475A, 0x1F3C
	.2byte 0x6AD8, 0x475B, 0x5199, 0x3264, 0x7B41, 0x49EF, 0x5198, 0x1CD7
@ Calculates two hash bits from 27 header bytes.
@ For each byte: rotate the running value right by 3, then XOR the byte into
@ all four byte lanes of the value. The result is bits 3-4 of the final value.
@ In: r0 = first byte (0x0800009D), r1 = count (27). Out: r0 = 0-3.
@ Clobbers r1-r3. Reads ROM directly (the copy does not exist yet).
@ GBATEK calls this "bytewise XORed, divided by 40h". The rotation makes the
@ result different: the two disagree for 215 of the 228 test ROMs in the
@ test-rom\GBA folder of DinoRec (both calculated in Python, not run on hardware).
header_hash:
	push {r4, r5, lr}
	movs r4, #3	@ rotation
	movs r3, #0	@ r3 = running value
hash_byte_loop:	@ each byte
	ldrb r2, [r0, #0]
	rors r3, r4
	movs r5, #4
hash_lane_loop:	@ XOR the byte in at bits 0, 8, 16 and 24
	eors r3, r2
	lsls r2, r2, #8
	.inst.n 0x1E6D	@ subs r5, r5, #1
	bgt hash_lane_loop
	.inst.n 0x1C40	@ adds r0, r0, #1
	.inst.n 0x1E49	@ subs r1, r1, #1
	bgt hash_byte_loop
	adds r0, r3, #0
	lsls r0, r0, #0x1B
	lsrs r0, r0, #0x1E	@ r0 = bits 3-4
	pop {r4, r5, pc}
@ Copies one 20-byte piece of the header from ROM + 4 + 20n to 0x03000088 + 20n,
@ as ten halfwords with CpuSet. In: r0 = n (0-10). Clobbers r0-r3.
copy_header_piece:
	push {r4, lr}
	movs r4, #0x14
	muls r4, r0	@ r4 = 20n
	movs r3, #8
	lsls r3, r3, #0x18	@ 0x08000000
	adds r0, r3, #4	@ header byte 0x04: the copy skips the entry branch
	adds r0, r0, r4
	ldr r1, header_copy_addr	@ =HEADER_COPY: from header byte 0x04
	adds r1, r1, r4
	movs r2, #0xA	@ CpuSet: 10 units, 16-bit, copy
	bl CpuSet
	pop {r4, pc}
@ Checks the logo against logo_reference, then the complement at 0xBD. 0 = good.
@ THE LOGO CHECK: header bytes 0x04-0x9F (156) must equal logo_reference, byte
@ for byte. First it masks two bytes, on the cartridge side only:
@   0x9C by 0x7B  bits 2 and 7 free: the GBATEK debug enable (0xA5 = on), which
@                 exception_handler reads
@   0x9E by 0xFC  bits 0-1 free: the key number that copy_cart_header uses
@ THE COMPLEMENT CHECK: 0x19 + the sum of header bytes 0xA0-0xBD (the last one
@ is the complement) must be 0 mod 256. The GBATEK formula agrees.
@ In: r0 = a header copy, from header byte 0x04 (0x03000088 from boot_intro;
@ EWRAM + 4 from MultiBoot, mb_slave_set_entry). Out: r0 = 0 good, 1 bad.
@ Clobbers r1-r3. Reads only memory; the caller decides what a failure means.
check_cart_header:
	push {r4, r5, r6, lr}
	ldr r1, logo_reference_pointer	@ =logo_reference: the correct logo
	movs r6, #0	@ r6 = offset from header byte 0x04
logo_check_loop:	@ each logo byte
	movs r4, #0xFF	@ r4 = mask for this byte
	cmp r6, #0x98
	bne logo_check_9e
	movs r4, #0x7B	@ header 0x9C
logo_check_9e:
	cmp r6, #0x9A
	bne logo_check_byte
	movs r4, #0xFC	@ header 0x9E
logo_check_byte:
	cmp r6, #0x9C
	bge complement_check	@ past 0x9F: the logo matches
	ldrb r2, [r0, r6]
	ldrb r3, [r1, r6]
	ands r2, r4
	.inst.n 0x1C76	@ adds r6, r6, #1
	cmp r2, r3
	beq logo_check_loop
	b header_check_bad	@ a logo byte differs: bad
complement_check:	@ complement check: r6 = 0x9C (header 0xA0)
	movs r4, #0x19	@ r4 = sum, start value 0x19
complement_sum_loop:
	ldrb r2, [r0, r6]
	adds r4, r4, r2
	.inst.n 0x1C76	@ adds r6, r6, #1
	cmp r6, #0xBA
	blt complement_sum_loop	@ up to header 0xBD
	lsls r0, r4, #0x18	@ low byte of the sum
	bne header_check_bad	@ not 0: bad
	movs r0, #0
	b header_check_done
header_check_bad:
	movs r0, #1
header_check_done:
	pop {r4, r5, r6, pc}
@ Resets the seven letters to the start of their flight: sets depth c of each
@ letter (word +8 of its 16-byte state at 0x03003580) to -0x7E (-126).
@ See boot_intro for what c does. Called once, before the first frame.
@ BAKED IN: 7 letters, the 0x78 bound (8 + 7 x 16). It does not set slot 7:
@ 0x03003580 + 0x70 is the affine block of the first letter (0x030035F0).
@ In: nothing. Clobbers r0, r2, r3.
intro_reset_letters:
	ldr r3, letter_states_addr	@ =LETTER_STATES: letter states, 16 bytes each
	movs r2, #8	@ offset of c in slot 0
	movs r0, #0x7E
	negs r0, r0	@ r0 = -126: depth 2 (the start)
reset_letters_loop:
	str r0, [r3, r2]
	adds r2, #0x10
	cmp r2, #0x78
	blt reset_letters_loop	@ slots 0-6
	bx lr
@ Calculates the path of a letter for frame t of its flight: X and Y in 1/256
@ pixels at depth 128 (full size), relative to the screen centre.
@   X = (n - 3) x (4t(64 - t) - 6144)
@   Y = 26t(t - 72) + 0x6800, only while t <= 47. After that, Y does not change.
@ Slot 3 (E) is the middle slot, so X is always 0 for it. At t = 63 (landed),
@ X = (3 - n) x 23.02 px and Y = -15.3 px: 23 pixels between letters, and Y is
@ 64 on the screen. Y is the same curve for every letter: the letters come up
@ from below and settle. X starts wide, closes in, then opens to the final spacing.
@ In: r0 = slot n (0 = Y ... 6 = G), r1 = its state (0x03003580 + 16n),
@ r2 = t (its timer). Out: state +0 X, +4 Y. Clobbers r0, r3.
@ BAKED IN: the 3 (middle of 7 letters), the spacing (6144, and 4t(64-t),
@ which is 252 at t = 63), and t = 47 and 63 (see c in boot_intro).
intro_letter_path:
	push {r6, lr}
	subs r3, r0, #3
	lsls r6, r3, #2
	muls r6, r2
	movs r3, #0x40
	subs r3, r3, r2
	muls r6, r3	@ r6 = 4(n - 3) t (64 - t)
	.inst.n 0x1EC0	@ subs r0, r0, #3
	movs r3, #0x18
	muls r3, r0
	lsls r3, r3, #8	@ r3 = 24 x 256 x (n - 3)
	subs r6, r6, r3
	str r6, [r1, #0]	@ X
	cmp r2, #0x2F
	bgt letter_path_return	@ t > 47: Y does not change
	movs r6, #0x1A
	muls r6, r2
	subs r2, #0x48
	muls r6, r2	@ 26t (t - 72)
	movs r3, #0x68
	lsls r3, r3, #8
	adds r6, r6, r3	@ + 0x6800 (104 px)
	str r6, [r1, #4]	@ Y
letter_path_return:
	pop {r6, pc}
@ Projects a letter onto the screen. z = c + 128 is its depth: 2 at the start,
@ 128 when it lands. An object at depth z shows at 128/z times its size, and
@ its offset from the centre scales by the same factor.
@ In: r0 = its state (X, Y, c: words +0, +4, +8), r1 = its 20-byte affine
@ block (0x030035F0 + 20n), with the layout of the BgAffineSet source:
@   +0, +4  words 0x3F80 (63.5 in 8.8): written here, read by nothing
@   +8      halfword: screen X of the letter centre = 120 + (X>>8) x 128/z
@   +0xA    halfword: screen Y of the centre        =  80 + (Y>>8) x 128/z
@   +0xC    halfword: scale X = 2z (8.8: 1.0 at z = 128; 1/64 at the start)
@   +0xE    halfword: scale Y = 2z
@   +0x10   halfword: angle. Never written here: 0 (from RegisterRamReset).
@ boot_intro gives block + 0xC to ObjAffineSet (scale X, Y, angle), so a letter
@ does not turn. An angle written at +0x10 would turn it.
@ Out: the block. Clobbers r0-r3 (thumb_Div). z must not be 0: c > -128.
intro_letter_affine:
	push {r4, r5, r6, r7, lr}
	adds r7, r1, #0	@ r7 = block
	ldmia r0!, {r4, r5, r6}	@ r4 = X, r5 = Y, r6 = c
	adds r6, #0x80	@ r6 = z
	adds r1, r6, #0
	movs r0, #0x80
	lsls r0, r0, #0x10
	bl thumb_Div	@ r0 = 0x800000 / z: 128/z in 16.16
	lsls r3, r6, #1
	strh r3, [r7, #0xC]	@ scale X
	strh r3, [r7, #0xE]	@ scale Y
	movs r1, #0x7F
	lsls r1, r1, #7	@ 0x3F80
	str r1, [r7, #0]
	str r1, [r7, #4]
	asrs r1, r4, #8
	muls r1, r0
	asrs r1, r1, #0x10
	adds r1, #0x78	@ + 120 (screen centre)
	strh r1, [r7, #8]	@ screen X
	asrs r1, r5, #8
	muls r1, r0
	asrs r1, r1, #0x10
	adds r1, #0x50	@ + 80
	strh r1, [r7, #0xA]	@ screen Y
	pop {r4, r5, r6, r7, pc}
@ Fills a rectangle of halfwords with a counting value: r3 rows of r2 bytes
@ (r2/2 halfwords). The value increases by r1 for each halfword. The rows are
@ r5 bytes apart. Used for the BG3 map (intro_load_graphics) and the Game Boy
@ screen (start_cgb_cartridge, system.s).
@ In: r0 = first value, r1 = step, r2 = row width in bytes (even), r3 = rows,
@ [sp] = destination, [sp + 4] = row pitch in bytes (on the stack of the
@ caller: [sp + 0x14] and [sp + 0x18] after the push).
@ Out: r0 = the next value. Clobbers r0.
fill_2d:
	push {r4, r5, r6, r7, lr}
	ldr r4, [sp, #0x14]	@ destination
	ldr r5, [sp, #0x18]	@ pitch
	movs r7, #0	@ r7 = row
fill_2d_row:
	movs r6, #0	@ r6 = byte offset in the row
fill_2d_column:
	strh r0, [r4, r6]
	adds r0, r0, r1
	.inst.n 0x1CB6	@ adds r6, r6, #2
	cmp r6, r2
	blt fill_2d_column
	adds r4, r4, r5
	.inst.n 0x1C7F	@ adds r7, r7, #1
	cmp r7, r3
	blt fill_2d_row
	pop {r4, r5, r6, r7, pc}
@ Interpolates between two sets of three colours in intro_colors.
@ intro_colors is words. Each word is a colour with its parts spread out (red
@ bits 0-4, green 10-14, blue 20-24), so a blend of two, x up to 32, cannot
@ carry from one part into the next. Set s is words 3s+1 to 3s+3 (word 0 is
@ never read). This function writes, as BGR555, for i = 2, 1, 0:
@   OBJ colour r2 + i = (colour i of set r0) x (32 - t)/32
@                     + (colour i of set r0+1) x t/32
@ t = 0 gives set r0, t = 32 gives set r0 + 1.
@ In: r0 = set (0-6 to stay in the table), r1 = t (0-32), r2 = the first OBJ
@ colour (4k + 1 for the letter in cell k). Clobbers r0-r3.
@ Callers: boot_intro (the flight and pulse of a letter; the logo when Select
@ and Start are held) and MultiBoot (the logo, colour 31, during a transfer).
intro_fade_colors:
	push {r4, r5, r6, r7, lr}
	movs r7, #2	@ r7 = i, colour in the set: 2, 1, 0
fade_colors_loop:
	ldr r4, intro_colors_pointer	@ =intro_colors: colour sets
	lsls r3, r0, #1
	adds r3, r3, r0
	adds r3, r3, r7
	lsls r3, r3, #2
	adds r3, r3, r4	@ r3 = &word[3 x set + i]
	ldr r5, [r3, #4]	@ r5 = word 3s+i+1: colour i of set s
	ldr r6, [r3, #0x10]	@ r6 = word 3s+i+4: colour i of set s+1
	movs r3, #0x20
	subs r3, r3, r1
	muls r3, r5
	muls r6, r1
	adds r3, r3, r6
	lsrs r4, r3, #5	@ r4 = blend, parts still spread out
	movs r6, #0x1F
	lsls r3, r6, #0x14
	ands r3, r4
	lsrs r5, r3, #0xA	@ blue: bits 20-24 to 10-14
	lsls r3, r6, #0xA
	ands r3, r4
	lsrs r3, r3, #5	@ green: bits 10-14 to 5-9
	orrs r3, r5
	ands r4, r6	@ red stays in bits 0-4
	orrs r4, r3
	adds r3, r2, r7
	lsls r6, r3, #1
	ldr r3, obj_palette_addr	@ =PLTT + 0x200: OBJ palette
	adds r3, r6, r3
	strh r4, [r3, #0]	@ OBJ colour r2 + i
	.inst.n 0x1E7F	@ subs r7, r7, #1
	bge fade_colors_loop
	pop {r4, r5, r6, r7, pc}
@ SWI 0x19
@ SoundBias: moves the SOUNDBIAS bias level to 0 (r0 = 0) or 0x200 (r0 any
@ other value). GBATEK: it moves one step at a time, with short delays, and
@ keeps the other bits. On the GBA, the delay count is a fixed 8.
@ The code reads the level as bits 0-9 (bit 0 is unused). Each step adds or
@ subtracts 2 (1 in the level field, bits 1-9). Then it counts r2 from 8 to -1
@ (9 loops) before it reads the level again. It moves toward the target only
@ from the expected side: when the target is 0x200, a level already above
@ 0x200 stays there. In: r0. Out: nothing. Clobbers r1-r3, ip.
@ boot_intro calls it with 1 at the start of the intro.
SoundBias:
	movs r1, #2
	lsls r1, r1, #8
	mov ip, r1	@ ip = 0x200 (high level)
	ldr r3, soundbias_addr	@ =REG_SOUNDBIAS
	ldrh r2, [r3, #0]
	ldr r3, soundbias_addr	@ =REG_SOUNDBIAS
	lsls r1, r2, #0x16
	lsrs r1, r1, #0x16	@ r1 = bits 0-9: the level
	cmp r0, #0
	beq soundbias_down	@ target 0: move down
	cmp r1, ip
	bge soundbias_done	@ at (or above) 0x200: done
	.inst.n 0x1C92	@ adds r2, r2, #2
	b soundbias_step
soundbias_down:
	cmp r1, #0
	ble soundbias_done	@ at 0: done
	.inst.n 0x1E92	@ subs r2, r2, #2
soundbias_step:
	strh r2, [r3, #0]
	movs r2, #8
soundbias_delay:	@ delay loop
	.inst.n 0x1E52	@ subs r2, r2, #1
	bpl soundbias_delay
	b SoundBias	@ repeat from the start
soundbias_done:
	bx lr
@ Copies gameboy_art (still packed) to 0x03000564, where intro_load_graphics
@ decodes it. Tail-calls copy_bios_data; clobbers r0-r3.
load_gameboy_art:
	ldr r1, work_buffer_a_addr	@ =WORK_BUF_A: scratch, start of the decodes
	@ Bytes to copy, in units of 16: the size of the art, rounded up. The
	@ retail BIOS has 0x37 here (880 bytes, exactly its art). This expression
	@ follows the art in assets/, and assembles to the same value for the
	@ retail art.
	movs r2, #(gameboy_art_end - gameboy_art + 15) >> 4
	lsls r2, r2, #4
	ldr r0, gameboy_art_pointer	@ =gameboy_art: the packed GAME BOY art
	b copy_bios_data
@ Copies logo_tree (the Huffman header and tree, 36 bytes) to 0x03000564.
@ decode_cart_logo then puts the 156 logo bytes of the header directly after it.
@ Tail-calls copy_bios_data; clobbers r0-r3.
load_logo_tree:
	ldr r1, work_buffer_a_addr	@ =WORK_BUF_A: scratch, Huffman input for the logo
	movs r2, #0x24
	ldr r0, logo_tree_pointer	@ =logo_tree
	b copy_bios_data
@ Copies intro_oam (ten sprites, 80 bytes) to OAM entries 0-9. The fourth
@ halfword of each entry is an OAM affine parameter. Those of entries 0-3 make
@ group 0 (PA 1.0, PB 0.25, PC 0, PD 0). Only the ball sprite (entry 9) uses
@ group 0: it is the streak across the logo (see boot_intro). Groups 1-7 are
@ for the letters; ObjAffineSet writes them each frame.
@ Tail-calls copy_bios_data; clobbers r0-r3.
load_intro_oam:
	movs r1, #7
	lsls r1, r1, #0x18	@ 0x07000000, OAM
	movs r2, #0x50
	ldr r0, intro_oam_pointer	@ =intro_oam: the ten sprites
	b copy_bios_data
@ Copies intro_palette (4 colours) to colours 28-31 of the BG palette (r0 = 0)
@ or of the OBJ palette (r0 = 1, 0x200 bytes later). These are the colours of
@ the ball (cell 7: 29-31; 28 is its transparent 0). Colour 31 is also the
@ colour of the Nintendo logo (logo_unpack). Falls into copy_bios_data;
@ clobbers r0-r3.
load_intro_palette:
	ldr r1, intro_palette_dest	@ =PLTT + 0x38: BG colour 28
	cmp r0, #0
	beq intro_palette_copy
	lsls r0, r0, #9
	adds r1, r1, r0	@ + 0x200: OBJ colour 28
intro_palette_copy:
	movs r2, #8
	ldr r0, intro_palette_pointer	@ =intro_palette: four colours
@ Copies words, but only from the BIOS data at 0x3200 and up.
@ The source range is intro_colors (a label: 0x3200 in the retail BIOS) to the
@ end of the BIOS, 0x4000. It copies words until r1 reaches r1 + r2. At the
@ first source address outside the range, it stops without a copy of that word.
@ Why it checks is not known. The effect: it can copy BIOS data but not BIOS
@ code, so all data that it copies must be at or after intro_colors.
@ In: r0 = source, r1 = destination, r2 = bytes. It copies whole words: a count
@ that is not a multiple of 4 copies up to 3 bytes more.
@ Clobbers r0-r3.
copy_bios_data:
	push {r4, r5, lr}
	adds r2, r2, r1	@ r2 = end address
copy_bios_data_loop:
	ldr r3, intro_colors_pointer	@ =intro_colors: lowest source address
	cmp r0, r3
	blt copy_bios_data_done
	movs r3, #4
	lsls r3, r3, #0xC
	cmp r0, r3	@ 0x4000: end of the BIOS
	bge copy_bios_data_done
	ldmia r0!, {r3}
	stmia r1!, {r3}
	cmp r1, r2
	blt copy_bios_data_loop
copy_bios_data_done:
	pop {r4, r5, pc}
@ Loads all graphics of the intro, once, before the first frame of boot_intro.
@ Order (see the file header): the dummy read, copy_cart_header, the 0x96
@ check, the GAME BOY art, the cartridge logo, the BG3 map, the palettes, OAM.
@ In: nothing. Out: nothing. Clobbers r0-r3.
@ Writes:
@   0x03000088-0x03000163  the header copy
@   0x03000564-0x03002563  scratch
@   VRAM                   BG tiles, the BG3 map, OBJ VRAM
@   palettes               BG colour 0; colours 28-31 of both palettes
@   OAM                    entries 0-9
@   INTRO_FLAG             = 0x88
@ Stack: [sp] and [sp+4] = arguments for fill_2d; [sp+8] and [sp+0xC] = a copy
@ of intro_letter_unpack (the BitUnPack parameters); [sp+0x10] = a fill word.
@ BAKED IN: 8 cells (cmp r7, #8; movs r7, #0xE), 4 rows of 4 tiles per cell.
intro_load_graphics:
	push {r4, r5, r6, r7, lr}
	sub sp, #0x14
	ldr r1, intro_letter_unpack_pointer	@ =intro_letter_unpack: BitUnPack parameters
	ldmia r1!, {r5, r7}
	add r0, sp, #8
	stmia r0!, {r5, r7}	@ to [sp+8]; the offset word changes per cell
	@ Reads 20 bytes near the top of the cartridge space, through the
	@ wait-state-1 mirror (0x0A000000 = ROM), into 0x03000564.
	@ load_gameboy_art overwrites them immediately after.
	@ Header 0xB4 bit 7 selects the address. It also selects the debugger
	@ address in exception_handler: 0x09FE1FE0 is 0x20 before its 0x09FE2000.
	@ Probably a signal to debugging hardware (DACS in GBATEK); not known.
	ldr r0, dacs_1mbit_probe_addr	@ =0x0BFE1FE0 (WS1 mirror of 0x09FE1FE0): bit 7 set
	ldr r3, header_b4_addr	@ =ROM + 0xB4: header device type
	ldrb r3, [r3, #0]
	lsrs r3, r3, #7
	bne debug_dummy_read
	ldr r0, dacs_8mbit_probe_addr	@ =0x0BFFFFE0: last 32 bytes of WS1 (bit 7 clear)
debug_dummy_read:
	ldr r1, work_buffer_a_addr	@ =WORK_BUF_A: scratch (overwritten next)
	movs r2, #0xA	@ CpuSet: 10 halfwords
	bl CpuSet
	bl copy_cart_header
	@ THE 0x96 CHECK. The copy starts at header 0x04, so + 0xAE is 0xB2.
	ldr r1, header_copy_addr	@ =HEADER_COPY: the header copy
	adds r3, r1, #0
	adds r3, #0xAE
	ldrb r0, [r3, #0]
	cmp r0, #0x96
	beq unpack_gameboy_art	@ 0x96: do not change the logo
	@ Not 0x96: fill the logo in the copy (0x04-0x9F) with 0xFF. The fill word,
	@ 0xFFFFFFFF, is the sign of the CpuSet mode word (bit 31 set).
	ldr r2, blank_logo_cpuset	@ =0x85000027: 32-bit fill, 0x27 words (156 bytes)
	asrs r3, r2, #0x1F
	str r3, [sp, #0x10]
	add r0, sp, #0x10
	bl CpuSet	@ r1 is still 0x03000088
unpack_gameboy_art:
	@ The GAME BOY art: packed to 0x03000564, Huffman to 0x03001564, LZ77 back
	@ to 0x03000564. Result: 2 KiB of 2bpp, 256 bytes per cell.
	bl load_gameboy_art
	ldr r0, work_buffer_a_addr	@ =WORK_BUF_A: the packed art
	ldr r1, work_buffer_b_addr	@ =WORK_BUF_B: scratch, Huffman output
	bl thumb_HuffUnComp
	ldr r0, work_buffer_b_addr	@ =WORK_BUF_B: LZ77 data
	ldr r1, work_buffer_a_addr	@ =WORK_BUF_A: the 2bpp art
	bl thumb_LZ77UnCompWram
	@ Unpack each cell k to 8bpp at VRAM + 0x40 + k x 0x400, and add 4k to its
	@ non-zero pixels: the three greys of cell k become colours 4k+1 to 4k+3.
	@ BitUnPack reads 512 bytes (intro_letter_unpack), which is two cells. Thus
	@ each pass also writes 1 KiB for the next cell, and the next pass writes it
	@ again. The second KiB of the last pass (VRAM + 0x2040) is from past the art.
	movs r7, #0	@ r7 = cell k
unpack_cell_loop:
	lsls r0, r7, #2
	str r0, [sp, #0xC]	@ offset: 4k
	ldr r2, work_buffer_a_addr	@ =WORK_BUF_A: the 2bpp art
	lsls r0, r7, #8
	adds r0, r0, r2	@ the 256 bytes of cell k
	ldr r3, letter_unpack_vram	@ =VRAM + 0x40: BG tile 1, for cell 0
	lsls r1, r7, #0xA
	adds r1, r1, r3	@ + 1 KiB per cell
	add r2, sp, #8
	bl thumb_BitUnPack
	.inst.n 0x1C7F	@ adds r7, r7, #1
	cmp r7, #8
	blt unpack_cell_loop	@ BAKED IN: 8 cells
	@ Copy each cell to OBJ VRAM, one row of four tiles (256 bytes) at a time.
	@ Row r of cell k goes to OBJ_VRAM + (intro_letter_tiles[k] + 16r) x 64.
	@ 16 units of 64 bytes = 1 KiB = one row of the 2D mapping.
	movs r7, #0xE	@ r7 = 2k, k = 7 to 0 (intro_letter_tiles is halfwords)
copy_cell_loop:
	movs r4, #3	@ r4 = r, the tile row: 3 to 0
copy_cell_row_loop:
	ldr r3, letter_unpack_vram	@ =VRAM + 0x40: the 8bpp cells
	lsls r0, r7, #1
	adds r0, r0, r4
	lsls r0, r0, #8
	adds r0, r0, r3	@ VRAM + 0x40 + k x 0x400 + r x 0x100
	ldr r3, intro_letter_tiles_pointer	@ =intro_letter_tiles: OBJ tile per cell
	ldrh r2, [r3, r7]
	ldr r3, obj_vram_addr	@ =OBJ_VRAM
	lsls r1, r4, #4
	adds r1, r1, r2
	lsls r1, r1, #6
	adds r1, r1, r3
	movs r2, #0x80	@ CpuSet: 128 halfwords, 256 bytes
	bl CpuSet
	.inst.n 0x1E64	@ subs r4, r4, #1
	bge copy_cell_row_loop
	.inst.n 0x1EBF	@ subs r7, r7, #2
	bge copy_cell_loop	@ BAKED IN: 8 cells (0xE = 2 x 7)
	@ The Nintendo logo of the cartridge, from the header copy. Thus a logo
	@ that the 0x96 check blanked is drawn blank.
	ldr r0, header_copy_addr	@ =HEADER_COPY: the logo in the header copy
	bl decode_cart_logo
	bl unpack_cart_logo
	bl place_cart_logo
	@ The BG3 map (256x256 affine, 1 byte per entry, at VRAM + 0xB800): 4 rows
	@ of 4 entries from row 4 (+ 0x80), tiles 0x71-0x80. This is cell 7 (the
	@ ball) as a 32x32 BG at BG pixels (0-31, 32-63). Each halfword is two
	@ entries, so the values are 0x7271, then + 0x0202 each. The rest of the
	@ map is 0, and tile 0 is blank.
	movs r2, #0x20
	str r2, [sp, #4]	@ pitch: 32 entries per row
	ldr r1, ball_bg3_map	@ =VRAM + 0xB880: BG3 map (0xB800), row 4
	str r1, [sp, #0]
	movs r3, #4	@ 4 rows
	movs r2, #4	@ of 4 bytes
	ldr r1, ball_bg3_map_step	@ =0x00000202: fill_2d step, + 2 per entry
	ldr r0, ball_bg3_map_first	@ =0x00007271: first two entries, tiles 0x71, 0x72
	bl fill_2d
	movs r1, #5
	lsls r1, r1, #0x18	@ 0x05000000, BG colour 0
	mvns r0, r1
	strh r0, [r1, #0]	@ = 0xFFFF: white backdrop (bit 15 is ignored)
	movs r0, #0
	bl load_intro_palette	@ BG colours 28-31
	movs r0, #1
	bl load_intro_palette	@ OBJ colours 28-31
	bl load_intro_oam
	add sp, #0x14
	pop {r4, r5, r6, r7, pc}
@ Decodes logo_tree + the logo of a header: Huffman, then Diff16.
@   1. Puts the 36 bytes of logo_tree and the 156 logo bytes at r0 together
@      at 0x03000564.
@   2. Huffman-decodes them to 0x03001564 (212 bytes).
@   3. Replaces the first word of the result with a Diff16 header (0xD082:
@      16-bit units, 208 bytes).
@   4. Unfilters it back to 0x03000564: 208 bytes of 1bpp. This is the logo as
@      26 tiles of 8 bytes (13 across, then 13 more), 104x16.
@ In: r0 = the logo of a header (header byte 0x04): 0x03000088 from
@ intro_load_graphics, EWRAM + 4 from MultiBoot (a received header).
@ Out: r0 unchanged. Clobbers r1-r3.
@ Writes INTRO_FLAG = low byte of r0 (0x88 here, 0x04 from MultiBoot). The wait
@ loop of boot_intro clears INTRO_FLAG first. Then it takes a non-zero value to
@ mean that a MultiBoot header has arrived.
decode_cart_logo:
	push {r0, r4, r5, r6, r7, lr}
	ldr r4, intro_flag_addr	@ =INTRO_FLAG: BIOS RAM byte, "intro/Nintendo logo related"
	strb r0, [r4, #0]
	bl load_logo_tree
	ldr r0, [sp, #0]	@ the logo
	ldr r1, logo_bits_buffer	@ =LOGO_BITS: 0x03000564 + 36 (after the tree)
	movs r2, #0x4E	@ CpuSet: 78 halfwords, 156 bytes
	bl CpuSet
	ldr r0, work_buffer_a_addr	@ =WORK_BUF_A: tree + logo, Huffman
	ldr r1, work_buffer_b_addr	@ =WORK_BUF_B: Huffman output
	bl thumb_HuffUnComp
	ldr r0, work_buffer_b_addr	@ =WORK_BUF_B
	ldr r2, logo_diff16_header	@ =0x0000D082: Diff16, 16-bit, 0xD0 (208) bytes
	str r2, [r0, #0]	@ over the first 4 bytes of the decoded data
	ldr r1, work_buffer_a_addr	@ =WORK_BUF_A: the 1bpp logo
	bl Diff16bitUnFilter
	pop {r0, r4, r5, r6, r7, pc}
@ Unpacks the 1bpp logo at 0x03000564 to 8bpp at 0x03001564. Set pixels become
@ colour 31, clear pixels 0 (logo_unpack). It unpacks 448 bytes, more than the
@ 208 of the logo; the rest is not used. In: nothing. Out: r0 unchanged.
@ Clobbers r1-r3. MultiBoot calls it separately, one frame after decoding.
unpack_cart_logo:
	push {r0, r4, r5, r6, r7, lr}
	ldr r0, work_buffer_a_addr	@ =WORK_BUF_A: the 1bpp logo
	ldr r1, work_buffer_b_addr	@ =WORK_BUF_B: the 8bpp logo
	ldr r2, logo_unpack_pointer	@ =logo_unpack: BitUnPack parameters for the logo
	bl thumb_BitUnPack
	pop {r0, r4, r5, r6, r7, pc}
@ Puts the 8bpp logo where OAM entries 7 and 8 show it:
@   1. Stages it in BG VRAM with the layout of the OBJ VRAM 2D mapping: the 13
@      top tiles (832 bytes) at VRAM + 0x24C0, the 13 bottom tiles 1 KiB later.
@      Both start 2 tiles into a 1 KiB row (VRAM + 0x2440 and 0x2840).
@   2. Copies those rows and the empty row after them (0x2C40) to
@      OBJ_VRAM + 0x6C00-0x77FF, rows 27-29.
@   3. Writes the scratch (see below).
@ Entries 7 and 8 (64x32, tiles 0x340 and 0x350) cover rows 26-29. Thus the
@ logo is at pixels 16-119 across and 8-23 down in the pair. On the screen it is
@ at X 71-174, Y 110-125 (intro_oam puts the entries at X 55 and 119, Y 102).
@ In: nothing. Out: r0 = 0 (see below). Clobbers r1-r3.
@ MultiBoot calls it separately, one frame after unpacking.
place_cart_logo:
	push {r0, r4, r5, r6, r7, lr}
	ldr r6, work_buffer_b_addr	@ =WORK_BUF_B: the 8bpp logo, tile by tile
	ldr r4, logo_stage_vram	@ =VRAM + 0x24C0: staging, 2 tiles into the row at 0x2440
	movs r7, #2	@ r7 = tile rows: 2
stage_logo_row:
	movs r5, #0x34	@ r5 = 52 blocks of 16 bytes (13 tiles of 64)
stage_logo_block:
	ldmia r6!, {r0, r1, r2, r3}
	stmia r4!, {r0, r1, r2, r3}
	.inst.n 0x1E6D	@ subs r5, r5, #1
	bgt stage_logo_block
	adds r4, #0xC0	@ same place in the next row (+ 1 KiB)
	.inst.n 0x1E7F	@ subs r7, r7, #1
	bgt stage_logo_row
	movs r7, #3	@ r7 = 3, 2, 1: the rows at 0x2C40, 0x2840, 0x2440
copy_logo_row_loop:
	lsls r3, r7, #0xA
	ldr r0, logo_copy_src_vram	@ =VRAM + 0x2040: + r7 KiB, the staged row
	adds r0, r0, r3
	ldr r1, logo_copy_dest_vram	@ =OBJ_VRAM + 0x6800: OAM 7-8 tiles, + r7 KiB
	adds r1, r1, r3
	movs r2, #1
	lsls r2, r2, #8	@ CpuFastSet: 0x100 words, 1 KiB
	bl thumb_CpuFastSet
	.inst.n 0x1E7F	@ subs r7, r7, #1
	bgt copy_logo_row_loop
	@ This looks meant to clear the 8 KiB of scratch at 0x03000564. It stores 0
	@ at [sp] as a fill value and calls cpufastset_from_sp (memory.s), which
	@ uses sp as the source and ORs r5 into the mode. RegisterRamReset passes
	@ r5 = 0x85000000 (a fill). Here r5 is 0 (the stage_logo_block loop counts it
	@ down to 0), so the mode is 0x800: a COPY of 8 KiB from the stack. The copy
	@ continues through the top of IWRAM into its mirror, onto 0x03000564-0x03002563. Seen in DinoRec: 0x03000564 then
	@ holds the stack. This is harmless in the retail intro, because nothing
	@ reads that scratch after this. But do not keep data there. It also puts
	@ 0 in the pushed r0, so this function returns r0 = 0.
	mov r0, sp
	str r7, [r0, #0]	@ [sp] = 0 (r7 is 0), over the pushed r0
	ldr r1, work_buffer_a_addr	@ =WORK_BUF_A: the scratch
	movs r2, #8
	lsls r2, r2, #8	@ 0x800: 8 KiB of words
	bl cpufastset_from_sp
	pop {r0, r4, r5, r6, r7, pc}
