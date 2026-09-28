@ memory.s 0x09C2-0x0C2B: the memory SWIs.
@   RegisterRamReset  SWI 0x01, Thumb: clears the RAM and resets the I/O registers
@                     that its flags select. Each block goes through rrr_clear. If the
@                     flag of the block is set, rrr_clear makes CpuFastSet fill it from
@                     a zero word on the stack (cpufastset_from_sp).
@   CpuSet            SWI 0x0B, Thumb: copy or fill in halfwords or words.
@   CpuFastSet        SWI 0x0C, ARM: copy or fill in 32-byte blocks. Thumb code calls
@                     it through thumb_CpuFastSet.
@   check_range       ARM: the read protection of CpuSet and CpuFastSet. It silently
@                     refuses a source that starts or ends below 0x02000000 (the BIOS).
@                     cpuset_check_range is the Thumb entry. decompress.s uses
@                     both; multiboot.s uses cpuset_check_range.
@ In the middle is a literal pool (boot_serial_irq_pointer-iwram_clear_words), shared
@ with the neighbours: boot_irq (system.s) loads the first two, header.s most of the
@ others, and RegisterRamReset the last four. The comment on each .4byte says what it
@ is and which code reads it.
@ RAM: RegisterRamReset clears, by its flags, EWRAM, IWRAM up to 0x03007DFF, palette
@   RAM, VRAM and OAM. It keeps its zero word in its own stack frame. CpuSet and
@   CpuFastSet change only the memory they are given.
@ I/O: RegisterRamReset, by its flags: DISPCNT (always); the display, window and blend
@   registers, DMA, timers, KEYCNT, IE, IF, WAITCNT and IME; SIO, RCNT and JOY BUS;
@   the sound registers and wave RAM. The code below lists them block by block.

@ SWI 0x01
@
@ RegisterRamReset SWI 0x01: resets the I/O registers and memory that r0 selects.
@ In: r0 = flags (the GBATEK list; each is done only if set):
@       bit 0  EWRAM, 256 KiB              bit 4  OAM, 1 KiB (all zero: GBATEK notes
@       bit 1  IWRAM 0x03000000-0x03007DFF         this does not hide the sprites)
@       bit 2  palette RAM, 1 KiB          bit 5  SIO and JOY BUS registers
@       bit 3  VRAM, 96 KiB                bit 6  sound registers
@                                          bit 7  the rest of the I/O registers
@ Always, for all values of r0: DISPCNT = 0x0080, forced blank (GBATEK: the screen goes
@ white). Also, if bit 5 is clear, the low byte of SIODATA32 = 7. This is the GBATEK
@ bug. It comes from the value that rrr_clear leaves in r1 (see rrr_sio).
@ Order: bit 7, 5, 6, then memory: EWRAM, VRAM, OAM, palette, IWRAM.
@ Out: nothing. r0-r3 changed, r4-r7 kept.
@ Care (inferred, not run): bit 0 clears EWRAM, so do not call it from code that runs
@ in EWRAM (GBATEK says the same). Bit 1 keeps 0x03007E00-0x03007FFF. The registers
@ that this function saves are in that area only if the System stack of the caller
@ (from 0x03007F00) is less than about 0xE0 bytes deep. If it is deeper, the function
@ would erase its own return address.
RegisterRamReset:
	.thumb
	push {r4, r5, r6, r7, lr}
	sub sp, #4	@ one word: the zero that CpuFastSet fills from
	adds r7, r0, #0	@ r7 = the flags, for rrr_clear
	ldr r5, rrr_fill_mode	@ =0x85000000, ORed into each length (bit 24: CpuFastSet fills)
	movs r4, #4
	lsls r4, r4, #0x18	@ r4 = 0x04000000, I/O
	movs r3, #0
	str r3, [sp, #0]	@ the zero
	movs r1, #0x80
	strh r1, [r4, #0]	@ DISPCNT = 0x0080: forced blank, always
	movs r6, #0x80	@ bit 7: the rest of the I/O registers
	tst r6, r7
	beq rrr_sio
	@ From here to rrr_sio, each step needs the fill before it to have run (its flag is
	@ set). CpuFastSet leaves r1 = the end of what it filled, and r2 = 0 (its fill word).
	lsrs r1, r4, #0x11
	adds r1, r1, r4	@ r1 = 0x04000200
	movs r2, #8
	bl rrr_clear	@ 0x04000200-0x0400021F = 0: IE, IF, WAITCNT, IME
	subs r1, #0x20	@ r1 = 0x04000200 again
	mvns r0, r2	@ r0 = 0xFFFFFFFF
	strh r0, [r1, #2]	@ IF = 0xFFFF: acknowledge all pending IRQs
	lsrs r1, r4, #0x10
	adds r1, r1, r4	@ r1 = 0x04000400
	strb r0, [r1, #0x10]	@ 0x04000410 = 0xFF (GBATEK: purpose unknown, probably a bug)
	adds r1, r4, #4	@ r1 = 0x04000004
	movs r2, #8
	bl rrr_clear	@ 0x04000004-0x04000023: DISPSTAT, BG0CNT-BG3CNT, scrolls, BG2PA, BG2PB
	.inst.n 0x1F09	@ subs r1, r1, #4 (0x04000024 to 0x04000020)
	movs r2, #0x10
	bl rrr_clear	@ 0x04000020-0x0400005F: BG2 and BG3 affine, windows, MOSAIC, blending
	movs r1, #0xB0
	adds r1, r1, r4	@ r1 = 0x040000B0
	movs r2, #0x18
	bl rrr_clear	@ 0x040000B0-0x0400010F: DMA0-DMA3 (stopped), then TM0-TM3
	str r2, [r1, #0x20]	@ r1 = 0x04000110: 0x04000130 = 0, KEYCNT (KEYINPUT is read-only)
	lsrs r0, r4, #0x12	@ r0 = 0x100: 1.0 in 8.8
	strh r0, [r4, #0x20]	@ BG2PA
	strh r0, [r4, #0x30]	@ BG3PA
	strh r0, [r4, #0x26]	@ BG2PD
	strh r0, [r4, #0x36]	@ BG3PD: BG2 and BG3 unscaled and unrotated
@ bit 5: SIO. The code after the clear uses r1 and r2 as rrr_clear leaves them. This
@ is correct only if the clear ran. If bit 5 is clear, r1 is still 0x04000110 and r2
@ is 8: the RCNT write goes to unused 0x04000114, and the JOYCNT write goes to
@ 0x04000120 (the low byte of SIODATA32 = 7). That is the bug that GBATEK reports.
rrr_sio:
	movs r6, #0x20	@ bit 5: SIO
	ldr r1, rrr_sio_start	@ =0x04000110
	movs r2, #8
	bl rrr_clear	@ 0x04000110-0x0400012F: SIODATA32 / SIOMULTI0-3, SIOCNT, SIOMLT_SEND
	lsrs r2, r4, #0xB	@ r2 = 0x8000
	strh r2, [r1, #4]	@ RCNT (0x04000134) = 0x8000: general-purpose mode, all inputs
	adds r1, #0x10	@ r1 = 0x04000140, JOYCNT
	movs r2, #7
	strb r2, [r1, #0]	@ JOYCNT = 7: acknowledge its three flags (write 1 to clear)
	bl rrr_clear	@ 7 words, rounded up to 8: 0x04000140-0x0400015F, JOYCNT to JOYSTAT
	movs r6, #0x40	@ bit 6: sound
	tst r6, r7
	beq rrr_memory
	movs r1, #0x80
	adds r1, r1, r4	@ r1 = 0x04000080, SOUNDCNT_L
	ldr r0, rrr_soundcnt	@ =0x880E0000, SOUNDCNT_L and _H as one word
	@ master off zeroes the PSG registers, 0x04000060-0x04000081 (GBATEK)
	strb r0, [r1, #4]	@ SOUNDCNT_X = 0x00 (the low byte of r0): master off
	strb r1, [r1, #4]	@ SOUNDCNT_X = 0x80 (the low byte of r1): master on again
	str r0, [r1, #0]	@ SOUNDCNT_L = 0, SOUNDCNT_H = 0x880E (see rrr_soundcnt)
	ldrh r0, [r1, #8]
	lsls r0, r0, #0x16
	lsrs r0, r0, #0x16
	strh r0, [r1, #8]	@ SOUNDBIAS: bias (bits 0-9) kept, resolution 0 (9-bit, 32 kHz)
	subs r1, #0x10	@ r1 = 0x04000070, SOUND3CNT_L
	strb r1, [r1, #0]	@ = 0x70 (the low byte of r1): 2 banks, bank 1 plays, 0x90 is bank 0
	adds r1, #0x20	@ r1 = 0x04000090, WAVE_RAM
	movs r2, #8
	bl rrr_clear	@ 0x04000090-0x040000AF: wave RAM bank 0, FIFO A and B
	subs r1, #0x40	@ r1 = 0x04000070 again (from 0x040000B0)
	strb r2, [r1, #0]	@ SOUND3CNT_L = 0 (r2, the fill word): bank 0 plays, 0x90 is bank 1
	adds r1, #0x20
	movs r2, #8
	bl rrr_clear	@ wave RAM bank 1, and the FIFOs again
	movs r2, #0
	movs r1, #0x80
	adds r1, r1, r4
	strb r2, [r1, #4]	@ SOUNDCNT_X = 0: master off. RegisterRamReset leaves sound off
@ the memory blocks, if their flags are set
rrr_memory:
	movs r6, #1	@ bit 0: EWRAM
	lsrs r1, r4, #1	@ 0x02000000
	lsrs r2, r4, #0xA	@ 0x10000 words, 256 KiB
	bl rrr_clear
	movs r6, #8	@ bit 3: VRAM
	movs r1, #6
	lsls r1, r1, #0x18	@ 0x06000000
	lsrs r2, r1, #0xC	@ 0x6000 words, 96 KiB
	bl rrr_clear
	movs r6, #0x10	@ bit 4: OAM
	movs r1, #7
	lsls r1, r1, #0x18	@ 0x07000000
	lsrs r2, r4, #0x12	@ 0x100 words, 1 KiB
	bl rrr_clear
	movs r6, #4	@ bit 2: palette RAM
	movs r1, #5
	lsls r1, r1, #0x18	@ 0x05000000
	lsrs r2, r4, #0x12	@ 0x100 words, 1 KiB
	bl rrr_clear
	movs r6, #2	@ bit 1: IWRAM
	movs r1, #3
	lsls r1, r1, #0x18	@ 0x03000000
	ldr r2, iwram_clear_words	@ =0x00001F80 words: 0x03000000-0x03007DFF
	bl rrr_clear
	add sp, #4
	pop {r4, r5, r6, r7}
	pop {r3}
	bx r3
@ rrr_clear: one step of RegisterRamReset. If flag r6 is set in r7, fills r2 words at
@ r1 with zero (cpufastset_from_sp). Else returns immediately.
@ In:  r1 = address, r2 = words (CpuFastSet rounds up to 8), r5 = 0x85000000, r6 = the
@      flag of the block, r7 = the flags. The word at sp of the caller = 0.
@ Out: if it filled, as CpuFastSet leaves them: r0 = sp, r1 = the end of the block,
@      r2 = r3 = 0. If not, r1 and r2 do not change. RegisterRamReset depends on which
@      case occurs.
rrr_clear:
	tst r6, r7
	bne cpufastset_from_sp	@ set: fill (a branch: CpuFastSet returns to the caller)
	bx lr
@ cpufastset_from_sp: CpuFastSet from the word at sp, with r5 ORed into r2. Tail-calls
@ thumb_CpuFastSet, which returns to the lr of the caller. In RegisterRamReset,
@ r5 = 0x85000000 has bit 24 set, so this is a fill with the zero at [sp].
@ place_cart_logo (header.s) also calls it. Its loop leaves r5 = 0, so there r2 = 0x800
@ is a copy of 0x800 words from sp to 0x03000564. place_cart_logo stores 0 at [sp],
@ which suggests a zero fill, but the call copies (read from the code, not run).
cpufastset_from_sp:
	mov r0, sp	@ the source: the zero word of the caller
	orrs r2, r5	@ + 0x85000000: bit 24, fill
	b thumb_CpuFastSet
	.balign 4
@ The shared literal pool. A Thumb ldr reaches a literal up to 1 KiB after it. An ARM
@ ldr reaches 4 KiB in both directions. This pool serves the Thumb code of header.s
@ (0x05A4-0x09C1), boot_irq (ARM, at 0x0300) and RegisterRamReset. If the pool moves,
@ or code moves away from it, a literal can go out of range. The assembler reports this.
boot_serial_irq_pointer:
	.4byte boot_serial_irq + 1	@ boot_irq: the serial IRQ handler, MultiBoot (Thumb)
sound_vsync_pointer:
	.4byte SoundDriverVSync + 1	@ boot_irq: the VBlank handler, in the sound driver (Thumb)
header_copy_addr:
	@ header.s (copy_header_piece, intro_load_graphics): the BIOS copy of the cartridge
	@ header, from header byte 0x04: 0xDC bytes, to 0x03000163
	.4byte HEADER_COPY
logo_reference_pointer:
	.4byte logo_reference	@ check_cart_header: what the header logo must match
letter_states_addr:
	@ intro_reset_letters: the intro letters, 16 bytes each: x, y, and a third word that
	@ intro_letter_affine converts to a scale (from intro.s and header.s)
	.4byte LETTER_STATES
intro_colors_pointer:
	.4byte intro_colors	@ table of intro_fade_colors; lowest address of copy_bios_data
obj_palette_addr:
	.4byte PLTT + 0x200	@ intro_fade_colors: the OBJ palette, 0x05000200
soundbias_addr:
	.4byte REG_SOUNDBIAS	@ SoundBias
work_buffer_a_addr:
	@ header.s: work buffer A, 4 KiB up to 0x03001564. header.s copies the GAME BOY art
	@ and the logo here, decodes them to buffer B (work_buffer_b_addr) and back, then
	@ unpacks them from here
	.4byte WORK_BUF_A
gameboy_art_pointer:
	.4byte gameboy_art	@ load_gameboy_art: the compressed letters
logo_tree_pointer:
	.4byte logo_tree	@ load_logo_tree: the Huffman header and tree of the logo
intro_oam_pointer:
	.4byte intro_oam	@ load_intro_oam: the sprite attributes
intro_palette_dest:
	@ load_intro_palette: BG colour 28, 0x05000038; + 0x200 for OBJ colour 28
	.4byte PLTT + 0x38
intro_palette_pointer:
	.4byte intro_palette	@ load_intro_palette: its four colours
intro_letter_unpack_pointer:
	.4byte intro_letter_unpack	@ intro_load_graphics: BitUnPack parameters for the letters
dacs_1mbit_probe_addr:
	@ intro_load_graphics: 20 bytes read into buffer A if header byte 0xB4 has bit 7 set.
	@ 0x09FE1FE0 through the wait state 1 mirror, just below the 0x09FE2000 debugger
	@ entry (see dacs_1mbit_entry). The purpose of the read: not followed
	.4byte 0x0BFE1FE0
header_b4_addr:
	@ intro_load_graphics: header byte 0xB4 (GBATEK: device type; bit 7 = the DACS size)
	.4byte ROM + 0xB4
dacs_8mbit_probe_addr:
	@ intro_load_graphics: if bit 7 is clear, 0x09FFFFE0 through the same mirror: the
	@ last 32 bytes of the cartridge space
	.4byte 0x0BFFFFE0
blank_logo_cpuset:
	@ intro_load_graphics: r2 for CpuSet if header byte 0xB2 is not 0x96. Fill (bit 24),
	@ 32-bit (bit 26), 0x27 words: sets the 156 logo bytes of the header copy to 0xFF
	@ (the fill word is this value asr 31). CpuSet ignores bit 31
	.4byte 0x85000027
work_buffer_b_addr:
	.4byte WORK_BUF_B	@ header.s: work buffer B, immediately after buffer A
letter_unpack_vram:
	@ intro_load_graphics: unpacks the letters here (VRAM + 0x40) to 8 bits per pixel,
	@ then copies them to OBJ VRAM
	.4byte VRAM + 0x40
intro_letter_tiles_pointer:
	.4byte intro_letter_tiles	@ intro_load_graphics: the OBJ tile number of each letter
obj_vram_addr:
	.4byte OBJ_VRAM	@ intro_load_graphics: the sprite tiles, 0x06010000
ball_bg3_map:
	.4byte VRAM + 0xB880	@ intro_load_graphics: destination for fill_2d (a BG map?)
ball_bg3_map_step:
	.4byte 0x00000202	@ intro_load_graphics: step for fill_2d (a number, not an address)
ball_bg3_map_first:
	.4byte 0x00007271	@ intro_load_graphics: first value for fill_2d
intro_flag_addr:
	.4byte INTRO_FLAG	@ decode_cart_logo: stores the low byte of its r0 there
logo_bits_buffer:
	@ decode_cart_logo: buffer A + 0x24, just after the copy of logo_tree. The 156 logo
	@ bytes of the header go here, so the tree and the bits decode as one Huffman stream
	.4byte LOGO_BITS
logo_diff16_header:
	@ decode_cart_logo: a Diff16 header put before the Huffman output: type 8 (bits 4-7),
	@ 16-bit units (bits 0-3 = 2), 0xD0 = 208 bytes of output (bits 8-31)
	.4byte 0x0000D082
logo_unpack_pointer:
	.4byte logo_unpack	@ unpack_cart_logo: BitUnPack parameters for the logo
logo_stage_vram:
	@ place_cart_logo: the unpacked logo (from buffer B) goes here, in two rows of 0x340
	@ bytes, 1 KiB apart
	.4byte VRAM + 0x24C0
logo_copy_src_vram:
	.4byte VRAM + 0x2040	@ place_cart_logo: copy source (three times 1 KiB)
logo_copy_dest_vram:
	.4byte OBJ_VRAM + 0x6800	@ place_cart_logo: copy destination
rrr_fill_mode:
	@ RegisterRamReset: the r5 value, ORed into each length for CpuFastSet. Bit 24 = fill.
	@ CpuFastSet ignores the other bits. In a DMA control word, the same bits would be
	@ enable, 32-bit and fixed source (compare cgb_vram_fill_dmacnt)
	.4byte 0x85000000
rrr_sio_start:
	.4byte 0x04000110	@ RegisterRamReset: the start of the SIO block (0x110-0x11F unused)
rrr_soundcnt:
	@ RegisterRamReset: SOUNDCNT_L = 0x0000 and SOUNDCNT_H = 0x880E in one store.
	@ PSG volume 100%, FIFO A and B at 100%, both FIFOs reset (bits 11, 15), no FIFO
	@ sent to a side. The low byte (0) is also stored to SOUNDCNT_X (master off)
	.4byte 0x880E0000
iwram_clear_words:
	.4byte 0x00001F80	@ RegisterRamReset: the IWRAM length in words (0x7E00 bytes)
@ SWI 0x0B
@
@ CpuSet SWI 0x0B: copy or fill, in halfwords or words. Thumb.
@ In:  r0 = source, r1 = destination (aligned to the unit),
@      r2 = bits 0-20: the count in units
@           bit 24: fill (the unit at [r0] repeated)
@           bit 26: 32-bit units, else 16 (GBATEK)
@      Bits 24 and 26 are the same bits as fixed source and 32-bit in a DMA control word.
@ Does nothing if check_range refuses: a count of 0, or a source that starts or ends
@ below 0x02000000. The end that it checks is r0 + count * 4, also in 16-bit mode.
@ Out: nothing. r0-r3 and ip changed, r4 and r5 kept. In 32-bit mode, r0 and r1 end
@      after the data read and written. In 16-bit mode, they do not change.
@ The loops use a signed compare (bge). This is correct for all addresses below
@ 0x80000000.
CpuSet:
	push {r4, r5, lr}
	lsls r4, r2, #0xB
	lsrs r4, r4, #9	@ r4 = count * 4: bytes, as if words
	bl cpuset_check_range
	beq cpuset_return	@ refused: return
	movs r5, #0
	lsrs r3, r2, #0x1B	@ C = bit 26
	bcc cpuset_16bit	@ 16-bit
	adds r5, r1, r4	@ 32-bit: r5 = the end of the destination
	lsrs r3, r2, #0x19	@ C = bit 24
	bcc cpuset_copy32	@ copy
	ldmia r0!, {r3}	@ fill: read the word once
cpuset_fill32:
	cmp r1, r5
	bge cpuset_return
	stmia r1!, {r3}
	b cpuset_fill32
@ 32-bit copy, one word per loop
cpuset_copy32:
	cmp r1, r5
	bge cpuset_return
	ldmia r0!, {r3}
	stmia r1!, {r3}
	b cpuset_copy32
@ 16-bit: r4 = the length in bytes, r5 = the offset in the source and the destination
cpuset_16bit:
	lsrs r4, r4, #1	@ count * 2
	lsrs r3, r2, #0x19	@ C = bit 24
	bcc cpuset_copy16	@ copy
	ldrh r3, [r0, #0]	@ fill: read the halfword once
cpuset_fill16:
	cmp r5, r4
	bge cpuset_return
	strh r3, [r1, r5]
	.inst.n 0x1CAD	@ adds r5, r5, #2
	b cpuset_fill16
@ 16-bit copy
cpuset_copy16:
	cmp r5, r4
	bge cpuset_return
	ldrh r3, [r0, r5]
	strh r3, [r1, r5]
	.inst.n 0x1CAD	@ adds r5, r5, #2
	b cpuset_copy16
cpuset_return:
	pop {r4, r5}
	pop {r3}
	bx r3
@ cpuset_check_range: the Thumb entry to check_range. Sets ip = r4 (the length in
@ bytes), then bx to check_range in ARM. check_range returns directly to the Thumb
@ caller, with Z set to refuse. r3 is lost. Used by CpuSet, decompress.s and multiboot.s.
cpuset_check_range:
	adr r3, check_range
	mov ip, r4
	bx r3
	.balign 4, 0
	.arm
	.balign 4
@ check_range: the read protection of the SWIs (GBATEK: CpuSet and CpuFastSet refuse a
@ source that goes into the BIOS). ARM. Returns with bx lr, to ARM or Thumb callers.
@ In:  r0 = source, ip = length in bytes (bits 25-31 ignored).
@ Out: Z set = refuse: the length is 0, or bits 25-27 are all clear in the start or in
@      the end of the source (r0 + length). That is 0x00000000-0x01FFFFFF (the BIOS and
@      the unused space after it), or the same range every 0x10000000 above.
@      Z clear = continue. ip = the end.
check_range:
	cmp ip, #0
	beq check_range_return	@ nothing to do: Z set
	bic ip, ip, #-0x2000000	@ bits 0-24 of the length
	add ip, r0, ip	@ ip = the end
	tst r0, #0xE000000	@ Z set if the start is below 0x02000000
	tstne ip, #0xE000000	@ if not: Z set if the end is below 0x02000000
	.balign 4
check_range_return:
	bx lr
	.thumb
	.balign 4
@ thumb_CpuFastSet: Thumb veneer to CpuFastSet. In Thumb, pc reads as this address + 4,
@ which is CpuFastSet (thus the .balign), and bx r3 goes there in ARM. r3 is lost.
thumb_CpuFastSet:
	mov r3, pc
	bx r3
	.arm
	.balign 4
@ SWI 0x0C
@
@ CpuFastSet SWI 0x0C: copy or fill in 32-byte blocks, eight registers at a time with
@ ldm/stm. ARM.
@ In:  r0 = source, r1 = destination (both word-aligned),
@      r2 = bits 0-20: the count in words
@           bit 24: fill (the word at [r0] repeated)
@      No other bit in r2 has an effect (bit 26 also has no effect). The count is
@      rounded up to a multiple of 8 (GBATEK).
@ Does nothing if check_range refuses (a count of 0, or a source in the BIOS).
@ Out: nothing. r1 = the end of the written data. r0 = after the data read (a copy), or
@      unchanged (a fill). r2 and r3 = the first two words of the last block (for a
@      fill, the fill word). r4-r10 kept. RegisterRamReset uses these values of r1 and r2.
@ The loops use a signed compare (lt). This is correct for all addresses below
@ 0x80000000.
CpuFastSet:
	push {r4, r5, r6, r7, r8, r9, sl, lr}
	lsl sl, r2, #0xB	@ count in the top bits: bits 21-31 of r2 are removed
	lsrs ip, sl, #9	@ ip = count * 4, bytes
	bl check_range
	beq cpufastset_return	@ refused
	add sl, r1, sl, lsr #9	@ sl = the end of the destination
	lsrs r2, r2, #0x19	@ C = bit 24
	bcc cpufastset_copy	@ copy
	ldr r2, [r0]	@ fill: put the word in all eight registers
	mov r3, r2
	mov r4, r2
	mov r5, r2
	mov r6, r2
	mov r7, r2
	mov r8, r2
	mov r9, r2
	.balign 4
@ fill, 32 bytes per loop. The last block can go past sl (the count is rounded up)
cpufastset_fill:
	cmp r1, sl
	stmialt r1!, {r2, r3, r4, r5, r6, r7, r8, r9}
	blt cpufastset_fill
	b cpufastset_return
	.balign 4
@ copy, 32 bytes per loop
cpufastset_copy:
	cmp r1, sl
	ldmlt r0!, {r2, r3, r4, r5, r6, r7, r8, r9}
	stmialt r1!, {r2, r3, r4, r5, r6, r7, r8, r9}
	blt cpufastset_copy
	.balign 4
cpufastset_return:
	pop {r4, r5, r6, r7, r8, r9, sl, lr}
	bx lr
