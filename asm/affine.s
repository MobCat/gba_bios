@ affine.s 0x0C2C-0x0F5B: BgAffineSet (SWI 0x0E), ObjAffineSet (SWI 0x0F) and the
@ sine table they share. All ARM.
@ Each SWI converts a scale (sx, sy) and an angle a into the 2x2 matrix that the
@ display hardware uses, in 8.8 fixed point:
@     pa =  sx cos a     pb = -sx sin a
@     pc =  sy sin a     pd =  sy cos a
@ BgAffineSet also calculates BGxX/BGxY: the start point that puts a given point of
@ the background at a given point of the screen.
@ pa-pd are background steps per screen pixel, so a scale of 0x200 (2.0) shows the
@ background at half size.
@ Only the top 8 bits of the angle are used: 256 steps per turn (GBATEK).
@ sin a = sine_table[a], cos a = sine_table[(a + 0x40) AND 0xFF]. The products
@ (8.8 x 1.14) get an arithmetic shift right of 14 bits.
@ They use no RAM or I/O: they read the source array and write the destination.

	.arm
	.balign 4
@ SWI 0x0E
@
@ BgAffineSet SWI 0x0E: calculates BG rotation and scaling parameters for r2 backgrounds.
@ In:  r0 = source entries, 20 bytes each (GBATEK lists 18; the last 2 are padding):
@        +0x00 s32 bx, +0x04 s32 by  the background point, 8 fractional bits
@        +0x08 s16 dx, +0x0A s16 dy  the screen point where (bx, by) appears, in pixels
@        +0x0C s16 sx, +0x0E s16 sy  scale, 8.8
@        +0x10 u16 angle             0x10000 = one turn
@      r1 = destination entries, 16 bytes each, laid out like BG2PA-BG2Y:
@        +0 pa, +2 pb, +4 pc, +6 pd  s16, 8.8
@        +8 s32 x0, +0xC s32 y0      the start point: x0 = bx - pa dx - pb dy,
@                                    y0 = by - pc dx - pd dy
@      r2 = number of entries (0 or less: does nothing).
BgAffineSet:
	push {r4, r5, r6, r7, r8, r9, sl, fp}
	.balign 4
bgaffine_loop:
	subs r2, r2, #1	@ one entry per loop
	blt bgaffine_return
	ldrh r3, [r0, #0x10]	@ angle
	lsr r3, r3, #8	@ top 8 bits: 0-255
	adr ip, sine_table
	add r8, r3, #0x40
	and r8, r8, #0xFF
	lsl r8, r8, #1
	ldrsh fp, [r8, ip]	@ fp = cos a (the sine at a + 90 degrees)
	lsl r8, r3, #1
	ldrsh ip, [r8, ip]	@ ip = sin a
	ldrsh r9, [r0, #0xC]	@ sx
	ldrsh sl, [r0, #0xE]	@ sy
	mul r8, fp, r9
	asr r3, r8, #0xE	@ r3 = sx cos a = pa
	mul r8, ip, r9
	asr r4, r8, #0xE	@ r4 = sx sin a = -pb
	mul r8, ip, sl
	asr r5, r8, #0xE	@ r5 = sy sin a = pc
	mul r8, fp, sl
	asr r6, r8, #0xE	@ r6 = sy cos a = pd
	ldm r0, {r9, sl, ip}	@ r9 = bx, sl = by, ip = dx | dy << 16
	lsl fp, ip, #0x10
	asr fp, fp, #0x10	@ fp = dx
	asr ip, ip, #0x10	@ ip = dy
	rsb r8, fp, #0
	mla r9, r3, r8, r9	@ bx - pa dx
	mla r8, r4, ip, r9	@ ... - pb dy (r4 is -pb)
	str r8, [r1, #8]	@ x0
	rsb r8, fp, #0
	mla sl, r5, r8, sl	@ by - pc dx
	rsb r8, ip, #0
	mla r8, r6, r8, sl	@ ... - pd dy
	str r8, [r1, #0xC]	@ y0
	strh r3, [r1]	@ pa
	rsb r4, r4, #0
	strh r4, [r1, #2]	@ pb
	strh r5, [r1, #4]	@ pc
	strh r6, [r1, #6]	@ pd
	add r0, r0, #0x14	@ next source entry (+20 bytes)
	add r1, r1, #0x10	@ next destination entry (+16 bytes)
	b bgaffine_loop
	.balign 4
	
bgaffine_return:
	pop {r4, r5, r6, r7, r8, r9, sl, fp}
	bx lr
	.balign 4
@ SWI 0x0F
@
@ ObjAffineSet SWI 0x0F: calculates sprite rotation and scaling parameters for r2 sprites.
@ In:  r0 = source entries, 8 bytes each (GBATEK lists 6; the last 2 are padding):
@        +0 s16 sx, +2 s16 sy (8.8), +4 u16 angle (only bits 8-15 used)
@      r1 = destination of pa. pb, pc and pd follow, each r3 bytes after the one before.
@      r3 = the step: 2 for four consecutive halfwords, 8 for OAM. In OAM, the four
@           halfwords of a parameter group are in attribute 3 of four sprites (GBATEK).
@           r1 moves 4 x r3 per entry, so with 8 the next entry is the next OAM group.
@      r2 = number of entries (0 or less: does nothing).
ObjAffineSet:
	push {r8, r9, sl, fp}
	.balign 4
objaffine_loop:
	subs r2, r2, #1	@ one entry per loop
	blt objaffine_return
	ldrh r9, [r0, #4]	@ angle
	lsr r9, r9, #8	@ top 8 bits: 0-255
	adr ip, sine_table
	add r8, r9, #0x40
	and r8, r8, #0xFF
	lsl r8, r8, #1
	ldrsh fp, [r8, ip]	@ fp = cos a
	lsl r8, r9, #1
	ldrsh ip, [r8, ip]	@ ip = sin a
	ldrsh r9, [r0]	@ sx
	ldrsh sl, [r0, #2]	@ sy
	mul r8, fp, r9
	asr r8, r8, #0xE
	strh r8, [r1], r3	@ pa = sx cos a
	mul r8, ip, r9
	asr r8, r8, #0xE
	rsb r8, r8, #0
	strh r8, [r1], r3	@ pb = -sx sin a
	mul r8, ip, sl
	asr r8, r8, #0xE
	strh r8, [r1], r3	@ pc = sy sin a
	mul r8, fp, sl
	asr r8, r8, #0xE
	strh r8, [r1], r3	@ pd = sy cos a
	add r0, r0, #8	@ next source entry (+8 bytes)
	b objaffine_loop
	.balign 4
	
objaffine_return:
	pop {r8, r9, sl, fp}
	bx lr
	.balign 4
@ 256 entries, 1.14 fixed point
@
@ sine_table: sin(i x 2 pi / 256) for i = 0x00-0xFF, signed 1.14 fixed point
@ (0x4000 = 1.0). One full turn, not folded. Eight entries per row; the comment on
@ each row gives its indices. i is the top byte of a 16-bit angle. cos a is the
@ entry 0x40 after a.
@ i = 0x40 is 90 degrees (0x4000), 0x80 is 180 (0), 0xC0 is 270 (0xC000, -1.0).
sine_table:
	.2byte 0x0000, 0x0192, 0x0323, 0x04B5, 0x0645, 0x07D5, 0x0964, 0x0AF1	@ 0x00-0x07
	.2byte 0x0C7C, 0x0E05, 0x0F8C, 0x1111, 0x1294, 0x1413, 0x158F, 0x1708	@ 0x08-0x0F
	.2byte 0x187D, 0x19EF, 0x1B5D, 0x1CC6, 0x1E2B, 0x1F8B, 0x20E7, 0x223D	@ 0x10-0x17
	.2byte 0x238E, 0x24DA, 0x261F, 0x275F, 0x2899, 0x29CD, 0x2AFA, 0x2C21	@ 0x18-0x1F
	.2byte 0x2D41, 0x2E5A, 0x2F6B, 0x3076, 0x3179, 0x3274, 0x3367, 0x3453	@ 0x20-0x27
	.2byte 0x3536, 0x3612, 0x36E5, 0x37AF, 0x3871, 0x392A, 0x39DA, 0x3A82	@ 0x28-0x2F
	.2byte 0x3B20, 0x3BB6, 0x3C42, 0x3CC5, 0x3D3E, 0x3DAE, 0x3E14, 0x3E71	@ 0x30-0x37
	.2byte 0x3EC5, 0x3F0E, 0x3F4E, 0x3F84, 0x3FB1, 0x3FD3, 0x3FEC, 0x3FFB	@ 0x38-0x3F
	.2byte 0x4000, 0x3FFB, 0x3FEC, 0x3FD3, 0x3FB1, 0x3F84, 0x3F4E, 0x3F0E	@ 0x40-0x47
	.2byte 0x3EC5, 0x3E71, 0x3E14, 0x3DAE, 0x3D3E, 0x3CC5, 0x3C42, 0x3BB6	@ 0x48-0x4F
	.2byte 0x3B20, 0x3A82, 0x39DA, 0x392A, 0x3871, 0x37AF, 0x36E5, 0x3612	@ 0x50-0x57
	.2byte 0x3536, 0x3453, 0x3367, 0x3274, 0x3179, 0x3076, 0x2F6B, 0x2E5A	@ 0x58-0x5F
	.2byte 0x2D41, 0x2C21, 0x2AFA, 0x29CD, 0x2899, 0x275F, 0x261F, 0x24DA	@ 0x60-0x67
	.2byte 0x238E, 0x223D, 0x20E7, 0x1F8B, 0x1E2B, 0x1CC6, 0x1B5D, 0x19EF	@ 0x68-0x6F
	.2byte 0x187D, 0x1708, 0x158F, 0x1413, 0x1294, 0x1111, 0x0F8C, 0x0E05	@ 0x70-0x77
	.2byte 0x0C7C, 0x0AF1, 0x0964, 0x07D5, 0x0645, 0x04B5, 0x0323, 0x0192	@ 0x78-0x7F
	.2byte 0x0000, 0xFE6E, 0xFCDD, 0xFB4B, 0xF9BB, 0xF82B, 0xF69C, 0xF50F	@ 0x80-0x87
	.2byte 0xF384, 0xF1FB, 0xF074, 0xEEEF, 0xED6C, 0xEBED, 0xEA71, 0xE8F8	@ 0x88-0x8F
	.2byte 0xE783, 0xE611, 0xE4A3, 0xE33A, 0xE1D5, 0xE075, 0xDF19, 0xDDC3	@ 0x90-0x97
	.2byte 0xDC72, 0xDB26, 0xD9E1, 0xD8A1, 0xD767, 0xD633, 0xD506, 0xD3DF	@ 0x98-0x9F
	.2byte 0xD2BF, 0xD1A6, 0xD095, 0xCF8A, 0xCE87, 0xCD8C, 0xCC99, 0xCBAD	@ 0xA0-0xA7
	.2byte 0xCACA, 0xC9EE, 0xC91B, 0xC851, 0xC78F, 0xC6D6, 0xC626, 0xC57E	@ 0xA8-0xAF
	.2byte 0xC4E0, 0xC44A, 0xC3BE, 0xC33B, 0xC2C2, 0xC252, 0xC1EC, 0xC18F	@ 0xB0-0xB7
	.2byte 0xC13B, 0xC0F2, 0xC0B2, 0xC07C, 0xC04F, 0xC02D, 0xC014, 0xC005	@ 0xB8-0xBF
	.2byte 0xC000, 0xC005, 0xC014, 0xC02D, 0xC04F, 0xC07C, 0xC0B2, 0xC0F2	@ 0xC0-0xC7
	.2byte 0xC13B, 0xC18F, 0xC1EC, 0xC252, 0xC2C2, 0xC33B, 0xC3BE, 0xC44A	@ 0xC8-0xCF
	.2byte 0xC4E0, 0xC57E, 0xC626, 0xC6D6, 0xC78F, 0xC851, 0xC91B, 0xC9EE	@ 0xD0-0xD7
	.2byte 0xCACA, 0xCBAD, 0xCC99, 0xCD8C, 0xCE87, 0xCF8A, 0xD095, 0xD1A6	@ 0xD8-0xDF
	.2byte 0xD2BF, 0xD3DF, 0xD506, 0xD633, 0xD767, 0xD8A1, 0xD9E1, 0xDB26	@ 0xE0-0xE7
	.2byte 0xDC72, 0xDDC3, 0xDF19, 0xE075, 0xE1D5, 0xE33A, 0xE4A3, 0xE611	@ 0xE8-0xEF
	.2byte 0xE783, 0xE8F8, 0xEA71, 0xEBED, 0xED6C, 0xEEEF, 0xF074, 0xF1FB	@ 0xF0-0xF7
	.2byte 0xF384, 0xF50F, 0xF69C, 0xF82B, 0xF9BB, 0xFB4B, 0xFCDD, 0xFE6E	@ 0xF8-0xFF
