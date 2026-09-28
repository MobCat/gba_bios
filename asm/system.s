@ system.s 0x0284-0x05A3: five groups that only share an address range.
@   start_cgb_cartridge  the path of boot_intro when a Game Boy cartridge is in the
@                        slot: a centred white screen, border fade-out, VRAM fill, then
@                        enter_cgb_mode (vectors.s). Thumb. Does not return.
@   boot_irq             the IRQ handler while the BIOS runs its intro: serial goes to
@                        MultiBoot, VBlank to the sound driver. ARM.
@   IntrWait, VBlankIntrWait, intr_take_flags  SWI 0x04 and 0x05: halt until the
@                        game IRQ handler has flagged a wanted IRQ. ARM.
@   GetBiosChecksum      SWI 0x0D. ARM.
@   the arithmetic SWIs  Div and DivArm (0x06, 0x07), Sqrt (0x08) and ArcTan (0x09)
@                        in ARM. ArcTan2 (0x0A) in Thumb, which calls Div and ArcTan
@                        through the Thumb veneers thumb_Div and thumb_ArcTan. abs is
@                        a helper for boot_intro.
@ RAM: INTR_CHECK (0x03007FF8), through its mirror at 0x03FFFFF8. boot_irq writes it.
@   IntrWait reads it and clears bits in it. start_cgb_cartridge writes three words at
@   the bottom of the stack frame of its caller. Sqrt pushes one word.
@ I/O: IE, IF, IME and HALTCNT (boot_irq, IntrWait). start_cgb_cartridge also writes
@   SOUNDCNT_H, SOUNDBIAS, BG2CNT, BG2X, BG2Y, DISPCNT, palette RAM, VRAM and DMA3.
@ Thumb code (ArcTan2, the intro, the sound driver) calls Div and ArcTan through a
@ veneer: thumb_Div and thumb_ArcTan in this file, thumb_DivArm in data.s.

@ a Game Boy cartridge: fade, then enter_cgb_mode
@
@ start_cgb_cartridge: called by boot_intro when WAITCNT bit 15 reads 1 (GBATEK: the
@ cartridge-type switch, pressed by an 8-bit cartridge). Before this call, boot_intro
@ did RegisterRamReset(0xFF), POSTFLG = 1, SoundBias(1), IE = VBlank and the DISPSTAT
@ VBlank IRQ. IME is 0, so each halt below ends at a VBlank and no IRQ is taken.
@ Does, in mode 4 (8-bit bitmap):
@   - draws a 160x144 white rectangle (the Game Boy screen size), moved by BG2X/BG2Y
@     to the middle of the 240x160 screen
@   - fades the backdrop (palette 0, the border) from light grey to black in 10 frames
@   - fills all of VRAM with 0xFF by DMA3, then goes to enter_cgb_mode
@ Sound: PSG volume 100%, and SOUNDBIAS resolution 6-bit / 262 kHz (GBATEK: the best
@ for the PSG channels, which are the Game Boy channels). Whether the CGB side uses
@ any of this is not followed.
@ Stack: no frame of its own. [sp] and [sp, #4] are the two stack arguments of fill_2d,
@ and [sp, #8] is the source word of the DMA. All three are in the frame of boot_intro.
@ This is harmless, because nothing returns to boot_intro.
start_cgb_cartridge:
	.thumb
	movs r4, #4
	lsls r4, r4, #0x18	@ r4 = 0x04000000, I/O
	movs r5, #5
	lsls r5, r5, #0x18	@ r5 = 0x05000000, palette RAM
	movs r6, #6
	lsls r6, r6, #0x18	@ r6 = 0x06000000, VRAM
	movs r1, #0	@ step for fill_2d: 0, the same value everywhere
	movs r0, #0xC2
	adds r2, r4, #0
	adds r2, #0x80	@ r2 = 0x04000080, SOUNDCNT_L
	strb r0, [r2, #2]	@ SOUNDCNT_H low byte = 0xC2: PSG volume 100% (bits 6-7 unused)
	strb r0, [r2, #9]	@ SOUNDBIAS high byte = 0xC2: resolution 3, bias bits 8-9 = 2
	movs r0, #0xFF
	.inst.n 0x1C80	@ adds r0, r0, #2 (r0 = 0x0101: two pixels of colour 1)
	movs r2, #0xA0	@ 160 bytes per row: 160 pixels at 8 bits
	movs r3, #0x90	@ 144 rows
	str r6, [sp, #0]	@ destination for fill_2d: VRAM, frame 0 of mode 4
	movs r7, #0xF0
	str r7, [sp, #4]	@ row stride for fill_2d: 240 bytes, one mode 4 line
	bl fill_2d	@ (header.s) the 160x144 rectangle, at the top left of the frame
	movs r0, #0x83
	lsls r0, r0, #7	@ 0x4180
	strh r0, [r4, #0xC]	@ BG2CNT = 0x4180: bits 7, 8, 14 (in mode 4: not followed)
	ldr r0, cgb_bg2x	@ =0xFFFFD800
	str r0, [r4, #0x28]	@ BG2X = -40.0: the frame moves 40 pixels right, (240 - 160) / 2
	asrs r0, r0, #0x10	@ r0 = -1
	lsls r0, r0, #0xB	@ -1 << 11 = 0xFFFFF800, -8.0
	str r0, [r4, #0x2C]	@ BG2Y = -8.0: 8 pixels down, (160 - 144) / 2
	ldr r3, cgb_border_colors	@ =0x7FFF7BDE
	str r3, [r5, #0]	@ palette 0 (backdrop) = 0x7BDE light grey, 1 = 0x7FFF white
	ldrh r3, [r5, #0]	@ r3 = 0x7BDE, the colour to fade
	ldr r7, cgb_fade_step	@ =0x00000C63, one fade step
@ one frame per loop: acknowledge VBlank, halt until the next VBlank, turn the display
@ on, and subtract 3 from the red, green and blue of the backdrop
cgb_fade_loop:
	lsrs r2, r4, #0x11
	adds r2, r2, r4	@ r2 = 0x04000200, IE
	strh r7, [r2, #2]	@ IF = 0x0C63: bit 0 acknowledges VBlank (other bits: harmless)
	bl thumb_Halt	@ until the next VBlank (IE = VBlank only)
	movs r0, #4
	strb r0, [r4, #1]	@ DISPCNT high byte = 0x04: BG2 on
	strb r0, [r4, #0]	@ DISPCNT low byte = 0x04: mode 4, forced blank off
	subs r3, r3, r7	@ one step darker. 0x7BDE is exactly 10 steps of 0x0C63
	strh r3, [r5, #0]	@ palette 0
	bgt cgb_fade_loop	@ until black (0)
	mvns r0, r1	@ r0 = 0xFFFFFFFF
	str r0, [sp, #8]	@ the source word for the DMA
	adds r4, #0xD4	@ r4 = 0x040000D4, DMA3SAD
	add r1, sp, #8
	str r1, [r4, #0]	@ DMA3SAD = the address of that word
	str r6, [r4, #4]	@ DMA3DAD = VRAM
	ldr r1, cgb_vram_fill_dmacnt	@ =0x85006000
	str r1, [r4, #8]	@ DMA3CNT: starts now, fills all 96 KiB of VRAM with 0xFF
	bl thumb_enter_cgb_mode	@ (data.s) does not return: data follows
	.balign 4
cgb_vram_fill_dmacnt:
	@ DMA3CNT: 0x6000 words (low half). 0x8500 = enable (bit 15), 32-bit (bit 10), fixed
	@ source (bits 7-8 = 2), start immediately. 96 KiB (all of VRAM) from one word
	.4byte 0x85006000
cgb_bg2x:
	@ BG2X: -0x2800, -40.0 in 8 fractional bits. Centres a 160-wide picture in 240
	.4byte 0xFFFFD800
cgb_border_colors:
	@ palette 0 and 1 in one word: 0x7BDE for the border (red, green and blue 30 of 31:
	@ light grey), 0x7FFF (white) for the rectangle
	.4byte 0x7FFF7BDE
cgb_fade_step:
	@ one fade step: 3 in each 5-bit colour: red (bits 0-4), green (5-9), blue (10-14).
	@ Also written to IF each frame, for its bit 0 (VBlank)
	.4byte 0x00000C63
	.arm
	.balign 4
@ the IRQ handler during the intro (serial for MultiBoot, VBlank for sound)
@
@ boot_irq: INTR_VECTOR while the BIOS runs its intro (HardReset sets it).
@ Called by irq_handler: ARM, IRQ mode, lr = irq_return.
@ If serial (IF bit 7) is pending: acknowledges it and tail-calls boot_serial_irq
@ (multiboot.s). Else: sets INTR_CHECK = IE AND IF (a plain store, not an OR), so that
@ VBlankIntrWait sees the VBlank. Acknowledges VBlank if it is pending, and tail-calls
@ SoundDriverVSync. Both paths return to irq_return with bx lr.
@ Serial has priority. A VBlank pending at the same time stays in IF, so the IRQ occurs
@ again immediately for it (inferred). Only serial and VBlank are expected in IE. Any
@ other IRQ would call SoundDriverVSync and acknowledge nothing (read from the code).
boot_irq:
	mov r3, #0x4000000
	ldr r2, [r3, #0x200]	@ IE in the low half, IF in the high half
	and r2, r2, r2, lsr #0x10	@ r2 = IE AND IF
	ands r1, r2, #0x80	@ serial?
	ldrne r0, boot_serial_irq_pointer	@ =boot_serial_irq + 1
	andeq r1, r2, #1	@ no: r1 = the VBlank bit
	ldreq r0, sound_vsync_pointer	@ =SoundDriverVSync + 1
	strheq r2, [r3, #-8]	@ INTR_CHECK (0x03FFFFF8) = IE AND IF
	strb r1, [r3, #0x202]	@ IF: acknowledge serial (0x80), VBlank (1), or nothing (0)
	bx r0	@ Thumb; it returns to irq_return
	.balign 4
@ SWI 0x05
@
@ VBlankIntrWait SWI 0x05: IntrWait with r0 = 1 and r1 = 1. It discards old flags and
@ waits for a new VBlank (GBATEK). boot_intro calls it directly, through
@ thumb_VBlankIntrWait (data.s). Falls into IntrWait.
VBlankIntrWait:
	mov r0, #1	@ discard old flags
	mov r1, #1	@ VBlank
	.balign 4
@ SWI 0x04
@
@ IntrWait SWI 0x04: halts until the game IRQ handler flags one of the wanted IRQs
@ in INTR_CHECK, then removes those flags from INTR_CHECK.
@ In:  r0 = 0: return when a wanted flag is set, also an old one. Other values: first
@          clear the wanted flags, so that only a new IRQ counts.
@      r1 = the IRQs to wait for, as IE/IF bits.
@ Out: r0 = the wanted flags that were set, now cleared in INTR_CHECK; r3 = 0;
@      r2 and ip changed (through the SWI, both are restored); IME = 1 (GBATEK: it
@      forces it).
@ The game IRQ handler must OR the IRQs that it acknowledges into INTR_CHECK
@ (GBATEK). This code does not do it. IRQs must also be unmasked in CPSR and IE. If
@ not, IntrWait never returns.
@ The loop halts before its first check. This is the GBATEK bug where it always waits
@ for one IRQ. But with r0 = 0, ip does not yet hold 0x04000000. Through a SWI, ip
@ holds the jump target of swi_handler, 0x0330 (IntrWait). Thus the first HALTCNT
@ write goes to 0x0631 in the BIOS and does nothing. That looks like the second bug
@ that, as GBATEK says, makes the first one harmless (inferred). When it is called
@ directly with r0 = 0, the value in ip decides.
IntrWait:
	push {r4, lr}
	mov r3, #0	@ r3 = 0: for IME off, and for the HALTCNT halt
	mov r4, #1	@ r4 = 1: IME on
	cmp r0, #0
	blne intr_take_flags	@ r0 != 0: discard flags already set (sets ip = 0x04000000)
	.balign 4
intr_wait_loop:
	strb r3, [ip, #0x301]	@ HALTCNT = 0: halt until an IRQ (the first time: see above)
	bl intr_take_flags
	beq intr_wait_loop	@ no flag of r1 yet: halt again
	pop {r4, lr}
	bx lr
	.balign 4
@ intr_take_flags: the check of IntrWait. With IME off, removes the wanted flags from
@ INTR_CHECK, then sets IME on.
@ In:  r1 = the wanted flags, r3 = 0, r4 = 1.
@ Out: r0 = r1 AND INTR_CHECK, Z set if that is 0; those bits cleared in INTR_CHECK;
@      r2 = the new INTR_CHECK; ip = 0x04000000; IME = 1.
intr_take_flags:
	mov ip, #0x4000000
	strb r3, [ip, #0x208]	@ IME = 0: the IRQ handler must not change INTR_CHECK now
	ldrh r2, [ip, #-8]	@ INTR_CHECK, through the mirror at 0x03FFFFF8
	ands r0, r1, r2	@ the wanted IRQs that occurred
	eorne r2, r2, r0	@ clear them
	strhne r2, [ip, #-8]
	strb r4, [ip, #0x208]	@ IME = 1
	bx lr
	.balign 4
@ SWI 0x0D: the sum of every word in the BIOS
@
@ GetBiosChecksum SWI 0x0D (undocumented): adds the 4096 words at 0x0000-0x3FFC. This
@ works because the loop runs in the BIOS, which can read itself.
@ Out: r0 = the sum: 0xBAAE187F for this BIOS (GBATEK; build.py prints it for a
@      build). r1 = 1, r2 = the last word, r3 = 0x4000.
@ Leaves CPSR = 0xDF: System mode, IRQ and FIQ masked (GBATEK: they are off while it
@ runs). Through the SWI, the CPSR of the caller is restored. A direct call would not
@ restore it.
GetBiosChecksum:
	mov r0, #0	@ the sum
	mov r3, #0	@ the address
	.balign 4
checksum_loop:
	mov ip, #0xDF	@ System mode, IRQ and FIQ masked
	ldm r3!, {r2}
	msr CPSR_fc, ip	@ on every word. Why this is inside the loop is not clear
	add r0, r0, r2
	lsrs r1, r3, #0xE	@ 0 until r3 reaches 0x4000, the end of the BIOS
	beq checksum_loop
	bx lr
@ abs: r0 = |r0| (0x80000000 does not change). Thumb. Used by boot_intro.
abs:
	.thumb
	cmp r0, #0
	bgt abs_return
	negs r0, r0
abs_return:
	bx lr
@ thumb_Div: Thumb veneer to Div (ARM). r3 is lost. Used by ArcTan2 and
@ intro_letter_affine (header.s).
thumb_Div:
	adr r3, Div
	bx r3
	.arm
	.balign 4
@ SWI 0x07
@
@ DivArm SWI 0x07: Div with the arguments swapped: r0 = denominator, r1 = numerator
@ (GBATEK: to match the ARM library; 3 cycles slower than Div). Swaps them through r3
@ and falls into Div. boot_intro and sound.s call it directly, through thumb_DivArm
@ (data.s).
DivArm:
	mov r3, r0
	mov r0, r1
	mov r1, r3
	.balign 4
@ SWI 0x06
@
@ Div SWI 0x06: signed 32-bit division, by shift and subtract.
@ In:  r0 = numerator, r1 = denominator.
@ Out: r0 = quotient, rounded towards 0; r1 = remainder, with the sign of the
@      numerator; r3 = |quotient|. The GBATEK example: -1234, 10 gives -123, -4, 123.
@      r2 and ip changed.
@ Division by 0 never ends, except for a numerator of -1, 0 or 1: the divisor (0) can
@ never be doubled past half of the numerator (GBATEK: usually an endless loop).
@ Sqrt has its own copy of the two loops.
Div:
	ands r3, r1, #-0x80000000	@ r3 = sign bit of the denominator
	rsbmi r1, r1, #0	@ r1 = |denominator|
	@ ip bit 31 = quotient sign, bits 0-30 = numerator sign. C = numerator sign
	eors ip, r3, r0, asr #0x20
	rsbcs r0, r0, #0	@ r0 = |numerator|
	movs r2, r1	@ r2 = the divisor, to be shifted
	.balign 4
@ double the divisor until it is more than half the numerator
div_scale_up:
	cmp r2, r0, lsr #1
	lslls r2, r2, #1
	bcc div_scale_up
	.balign 4
@ then shift back down to the divisor: one quotient bit per step, shifted into r3.
@ The sign bit of r3 is shifted out on the first step
div_loop:
	cmp r0, r2
	adc r3, r3, r3	@ quotient = quotient * 2 + (r0 >= r2)
	subcs r0, r0, r2
	teq r2, r1	@ r2 is the divisor again: done
	lsrne r2, r2, #1
	bne div_loop
	mov r1, r0	@ the remainder
	mov r0, r3	@ the quotient, unsigned
	lsls ip, ip, #1	@ C = sign of the quotient, N = sign of the numerator
	rsbcs r0, r0, #0
	rsbmi r1, r1, #0
	bx lr
	.balign 4
@ SWI 0x08
@
@ Sqrt SWI 0x08: integer square root, rounded down, by the Newton method.
@ In:  r0 = an unsigned 32-bit number, n.
@ Out: r0 = floor(sqrt(n)), at most 16 bits (GBATEK: for k bits of fraction, shift n
@      left by 2k first). r1-r3 and ip changed. Uses one word of stack for r4.
@ The first guess is a power of 2 that is not smaller than the answer. Then
@ x = (x + n / x) / 2 until x stops decreasing. The last x that decreased is the
@ answer. The division is the loop of Div again, unsigned.
Sqrt:
	stmfd sp!, {r4}
	mov ip, r0	@ ip = n
	mov r1, #1
	.balign 4
@ first guess: halve r0 and double r1 until they meet
sqrt_first_guess:
	cmp r0, r1
	lsrhi r0, r0, #1
	lslhi r1, r1, #1
	bhi sqrt_first_guess
	.balign 4
@ one Newton step: r3 = n / r1, as in Div
sqrt_newton_step:
	mov r0, ip
	mov r4, r1	@ r4 = this guess
	mov r3, #0
	mov r2, r1
	.balign 4
sqrt_div_scale_up:
	cmp r2, r0, lsr #1
	lslls r2, r2, #1
	bcc sqrt_div_scale_up
	.balign 4
sqrt_div_loop:
	cmp r0, r2
	adc r3, r3, r3
	subcs r0, r0, r2
	teq r2, r1
	lsrne r2, r2, #1
	bne sqrt_div_loop
	add r1, r1, r3
	lsrs r1, r1, #1	@ the next guess, (x + n / x) / 2
	cmp r1, r4
	bcc sqrt_newton_step	@ still decreasing: do another step
	mov r0, r4	@ the last guess (the next guess was not smaller)
	ldmfd sp!, {r4}
	bx lr
@ thumb_ArcTan: Thumb veneer to ArcTan (ARM). r3 is lost. Used by ArcTan2.
thumb_ArcTan:
	.thumb
	adr r3, ArcTan
	bx r3
	.arm
	.balign 4
@ SWI 0x09
@
@ ArcTan SWI 0x09: arctangent, by a polynomial.
@ In:  r0 = tan a, signed 1.14 fixed point (0x4000 = 1.0).
@ Out: r0 = a, with 0x10000 = one full turn: -0x4000 to 0x4000 for -pi/2 to pi/2,
@      sign-extended (GBATEK gives the range as 0xC000-0x4000). r1 and r3 changed.
@ Accurate only for |tan| <= 1, that is -pi/4 to pi/4 (GBATEK notes the loss of
@ accuracy outside this range). ArcTan2 only uses this range.
@ The polynomial is odd, of degree 15: x * (c1 - c3 x^2 + c5 x^4 - ... - c15 x^14).
@ The code calculates it from the inside out, with r1 = -x^2.
@ c1 = 0xA2F9 is 4 x 0x10000 / (2 pi): the final >> 16 removes the 1.14 and the 4.
@ c3 = 0x3651 is c1 x 0.333 and c5 = 0x2081 is c1 x 0.199 (1/3 and 1/5 of the arctan
@ series). But the later constants are smaller than 1/7, 1/9 ...: they look fitted,
@ not the series truncated (inferred).
@ The code adds each constant in two parts, because an ARM immediate is 8 bits, rotated.
ArcTan:
	mul r1, r0, r0
	asr r1, r1, #0xE
	rsb r1, r1, #0	@ r1 = -x^2, 1.14
	mov r3, #0xA9	@ c15
	mul r3, r1, r3
	asr r3, r3, #0xE
	add r3, r3, #0x390	@ c13 = 0x390
	mul r3, r1, r3
	asr r3, r3, #0xE
	add r3, r3, #0x900
	add r3, r3, #0x1C	@ c11 = 0x91C
	mul r3, r1, r3
	asr r3, r3, #0xE
	add r3, r3, #0xF00
	add r3, r3, #0xB6	@ c9 = 0xFB6
	mul r3, r1, r3
	asr r3, r3, #0xE
	add r3, r3, #0x1600
	add r3, r3, #0xAA	@ c7 = 0x16AA
	mul r3, r1, r3
	asr r3, r3, #0xE
	add r3, r3, #0x2000
	add r3, r3, #0x81	@ c5 = 0x2081
	mul r3, r1, r3
	asr r3, r3, #0xE
	add r3, r3, #0x3600
	add r3, r3, #0x51	@ c3 = 0x3651
	mul r3, r1, r3
	asr r3, r3, #0xE
	add r3, r3, #0xA200
	add r3, r3, #0xF9	@ c1 = 0xA2F9
	mul r0, r3, r0	@ multiply by x
	asr r0, r0, #0x10	@ the angle, 0x4000 = pi/2
	bx lr
@ SWI 0x0A
@
@ ArcTan2 SWI 0x0A: the angle of the point (x, y), with 0x10000 = one full turn. Thumb.
@ In:  r0 = x, r1 = y (GBATEK: signed 1.14. Only the ratio is important, but x << 14
@      and y << 14 must fit in 32 bits).
@ Out: r0 = 0x0000-0xFFFF for 0 <= a < 2 pi (GBATEK). r1-r3 changed.
@ On an axis, it gives the result directly: 0, 0x4000, 0x8000 or 0xC000. (0, 0) gives 0.
@ Else it divides the smaller of |x| and |y| by the larger (Div, with the numerator
@ << 14 for 1.14), so that ArcTan only gets |tan| <= 1. Then, by octant, it adds the
@ result to, or subtracts it from, 0, 0x4000, 0x8000, 0xC000 or 0x10000.
@ Read from the code, not run: r0 is not cut to 16 bits. Thus y just below 0 with
@ x > 0, where y / x rounds to 0, gives 0x10000, not 0.
ArcTan2:
	.thumb
	push {r4, r5, r6, r7, lr}
	cmp r1, #0
	bne arctan2_y_nonzero
	cmp r0, #0	@ y = 0: on the x axis
	blt arctan2_180
	movs r0, #0	@ x >= 0: 0
	b arctan2_return
arctan2_180:
	movs r0, #0x80
	lsls r0, r0, #8	@ x < 0: 0x8000, pi
	b arctan2_return
arctan2_y_nonzero:
	cmp r0, #0	@ x = 0: on the y axis
	bne arctan2_general
	cmp r1, #0
	blt arctan2_270
	movs r0, #0x40
	lsls r0, r0, #8	@ y > 0: 0x4000, pi/2
	b arctan2_return
arctan2_270:
	movs r0, #0xC0
	lsls r0, r0, #8	@ y < 0: 0xC000, 3 pi/2
	b arctan2_return
@ neither is 0
arctan2_general:
	adds r2, r0, #0
	lsls r2, r2, #0xE	@ r2 = x << 14
	adds r3, r1, #0
	lsls r3, r3, #0xE	@ r3 = y << 14
	negs r4, r0	@ r4 = -x
	negs r5, r1	@ r5 = -y
	movs r6, #0x40
	lsls r6, r6, #8	@ r6 = 0x4000, pi/2
	lsls r7, r6, #1	@ r7 = 0x8000, pi
	cmp r1, #0
	blt arctan2_y_negative	@ y < 0
	cmp r0, #0	@ y > 0
	blt arctan2_quadrant2	@ y > 0, x < 0
	cmp r0, r1	@ y > 0, x > 0
	blt arctan2_from_90	@ x < y
	adds r1, r0, #0	@ x >= y: atan(y / x), 0 to pi/4
	adds r0, r3, #0
	bl thumb_Div
	bl thumb_ArcTan
	b arctan2_return
@ |y| > |x|, y > 0: 0x4000 - atan(x / y), pi/4 to 3 pi/4
arctan2_from_90:
	adds r0, r2, #0	@ x << 14 over y (r1 is still y)
	bl thumb_Div
	bl thumb_ArcTan
	subs r0, r6, r0
	b arctan2_return
@ y > 0, x < 0
arctan2_quadrant2:
	cmp r4, r1
	blt arctan2_from_90	@ -x < y: the same as above
@ |x| >= |y|, x < 0: 0x8000 + atan(y / x), 3 pi/4 to 5 pi/4
arctan2_from_180:
	adds r1, r0, #0
	adds r0, r3, #0	@ y << 14 over x
	bl thumb_Div
	bl thumb_ArcTan
	adds r0, r7, r0
	b arctan2_return
@ y < 0
arctan2_y_negative:
	cmp r0, #0
	bgt arctan2_quadrant4	@ x > 0
	cmp r4, r5	@ x < 0: -x > -y?
	bgt arctan2_from_180	@ yes: 0x8000 + atan(y / x)
@ |y| >= |x|, y < 0: 0xC000 - atan(x / y), 5 pi/4 to 7 pi/4
arctan2_from_270:
	adds r0, r2, #0	@ x << 14 over y (r1 is still y)
	bl thumb_Div
	bl thumb_ArcTan
	adds r6, r6, r7	@ 0xC000
	subs r0, r6, r0
	b arctan2_return
@ y < 0, x > 0
arctan2_quadrant4:
	cmp r0, r5
	blt arctan2_from_270	@ x < -y: 0xC000 - atan(x / y)
	adds r1, r0, #0	@ else 0x10000 + atan(y / x), 7 pi/4 to 2 pi
	adds r0, r3, #0
	bl thumb_Div
	bl thumb_ArcTan
	adds r7, r7, r7	@ 0x10000
	adds r0, r7, r0
arctan2_return:
	pop {r4, r5, r6, r7}
	pop {r3}
	bx r3	@ return to ARM (swi_return) or Thumb
