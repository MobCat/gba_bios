@ decompress.s 0x0F5C-0x13C3: the decompression SWIs 0x10-0x18, in address order:
@
@   SWI  label                  mode   format               writes
@   0x10 BitUnPack              ARM    unit widening        32 bits at a time
@   0x13 HuffUnComp             ARM    Huffman              32 bits at a time
@   0x11 LZ77UnCompWram         ARM    LZ77                  8 bits at a time
@   0x12 LZ77UnCompVram         ARM    LZ77                 16 bits at a time
@   0x14 RLUnCompWram           Thumb  run-length            8 bits at a time
@   0x15 RLUnCompVram           Thumb  run-length           16 bits at a time
@   0x16 Diff8bitUnFilterWram   Thumb  8-bit differences     8 bits at a time
@   0x17 Diff8bitUnFilterVram   Thumb  8-bit differences    16 bits at a time
@   0x18 Diff16bitUnFilter      Thumb  16-bit differences   16 bits at a time
@
@ The "Wram" versions write bytes, so they need memory that accepts 8-bit writes (GBATEK:
@ "eg. not VRAM"). The "Vram" versions pair bytes into a halfword in a register and store
@ it with strh.
@ None of them returns a value (GBATEK). r0, r1 and r3 are not preserved: r0 and r1 keep
@ the values they had when the loops stopped. swi_handler (vectors.s) restores r2 and ip,
@ but a direct caller also loses r2 and ip.
@
@ HOW THEY SHARE CODE
@ Very little: each SWI has its own loop. They share only these:
@ - check_range (memory.s). Each SWI calls it before it reads the data itself. (LZ77, RL
@   and Diff have already read their header; HuffUnComp has read nothing.)
@   The ARM SWIs call it directly, with the length in ip. The Thumb SWIs call it through
@   cpuset_check_range, with the length in r4 (this clobbers r3 and ip).
@   check_range returns Z set when the length is 0, or when r0 or
@   r0 + (length & 0x01FFFFFF) has bits 25-27 clear (below 0x02000000: the BIOS). The SWI
@   then returns at once and writes nothing. Only bits 25-27 are tested, so
@   0x10000000-0x11FFFFFF and similar ranges are also refused.
@   This is the "software-based protection which rejects source addresses in the BIOS
@   area" that GBATEK mentions. Only the source is checked, never the destination.
@   The notes of each SWI give the r0 and length that it passes.
@ - The swi_table entries (vectors.s): ARM SWIs as the label, Thumb SWIs as label + 1.
@ - Three Thumb veneers for the Thumb code of the BIOS: thumb_BitUnPack, thumb_HuffUnComp
@   and thumb_LZ77UnCompWram. header.s calls them directly, not by SWI.
@   Each is `mov r3, pc; bx r3`. pc reads as the veneer + 4, which is the ARM function.
@   It is word aligned because of the .balign 4 before the veneer. The veneers clobber r3.
@   header.s also calls Diff16bitUnFilter directly; it is already Thumb.
@ - Diff16bitUnFilter returns through call_via_r2 (`bx r2`). sound.s also calls
@   call_via_r2, as a call-through-r2 helper. call_via_r1 is the same, through r1.
@ There are no read callbacks: those are in the NDS BIOS ("ReadByCallback" in GBATEK).
@ The GBA versions read the source directly ("ReadNormal"). There are no literal pools.
@
@ THE DATA FORMATS (GBATEK, "BIOS Decompression Functions"; checked against the code)
@ All SWIs except BitUnPack start with a 32-bit header at r0. The header is read as a
@ word, so r0 must be word aligned:
@     bits 0-3   Huffman: bits per data unit, 4 or 8. Diff: unit size, 1 or 2. Else 0.
@     bits 4-7   type: 1 LZ77, 2 Huffman, 3 run-length, 8 diff. No SWI checks it.
@     bits 8-31  the size of the output, in bytes.
@ LZ77      a flag byte, then 8 blocks, one per flag bit, bit 7 first. Flag 0: a literal
@           byte. Flag 1: two bytes NP pp. Copy N+3 bytes (3-18) from Ppp+1 bytes
@           (1-4096) back in the output.
@ Huffman   a byte n, the tree size: the tree is (n+1)*2 bytes, including n. Thus the
@           first node (the root) is at r0 + 5, and the bitstream at r0 + 4 + (n+1)*2.
@           The bitstream is 32-bit words, bit 31 first: 0 selects child 0, 1 child 1.
@           A node byte: bits 0-5 are an offset. Child 0 is at (node & ~1) + offset*2 + 2,
@           and child 1 is the byte after it. Bit 7 set: child 0 is a data byte, not a
@           node. Bit 6: the same for child 1. After a data byte, decoding starts again
@           at the root.
@ RL        a flag byte, then data. Bit 7 clear: (bits 0-6) + 1 bytes follow, copied
@           unchanged. Bit 7 set: one byte follows, written (bits 0-6) + 3 times.
@ Diff8/16  the first unit unchanged, then the difference of each unit from the one before.
@ BitUnPack has no header: r2 points to an 8-byte UnPackInfo (see BitUnPack).
@
@ WHAT THEY DO ALIKE (code)
@ - The size is checked between blocks, not inside a block. The SWI writes all of the last
@   LZ77 block or RL packet, even past the size (up to 17 bytes for LZ77, 129 for RL).
@ - The Vram versions never store an odd final byte: it stays in the register.
@ - BitUnPack and HuffUnComp write whole words only.

	.thumb
	.balign 4
@ Thumb veneer for BitUnPack: switches to ARM at the next word. Clobbers r3.
thumb_BitUnPack:
	mov r3, pc
	bx r3
	.arm
	.balign 4
@ BitUnPack SWI 0x10: widens each source unit to a larger unit, and adds an offset.
@ Example: a 1bpp font to 4bpp tiles. The BIOS uses it for the intro letters (2bpp to
@ 8bpp) and the cartridge logo (1bpp to 8bpp), both from header.s.
@ In:  r0 source, any alignment (read one byte at a time).
@      r1 destination, word aligned. Written with 32-bit str only, so VRAM is fine.
@      r2 -> UnPackInfo, 8 bytes. Not range-checked: the BIOS itself uses logo_unpack,
@            which is in the BIOS (data.s).
@              +0 hword  source length in bytes
@              +2 byte   source unit width in bits (GBATEK: 1, 2, 4, 8)
@              +3 byte   destination unit width in bits (GBATEK: 1, 2, 4, 8, 16, 32)
@              +4 word   bits 0-30: an offset added to every non-zero unit;
@                        bit 31: add it to zero units too
@ Out: nothing. The SWI splits each source byte, lowest unit first. It ORs each unit, plus
@      the offset, into an output word from bit 0 up, and stores the word when it is full.
@      It drops a final partial word, so the output must be a multiple of 4 bytes.
@ Refuses (check_range, with r0 and the source length): a length of 0, a source in the BIOS.
@ GBATEK matches all of this, but does not mention the range check. Code: the widths are
@      not checked (other values are not followed here). A unit plus offset wider than
@      the destination width is not masked: it overflows into the next unit up.
@ Stack: 8 bytes; [sp+4] is the offset, [sp+0] is not used.
BitUnPack:
	push {r4, r5, r6, r7, r8, r9, sl, fp, lr}
	sub sp, sp, #8
	ldrh r7, [r2]	@ r7 = the source length: bytes left
	movs ip, r7	@ the length for check_range
	bl check_range
	beq bitunpack_return	@ refused: return
	ldrb r6, [r2, #2]	@ r6 = source unit width
	rsb sl, r6, #8	@ sl = 8 - width, for the unit mask below
	mov lr, #0	@ lr = the output word being filled
	ldr fp, [r2, #4]
	lsr r8, fp, #0x1F	@ r8 = bit 31: the zero data flag
	ldr fp, [r2, #4]
	lsl fp, fp, #1
	lsr fp, fp, #1	@ fp = the offset (bits 0-30)...
	str fp, [sp, #4]	@ ...kept on the stack
	ldrb r2, [r2, #3]	@ r2 = destination unit width (r2 no longer points to UnPackInfo)
	mov r3, #0	@ r3 = bit position in the output word
	.balign 4
bitunpack_next_byte:	@ each source byte
	subs r7, r7, #1
	blt bitunpack_return	@ none left: done (a partial word in lr is dropped)
	mov fp, #0xFF
	asr r5, fp, sl	@ r5 = mask of the lowest unit: 0xFF >> (8 - width)
	ldrb r9, [r0], #1	@ r9 = the byte
	mov r4, #0	@ r4 = bit position in r9
	.balign 4
bitunpack_next_unit:	@ each unit in the byte, lowest first
	cmp r4, #8
	bge bitunpack_next_byte	@ no units left in the byte
	and fp, r9, r5
	lsrs ip, fp, r4	@ ip = the unit; Z if it is 0
	cmpeq r8, #0	@ a 0 unit keeps Z only if the zero data flag is clear...
	beq bitunpack_put_unit	@ ...and then gets no offset
	ldr fp, [sp, #4]
	add ip, ip, fp	@ add the offset
	.balign 4
bitunpack_put_unit:
	orr lr, lr, ip, lsl r3	@ OR into the output word at bit r3, not masked
	add r3, r3, r2
	cmp r3, #0x20
	blt bitunpack_unit_done	@ word not full yet
	str lr, [r1], #4	@ full: store the 32-bit word
	mov lr, #0
	mov r3, #0
	.balign 4
bitunpack_unit_done:
	lsl r5, r5, r6	@ mask and position move up to the next unit
	add r4, r4, r6
	b bitunpack_next_unit
	.balign 4
bitunpack_return:	@ return, also when refused
	add sp, sp, #8
	pop {r4, r5, r6, r7, r8, r9, sl, fp, lr}
	bx lr
	.thumb
	.balign 4
@ Thumb veneer for HuffUnComp: switches to ARM at the next word. Clobbers r3.
thumb_HuffUnComp:
	mov r3, pc
	bx r3
	.arm
	.balign 4
@ HuffUnComp SWI 0x13: decodes Huffman-coded data of 4- or 8-bit units.
@ The BIOS uses it for gameboy_art, and for the cartridge logo with logo_tree in front
@ (header.s).
@ In:  r0 source, word aligned: header, tree size byte n, tree, bitstream (top of file).
@         The bitstream is read with ldr at r0 + 4 + (n+1)*2: word aligned only if n is odd.
@      r1 destination, word aligned. Written with 32-bit str only, so VRAM is fine.
@ Out: nothing. The SWI collects units into a word, first unit in the low bits, and stores
@      each full word. The size decreases by 4 per word, so it is rounded up to 4.
@ Refuses (check_range): a source start in the BIOS. The length passed is 0x2000000.
@      It is not 0, so it passes the zero test. Then it is masked to 0, so only r0 is
@      checked.
@ GBATEK matches: the header, the tree, the bit order, 32-bit writes. Code:
@      - The type is not checked.
@      - A data size other than 4 or 8 is not refused. But a word is stored after
@        (size & 7) + 4 units, which is 32 bits only for 4 and 8. Other sizes give
@        wrong output.
@      - The bits of a data byte above the data size are shifted out of the top of the
@        word, so they have no effect (GBATEK: they "should be zero").
@ Stack: 8 bytes; [sp+4] is the units per word, [sp+0] is not used.
HuffUnComp:
	push {r4, r5, r6, r7, r8, r9, sl, fp, lr}
	sub sp, sp, #8
	movs ip, #0x2000000	@ the length for check_range: not 0, but masked to 0 there
	bl check_range
	beq huff_return	@ refused: return
	add r2, r0, #4	@ r2 -> the tree size byte
	add r7, r2, #1	@ r7 -> the root node
	ldrb sl, [r0]
	and r4, sl, #0xF	@ r4 = bits per data unit (header bits 0-3)
	mov r3, #0	@ r3 = the output word; each unit goes in at the top
	mov lr, #0	@ lr = number of units in r3
	and sl, r4, #7
	add fp, sl, #4	@ units per word: (4 & 7) + 4 = 8, (8 & 7) + 4 = 4
	str fp, [sp, #4]
	ldr sl, [r0]
	lsr ip, sl, #8	@ ip = bytes left to write (header bits 8-31)
	ldrb sl, [r2]
	add sl, sl, #1
	add r0, r2, sl, lsl #1	@ r0 -> the bitstream: the size byte + (n+1)*2
	mov r2, r7	@ r2 = the current node: the root
	.balign 4
huff_next_word:	@ each word of the bitstream
	cmp ip, #0
	ble huff_return	@ all written: done
	mov r8, #0x20	@ 32 bits per word
	ldr r5, [r0], #4	@ r5 = the word; bit 31 is the next bit
	.balign 4
huff_next_bit:	@ each bit: one step down the tree
	subs r8, r8, #1
	blt huff_next_word	@ no bits left in the word
	mov sl, #1
	and r9, sl, r5, lsr #0x1F	@ r9 = the bit: which child
	ldrb r6, [r2]
	lsl r6, r6, r9	@ bit 7 of r6 = the data flag of that child (node bit 7, or bit 6)
	lsr sl, r2, #1
	lsl sl, sl, #1	@ sl = node address & ~1
	ldrb fp, [r2]
	and fp, fp, #0x3F	@ the node offset, bits 0-5
	add fp, fp, #1
	add sl, sl, fp, lsl #1
	add r2, sl, r9	@ r2 -> the child: (node & ~1) + offset*2 + 2 + bit
	tst r6, #0x80
	beq huff_bit_done	@ a node: continue down from it
	lsr r3, r3, r4	@ data: make room at the top of the output word...
	ldrb sl, [r2]
	rsb fp, r4, #0x20
	orr r3, r3, sl, lsl fp	@ ...and put it there (bits above the unit size are lost)
	mov r2, r7	@ start again at the root
	add lr, lr, #1
	ldr fp, [sp, #4]
	cmp lr, fp	@ a full word of units?
	streq r3, [r1], #4	@ store it: the first unit has reached the low bits
	subeq ip, ip, #4
	moveq lr, #0	@ r3 is not cleared: its old units are shifted out by the next ones
	.balign 4
huff_bit_done:
	cmp ip, #0
	lslgt r5, r5, #1	@ next bit to bit 31
	bgt huff_next_bit
	b huff_next_word	@ all written: huff_next_word returns
	.balign 4
huff_return:	@ return, also when refused
	add sp, sp, #8
	pop {r4, r5, r6, r7, r8, r9, sl, fp, lr}
	bx lr
	.thumb
	.balign 4
@ Thumb veneer for LZ77UnCompWram: switches to ARM at the next word. Clobbers r3.
thumb_LZ77UnCompWram:
	mov r3, pc
	bx r3
	.arm
	.balign 4
@ LZ77UnCompWram SWI 0x11: decodes LZ77, and writes one byte at a time.
@ The BIOS uses it for gameboy_art, after HuffUnComp (header.s).
@ In:  r0 source, word aligned: header, then flag bytes and blocks (top of file).
@      r1 destination: memory that accepts 8-bit writes (GBATEK: not VRAM). Any alignment.
@ Out: nothing. A back-reference copies from the output already written, one byte at a
@      time. Thus an overlapping back-reference repeats bytes, and disp 0 (1 back) repeats
@      one byte.
@ Refuses (check_range): the SWI reads the header first. Then it checks r0 = source + 4
@      and the size from the header (the output size, not the compressed size).
@ GBATEK matches. Code: the type is not checked, and a back-reference is not cut at the
@      size. The last one is copied whole, up to 17 bytes past the size.
LZ77UnCompWram:
	push {r4, r5, r6, lr}
	ldr r5, [r0], #4	@ the header, read before the range check
	lsr r2, r5, #8	@ r2 = bytes left to write
	movs ip, r2	@ the length for check_range: the output size
	bl check_range
	beq lz77_wram_return	@ refused: return
	.balign 4
lz77_wram_next_flags:	@ each flag byte
	cmp r2, #0
	ble lz77_wram_return	@ all written: done
	ldrb lr, [r0], #1	@ lr = flags for the next 8 blocks, the first in bit 7
	mov r4, #8
	.balign 4
lz77_wram_next_block:	@ each block
	subs r4, r4, #1
	blt lz77_wram_next_flags	@ 8 done: next flag byte
	tst lr, #0x80
	bne lz77_wram_backref
	ldrb r6, [r0], #1	@ flag 0: a literal byte
	strb r6, [r1], #1
	sub r2, r2, #1
	b lz77_wram_block_done
	.balign 4
lz77_wram_backref:	@ flag 1: a back-reference, bytes NP pp
	ldrb r5, [r0]
	mov r6, #3
	add r3, r6, r5, asr #4	@ r3 = N + 3, bytes to copy
	ldrb r6, [r0], #1
	and r5, r6, #0xF
	lsl ip, r5, #8
	ldrb r6, [r0], #1
	orr r5, r6, ip	@ r5 = Ppp, 12 bits
	add ip, r5, #1	@ ip = distance back: Ppp + 1
	sub r2, r2, r3	@ subtracted all at once: can go below 0
	.balign 4
lz77_wram_copy:	@ each byte copied
	ldrb r5, [r1, -ip]
	strb r5, [r1], #1
	subs r3, r3, #1
	bgt lz77_wram_copy
	.balign 4
lz77_wram_block_done:	@ after each block
	cmp r2, #0
	lslgt lr, lr, #1	@ next flag to bit 7
	bgt lz77_wram_next_block
	b lz77_wram_next_flags	@ all written: lz77_wram_next_flags returns
	.balign 4
lz77_wram_return:	@ return, also when refused
	pop {r4, r5, r6, lr}
	bx lr
	.balign 4
@ LZ77UnCompVram SWI 0x12: LZ77 as SWI 0x11, but writes 16 bits at a time, for VRAM.
@ No Thumb veneer: nothing in the BIOS calls it. Only swi_table reaches it.
@ In:  r0 source, word aligned, as SWI 0x11.
@      r1 destination, halfword aligned. Written with strh only.
@ Out: nothing. The SWI pairs bytes (literal or copied) into a halfword in r3 (r2 gives
@      the next half). It stores the halfword when its high byte is in. It never stores an
@      odd final byte. A back-reference reads its byte from the destination with ldrh.
@ Refuses: as SWI 0x11.
@ GBATEK matches, and warns that disp 0 (1 byte back) does not work here. The code shows
@      why. At an odd output position, the byte 1 back is the low half of the halfword in
@      r3, which is not stored yet. So ldrh reads the old contents of the destination.
@      A disp 0 block is 3 bytes or more, so it always reaches an odd position.
@      (A Python model of this loop, made for these notes, agrees: with disp 1-4095 it
@      matches SWI 0x11, and gameboy_art, which has disp 0 blocks, comes out wrong.)
@ Code, not in GBATEK: the type is not checked; the last block is not cut at the size.
LZ77UnCompVram:
	push {r4, r5, r6, r7, r8, r9, sl, lr}
	mov r3, #0	@ r3 = the halfword being built
	ldr r8, [r0], #4	@ the header, read before the range check
	lsr sl, r8, #8	@ sl = bytes left to write
	mov r2, #0	@ r2 = where the next byte goes in r3: 0 low half, 8 high
	movs ip, sl	@ the length for check_range: the output size
	bl check_range
	beq lz77_vram_return	@ refused: return
	.balign 4
lz77_vram_next_flags:	@ each flag byte
	cmp sl, #0
	ble lz77_vram_return	@ all written: done
	ldrb r6, [r0], #1	@ r6 = flags for the next 8 blocks, the first in bit 7
	mov r7, #8
	.balign 4
lz77_vram_next_block:	@ each block
	subs r7, r7, #1
	blt lz77_vram_next_flags	@ 8 done: next flag byte
	tst r6, #0x80
	bne lz77_vram_backref
	ldrb r9, [r0], #1	@ flag 0: a literal byte...
	orr r3, r3, r9, lsl r2	@ ...into its half of r3
	sub sl, sl, #1
	eors r2, r2, #8	@ other half next; back to 0 means both halves are in...
	strheq r3, [r1], #2	@ ...so store the halfword
	moveq r3, #0
	b lz77_vram_block_done
	.balign 4
lz77_vram_backref:	@ flag 1: a back-reference, bytes NP pp
	ldrb r9, [r0]
	mov r8, #3
	add r5, r8, r9, asr #4	@ r5 = N + 3, bytes to copy
	ldrb r9, [r0], #1
	and r8, r9, #0xF
	lsl r4, r8, #8
	ldrb r9, [r0], #1
	orr r8, r9, r4	@ r8 = Ppp, 12 bits
	add r4, r8, #1	@ r4 = distance back: Ppp + 1
	rsb r8, r2, #8	@ 8 - r2, which is r2 ^ 8
	and r9, r4, #1	@ an odd distance puts the source byte in the other half
	eor lr, r8, r9, lsl #3	@ lr = (the half of the source byte) ^ 8; the loop flips it first
	sub sl, sl, r5	@ subtracted all at once: can go below 0
	.balign 4
lz77_vram_copy:	@ each byte copied
	eor lr, lr, #8	@ lr = the shift of the source byte in its halfword: 0 low, 8 high
	rsb r8, r2, #8
	add r8, r4, r8, lsr #3	@ the distance, + 1 when the output is at a low half...
	lsr r8, r8, #1
	lsl r8, r8, #1	@ ...rounded down to even: the distance back from r1 to its halfword
	ldrh r9, [r1, -r8]	@ r8 = 0 (1 back, at a high half) reads [r1], not stored yet
	mov r8, #0xFF
	and r8, r9, r8, lsl lr
	asr r8, r8, lr	@ r8 = the source byte
	orr r3, r3, r8, lsl r2	@ into its half of r3, as a literal
	eors r2, r2, #8
	strheq r3, [r1], #2	@ both halves in: store
	moveq r3, #0
	subs r5, r5, #1
	bgt lz77_vram_copy
	.balign 4
lz77_vram_block_done:	@ after each block
	cmp sl, #0
	lslgt r6, r6, #1	@ next flag to bit 7
	bgt lz77_vram_next_block
	b lz77_vram_next_flags	@ all written: lz77_vram_next_flags returns
	.balign 4
lz77_vram_return:	@ return, also when refused; a pending odd byte in r3 is dropped
	pop {r4, r5, r6, r7, r8, r9, sl, lr}
	bx lr
@ RLUnCompWram SWI 0x14: decodes run-length data, and writes one byte at a time.
@ Thumb. Only swi_table reaches it (entry + 1).
@ In:  r0 source, word aligned: header, then packets (top of file).
@      r1 destination: memory that accepts 8-bit writes (GBATEK: not VRAM). Any alignment.
@ Out: nothing.
@ Refuses (cpuset_check_range): source + 4 and the size from the header, as LZ77.
@ GBATEK matches. Code: the type is not checked. The last packet is written whole, even
@      past the size (up to 129 bytes past it).
RLUnCompWram:
	.thumb
	push {r4, r5, r6, r7, lr}
	ldmia r0!, {r3}	@ the header
	lsrs r7, r3, #8	@ r7 = bytes left to write
	adds r4, r7, #0	@ r4 = the length for cpuset_check_range: the output size
	bl cpuset_check_range
	beq rl_wram_return	@ refused: return
rl_wram_next_packet:	@ each packet
	cmp r7, #0
	ble rl_wram_return	@ all written: done
	ldrb r4, [r0, #0]	@ the flag byte
	.inst.n 0x1C40	@ adds r0, r0, #1
	lsls r2, r4, #0x19
	lsrs r2, r2, #0x19	@ r2 = bits 0-6: the length
	lsrs r3, r4, #8	@ for the carry only: C = bit 7
	bcs rl_wram_run	@ bit 7 set: a run
	.inst.n 0x1C52	@ adds r2, r2, #1 (bit 7 clear: copy N + 1 bytes)
	subs r7, r7, r2
rl_wram_copy:	@ each byte copied
	ldrb r3, [r0, #0]
	strb r3, [r1, #0]
	.inst.n 0x1C40	@ adds r0, r0, #1
	.inst.n 0x1C49	@ adds r1, r1, #1
	.inst.n 0x1E52	@ subs r2, r2, #1
	bgt rl_wram_copy
	b rl_wram_next_packet
rl_wram_run:	@ a run: one byte, N + 3 times
	.inst.n 0x1CD2	@ adds r2, r2, #3
	subs r7, r7, r2
	ldrb r5, [r0, #0]	@ r5 = the byte
	.inst.n 0x1C40	@ adds r0, r0, #1
rl_wram_fill:	@ each byte written
	strb r5, [r1, #0]
	.inst.n 0x1C49	@ adds r1, r1, #1
	.inst.n 0x1E52	@ subs r2, r2, #1
	bgt rl_wram_fill
	b rl_wram_next_packet
rl_wram_return:	@ return, also when refused
	pop {r4, r5, r6, r7}
	pop {r3}
	bx r3
@ RLUnCompVram SWI 0x15: run-length as SWI 0x14, but writes 16 bits at a time, for VRAM.
@ Thumb. Only swi_table reaches it (entry + 1).
@ In:  r0 source, word aligned, as SWI 0x14.
@      r1 destination, halfword aligned. Written with strh only.
@ Out: nothing. The SWI pairs bytes into a halfword in r7 (r4 gives the next half). It
@      stores the halfword when its high byte is in. It never stores an odd final byte.
@ Refuses: as SWI 0x14.
@ GBATEK matches. Code, as SWI 0x14: the type is not checked; the last packet is not cut.
@ Stack: 12 bytes; [sp+4] the flag byte, [sp+8] the byte of a run, [sp+0] not used.
@      (SWI 0x14 keeps these in registers.)
RLUnCompVram:
	push {r4, r5, r6, r7, lr}
	sub sp, #0xC
	movs r7, #0	@ r7 = the halfword being built
	ldmia r0!, {r3}	@ the header
	lsrs r5, r3, #8	@ r5 = bytes left to write
	adds r4, r5, #0	@ r4 = the length for cpuset_check_range: the output size
	bl cpuset_check_range
	beq rl_vram_return	@ refused: return
	movs r4, #0	@ r4 = where the next byte goes in r7: 0 low half, 8 high
rl_vram_next_packet:	@ each packet
	cmp r5, #0
	ble rl_vram_return	@ all written: done
	ldrb r3, [r0, #0]
	str r3, [sp, #4]	@ the flag byte, kept on the stack
	.inst.n 0x1C40	@ adds r0, r0, #1
	ldr r3, [sp, #4]
	lsls r2, r3, #0x19
	lsrs r2, r2, #0x19	@ r2 = bits 0-6: the length
	ldr r6, [sp, #4]
	lsrs r3, r6, #8	@ for the carry only: C = bit 7
	bcs rl_vram_run	@ bit 7 set: a run
	.inst.n 0x1C52	@ adds r2, r2, #1 (bit 7 clear: copy N + 1 bytes)
	subs r5, r5, r2
rl_vram_copy:	@ each byte copied
	ldrb r6, [r0, #0]
	lsls r6, r4
	orrs r7, r6	@ into its half of r7
	.inst.n 0x1C40	@ adds r0, r0, #1
	movs r3, #8
	eors r4, r3	@ other half next; back to 0 means both halves are in...
	bne rl_vram_copy_next
	strh r7, [r1, #0]	@ ...so store the halfword
	.inst.n 0x1C89	@ adds r1, r1, #2
	movs r7, #0
rl_vram_copy_next:
	.inst.n 0x1E52	@ subs r2, r2, #1
	bgt rl_vram_copy
	b rl_vram_next_packet
rl_vram_run:	@ a run: one byte, N + 3 times
	.inst.n 0x1CD2	@ adds r2, r2, #3
	subs r5, r5, r2
	ldrb r6, [r0, #0]
	str r6, [sp, #8]	@ the byte, kept on the stack
	.inst.n 0x1C40	@ adds r0, r0, #1
rl_vram_fill:	@ each byte written
	ldr r6, [sp, #8]
	lsls r6, r4
	orrs r7, r6	@ into its half of r7
	movs r3, #8
	eors r4, r3
	bne rl_vram_fill_next
	strh r7, [r1, #0]	@ both halves in: store
	.inst.n 0x1C89	@ adds r1, r1, #2
	movs r7, #0
rl_vram_fill_next:
	.inst.n 0x1E52	@ subs r2, r2, #1
	bgt rl_vram_fill
	b rl_vram_next_packet
rl_vram_return:	@ return, also when refused; a pending odd byte in r7 is dropped
	add sp, #0xC
	pop {r4, r5, r6, r7}
	pop {r3}
	bx r3
@ Diff8bitUnFilterWram SWI 0x16: reverses an 8-bit difference filter, one byte per write.
@ Thumb. Only swi_table reaches it (entry + 1).
@ In:  r0 source, word aligned: header, the first byte, then the difference of each byte
@         from the byte before.
@      r1 destination: memory that accepts 8-bit writes (GBATEK: not VRAM). Any alignment.
@ Out: nothing. It writes exactly the header size in bytes: out[0] = in[0],
@      out[i] = out[i-1] + in[i], mod 256.
@ Refuses (cpuset_check_range): source + 4 and the size from the header.
@ GBATEK matches. Code: header bits 0-3 (GBATEK: must be 1) and the type (8) are not
@      checked.
Diff8bitUnFilterWram:
	push {r4, lr}
	ldmia r0!, {r4}	@ the header
	lsrs r4, r4, #8	@ r4 = bytes left to write, and the length for cpuset_check_range
	bl cpuset_check_range
	beq diff8_wram_return	@ refused: return
	ldrb r2, [r0, #0]	@ r2 = the running value: the first byte, unchanged
	.inst.n 0x1C40	@ adds r0, r0, #1
	strb r2, [r1, #0]
	.inst.n 0x1C49	@ adds r1, r1, #1
diff8_wram_loop:	@ each byte after the first
	.inst.n 0x1E64	@ subs r4, r4, #1
	ble diff8_wram_return	@ all written: done
	ldrb r3, [r0, #0]
	adds r2, r3, r2	@ add the difference (only the low 8 bits are stored)
	.inst.n 0x1C40	@ adds r0, r0, #1
	strb r2, [r1, #0]
	.inst.n 0x1C49	@ adds r1, r1, #1
	b diff8_wram_loop
diff8_wram_return:	@ return, also when refused
	pop {r4}
	pop {r3}
	bx r3
@ Diff8bitUnFilterVram SWI 0x17: as SWI 0x16, but writes 16 bits at a time, for VRAM.
@ Thumb. Only swi_table reaches it (entry + 1).
@ In:  r0 source, word aligned, as SWI 0x16.
@      r1 destination, halfword aligned. Written with strh only.
@ Out: nothing. The SWI pairs bytes into a halfword in r2 (r4 gives the next half). It
@      stores the halfword when its high byte is in. It never stores an odd final byte, so
@      a size of 1 writes nothing.
@ Refuses: as SWI 0x16.
@ GBATEK matches. Code: header bits 0-3 (GBATEK: must be 1) and the type (8) are not
@      checked.
Diff8bitUnFilterVram:
	push {r4, r5, r6, r7, lr}
	ldmia r0!, {r3}	@ the header
	lsrs r5, r3, #8	@ r5 = bytes left to write
	adds r4, r5, #0	@ r4 = the length for cpuset_check_range: the output size
	bl cpuset_check_range
	beq diff8_vram_return	@ refused: return
	movs r4, #8	@ r4 = where the next byte goes in r2: 8, the high half...
	ldrb r7, [r0, #0]	@ r7 = the running value: the first byte, unchanged
	.inst.n 0x1C40	@ adds r0, r0, #1
	adds r2, r7, #0	@ ...because the first byte is already in the low half
diff8_vram_loop:	@ each byte after the first
	.inst.n 0x1E6D	@ subs r5, r5, #1
	ble diff8_vram_return	@ all written: done
	ldrb r3, [r0, #0]
	adds r7, r3, r7	@ add the difference
	.inst.n 0x1C40	@ adds r0, r0, #1
	lsls r6, r7, #0x18
	lsrs r6, r6, #0x18	@ its low 8 bits...
	lsls r6, r4
	orrs r2, r6	@ ...into their half of r2
	movs r3, #8
	eors r4, r3	@ other half next; back to 0 means both halves are in
	bne diff8_vram_loop
	strh r2, [r1, #0]	@ so store the halfword
	.inst.n 0x1C89	@ adds r1, r1, #2
	movs r2, #0
	b diff8_vram_loop
diff8_vram_return:	@ return, also when refused; a pending odd byte in r2 is dropped
	pop {r4, r5, r6, r7}
	pop {r3}
	bx r3
@ Diff16bitUnFilter SWI 0x18: reverses a 16-bit difference filter, 16 bits at a time.
@ There is only one version: halfword writes suit both WRAM and VRAM. Thumb.
@ swi_table reaches it (entry + 1), and decode_cart_logo (header.s) calls it directly.
@ decode_cart_logo writes the header itself (0x0000D082, 208 bytes) over the start of
@ the HuffUnComp output.
@ In:  r0 source, word aligned: header, the first halfword, then the difference of each
@         halfword from the halfword before.
@      r1 destination, halfword aligned.
@ Out: nothing. out[0] = in[0], out[i] = out[i-1] + in[i], mod 0x10000. The size is in
@      bytes and decreases by 2 per halfword, so an odd size writes one byte more.
@ Refuses (cpuset_check_range): source + 4 and the size from the header.
@ GBATEK matches. Code: header bits 0-3 (GBATEK: must be 2) and the type (8) are not
@      checked.
@ It returns through call_via_r2 (pop {r2}, then bx r2), which sound.s also calls. Keep
@ the two together, or give one of them its own bx.
Diff16bitUnFilter:
	push {r4, lr}
	ldmia r0!, {r4}	@ the header
	lsrs r4, r4, #8	@ r4 = bytes left to write, and the length for cpuset_check_range
	bl cpuset_check_range
	beq diff16_return	@ refused: return
	ldrh r2, [r0, #0]	@ r2 = the running value: the first halfword, unchanged
	.inst.n 0x1C80	@ adds r0, r0, #2
	strh r2, [r1, #0]
	.inst.n 0x1C89	@ adds r1, r1, #2
diff16_loop:	@ each halfword after the first
	.inst.n 0x1EA4	@ subs r4, r4, #2
	ble diff16_return	@ all written: done
	ldrh r3, [r0, #0]
	adds r2, r3, r2	@ add the difference (only the low 16 bits are stored)
	.inst.n 0x1C80	@ adds r0, r0, #2
	strh r2, [r1, #0]
	.inst.n 0x1C89	@ adds r1, r1, #2
	b diff16_loop
diff16_return:	@ return, also when refused: pop the return address to r2, then call_via_r2
	pop {r4}
	pop {r2}
@ call_via_r2: bx r2. Calls the function whose address is in r2. A Thumb `bl call_via_r2`
@ has set lr, so that function returns directly to the caller. This is the
@ call-through-register helper (_call_via_r2) that ARM compilers use in Thumb code,
@ because Thumb on the ARM7TDMI has no blx.
@ sound.s calls it at trkvolpit_call_ext. It is also the return of Diff16bitUnFilter,
@ which falls through into it from above.
call_via_r2:
	bx r2
@ call_via_r1: bx r1. The same as call_via_r2, through r1.
@ sound.s calls it at clear_cgb_loop.
call_via_r1:
	bx r1
