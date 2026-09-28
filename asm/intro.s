@ intro.s 0x1928-0x1DC3: boot_intro (the whole boot screen) and thumb_umul_high,
@ a multiply helper for MidiKey2Freq that follows it.
@
@ HardReset calls boot_intro with lr = SoftReset, so the return starts the
@ cartridge (or a MultiBoot program). boot_intro does these steps:
@   1. Setup.
@   2. 211 frames of animation (frame counter r7 = 0 to 210).
@   3. The header check.
@   4. In some cases, a wait for MultiBoot.
@   5. A fade to white, then the return.
@ Read this file with header.s. intro_load_graphics there loads every picture
@ used here, and small helpers there (intro_letter_path, intro_letter_affine,
@ intro_fade_colors) do the maths.
@ All of this is from the code. Where a comment says that something was also
@ run, that was in the GBA core of DinoRec (an emulator), not on hardware.
@
@ THE SCREEN. Mode 2. The backdrop (BG colour 0) is white.
@   OAM 0-6    The letters. Slot n = entry n = affine group n + 1, RIGHT TO
@              LEFT: 0 Y, 1 O, 2 B, 3 E, 4 M, 5 A, 6 G (gameboy_art cell
@              6 - n). 256 colours, priority 2, semi-transparent. 64x64, with
@              the 32x32 letter in the middle. Hidden at the start.
@   OAM 7-8    The Nintendo logo of the cartridge (header.s), as two 64x32
@              halves at (55, 102) and (119, 102). On the screen: X 71-174,
@              Y 110-125, colour 31 (magenta, intro_palette). Semi-transparent,
@              shown from frame 0.
@   OAM 9      The ball (cell 7) as a 32x32 sprite, priority 0. Hidden until
@              frame 109, then the streak on the logo (see THE BALL).
@   OAM 16-24  From frame 109: copies of entries 0-8, made each frame, in
@              OBJ-window mode. The window has the shapes of the letters and
@              the logo.
@   BG3        Affine, 256x256, wrapping. Its map has only the ball, at BG
@              pixels (0-31, 32-63) (header.s: fill_2d). On from frame 109.
@
@ THE FRAME SCHEDULE (r7). Letter slot n starts at frame s = 38 - 5n:
@ G 8, A 13, M 18, E 23, B 28, O 33, Y 38.
@   setup      RegisterRamReset(0xFF), POSTFLG = 1, SoundBias up, VBlank IRQ
@              on. A Game Boy cartridge goes to start_cgb_cartridge and does
@              not return. Then intro_load_graphics, BG3, blending, sound.
@   0-15       The logo fades in from white: BLDALPHA EVA 0 -> 16 and
@              EVB 16 -> 0, one step per frame.
@   0-107      DISPCNT 0x1002: mode 2, sprites only.
@   s          The letter starts. s + 15: it shows. s + 62: it lands.
@   16         SoundDriverMain from this frame on, each frame. song_intro.
@   65-143     The Select+Start check (see THE CHECKS).
@   57-210     When the Select+Start flag is set: the logo (colour 31) fades
@              to white, 2/32 per frame.
@   s+62..96   The letter bounces (intro_bounce). Landings are at frames 70,
@              75, 80, 85, 90, 95, 100 (G ... Y).
@   s+95..175  The letter colour pulses: blue, magenta, blue. G 103-183 ...
@              Y 133-213, so the pulse of Y stops early, at 210.
@   108        The shine: BLDCNT 0x1F5F, BG3 moves to the left of the letters.
@   109-210    DISPCNT 0x9802 (BG3, sprites, OBJ window), WINOUT 0x3F27, the
@              OBJ-window copies. BG3 moves right 3 px per frame, sprite 9
@              moves right 4 px. Every 6th frame: EVA + 1, EVB - 1.
@   162        song_intro_end.
@   180        The shine event again. This time BG3 goes below the screen,
@              so the shine on the letters ends.
@   after 210  The checks, the wait (in some cases), the fade to white, the end.
@
@ HOW A LETTER FLIES. Per slot, in IWRAM:
@   timer  0x03003564 + 4n   t: frames since frame s (0 before frame s)
@   state  0x03003580 + 16n  +0 X, +4 Y (intro_letter_path), +8 c, +0xC unused
@   block  0x030035F0 + 20n  screen centre and scale (intro_letter_affine)
@ c is the depth of the letter minus 128. It starts at -126 (intro_reset_letters)
@ and increases by 2 per frame from frame s. c = 0 means landed, so the flight
@ is 63 frames (t = 1 to 63). At depth z = c + 128, the letter shows at 128/z
@ times its size (64x down to 1x), at 128/z times its offset (X, Y) from the
@ screen centre (120, 80).
@ Each frame while c < 0 (also before frame s, with t = 0; nothing shows):
@   - intro_letter_path, intro_letter_affine, then ObjAffineSet into its group.
@   - c <= -96 (more than 4x, too big for its box): the letter stays hidden.
@   - Else: an affine double-size sprite, its 64x64 in a 128x128 box at
@     centre - 64.
@   - From c >= -64 (2x), or c >= -75 for slots 0-3: the sprite narrows to
@     32x64 (tall shape, tile + 4: only the 32 columns of the letter), a
@     64x128 box at centre - (32, 64). This is probably to stay within the
@     sprite time of a scanline.
@   - When c reaches 0: a plain sprite at centre - (16, 32). This gives
@     exactly the X and Y in intro_oam (34, 57, 80, 104, 127, 150, 173; 32).
@ The letter colours (OBJ 4k+1 to 4k+3, k = 6 - n) come from the depth:
@ intro_fade_colors(set (-c >> 4) + 1, t 2 x (-c & 15)). As the letter comes
@ in, it goes through white, magenta, red, yellow, green, cyan, blue (sets 7
@ down to 1).
@ After landing: intro_bounce moves the letter. The pulse is set 1 (blue) to
@ set 0 (magenta) and back. Seen in DinoRec: the stack and the arrays dumped
@ there after the last frame agree with these predictions.
@
@ THE BALL (cell 7 of gameboy_art) does not move like a letter. It has two uses:
@   - BG3: the light disc that crosses GAME BOY from left to right, in frames
@     109-179, at Y 42-73, BG colours 29-31. It shows only inside the OBJ
@     window (WINOUT 0x3F27: outside, only the backdrop). It blends over the
@     letters (BLDCNT 0x1F5F, EVA 6 rising, EVB 10 falling).
@   - Sprite 9: the streak across the logo, from frame 109. It is affine with
@     group 0 (intro_oam: PA 1, PB 0.25, PC 0, PD 0), so each line of the
@     sprite is the middle row of the ball, a quarter pixel further along per
@     line. The result is a slanted band at Y 104-135, colours 29-30, shown
@     only inside the OBJ window.
@
@ THE CHECKS. The 0x96 check is in intro_load_graphics (header.s): a bad 0xB2
@ blanks the logo, so the logo check then fails. After frame 210,
@ check_cart_header does the logo check and the complement check. Results:
@   Good, no Select+Start: the hand-over, to 0x08000000.
@   Bad: the wait loop, forever, unless a MultiBoot program arrives.
@     Buttons do nothing (run in DinoRec: a press of A changes nothing).
@   Good, Select+Start held in frames 65-143: the same wait. But A, B or the
@     d-pad plays song_wait_button, the logo fades back in, and the cartridge
@     starts (run in DinoRec). GBATEK: Select and Start at power-on put a GBA
@     with a cartridge in MultiBoot mode.
@   A MultiBoot program arrives (intro_link_poll returns non-zero): the
@     hand-over with SOFT_RESET_FLAG set. EWRAM is kept, and SoftReset starts
@     0x02000000.
@ The hand-over: fade to white over 32 frames (51 frames in total), sound off,
@ RegisterRamReset, return.
@
@ IWRAM (0x0300xxxx), in addition to the areas in header.s:
@   3564  timers (7 words)
@   3580  states (7 x 16 bytes)
@   35F0  blocks (7 x 20 bytes)
@   36EC  music player 0: song_intro, song_intro_end. Its 6 tracks are at 372C.
@   390C  music player 1: the Select+Start and button songs (and song_multiboot
@         for MultiBoot). Its 6 tracks are at 394C.
@   3B2C  work area of the sound driver (SoundDriverInit)
@ Also: 0x03000088 the header copy; 0x0300000C the MultiBoot state (multiboot.s).
@ BIOS RAM through its mirror at 0x03FFFFF0: INTRO_FLAG, SOFT_RESET_FLAG,
@ MULTIBOOT_FLAG.
@
@ THE BOOT_INTRO STACK (sp after the sub; r7 = frame, r5 = slot, r6 = c):
@   [sp+0x00]  Select+Start logo fade, 0-32 (t for intro_fade_colors)
@   [sp+0x04]  BG3Y in pixels (118; -10 at 108; -138 at 180)
@   [sp+0x08]  BG3X in pixels (84; 28 at 108, then - 3 per frame; - 56 at 180)
@   [sp+0x0C]  EVB: 16 down in frames 0-15; 10 at 108 and 180, then down
@   [sp+0x10]  EVA: 0 up in frames 0-15; 6 at 108 and 180, then up
@   [sp+0x14]  BLDY, the fade to white at the end, 0-16
@   [sp+0x18]  state of this slot
@   [sp+0x1C]  timer of this slot
@   [sp+0x20]  the Select+Start flag. Never set to 0 here: it is 0 because
@              reset_stacks in HardReset cleared 0x03007E00-0x03007FFF.
@   [sp+0x24], [sp+0x28]  block of this slot
@   [sp+0x2C]  8n (offset of its OAM entry, also in intro_oam)
@   [sp+0x30]  6 - n (its cell k)
@
@ BAKED IN, for another word or another number of letters:
@   - 7 letters: movs r5, #7 (slots 6-0), 0x78 in intro_reset_letters, the
@     IWRAM arrays sized for 7 (the timers run into the states, the states
@     into the blocks), 7 affine groups, OAM 0-6. Slot = 6 - cell.
@   - The start frames 38 - 5n and the 5-frame bounce/pulse spacing come from
@     that n (intro_letter). intro_letter_path centres on slot 3, 23 px apart.
@   - The slots that narrow early: cmp r5, #4 (intro_letter_flying).
@   - OAM entries 0-8 are the letters and the logo (cmp r5, #9 at
@     obj_window_copy_loop and cmp r1, #9 at intro_sprites_normal_loop). The
@     ball is entry 9 (OAM + 0x48).
@   - The tiles in intro_oam and intro_letter_tiles (data.s) place the 64x64
@     boxes. OBJ VRAM rows 0-25 are used; rows 26-29 are for the logo.
@   - Colours: cell k uses 4k+1 to 4k+3, so 8 cells fill colours 1-31. The
@     ball colours 29-31 and the logo colour 31 come from intro_palette.
@ The picture (gameboy_art.png) alone changes the glyphs, not the count.

@ The animation, the chime and the header check; returns to SoftReset.
@ In: lr = SoftReset (from HardReset). Out: returns to SoftReset at the end of
@ the intro, after a reset of RAM and registers. It does not return for a
@ Game Boy cartridge (start_cgb_cartridge), or while it waits for MultiBoot.
boot_intro:
	.thumb
	push {r4, r5, r6, r7, lr}
	sub sp, #0x34
	@ ---- setup ----
	movs r1, #0
	movs r0, #0
	str r0, [sp, #0x14]	@ BLDY level = 0
	movs r0, #0x10
	str r0, [sp, #0xC]	@ EVB = 16
	mvns r7, r1	@ r7 = -1: after the increment, the first frame is 0
	movs r0, #0xFF
	str r1, [sp, #0x10]	@ EVA = 0
	str r1, [sp, #0]	@ Select+Start fade = 0
	bl RegisterRamReset	@ 0xFF: everything (except 0x03007E00 and up: this stack)
	ldr r0, intro_postflg_reg	@ =REG_POSTFLG: set to 1 after boot
	movs r5, #1
	strb r5, [r0, #0]	@ POSTFLG = 1: later resets use the debug vector (GBATEK)
	movs r0, #1
	bl SoundBias	@ increase the bias level to 0x200
	ldr r6, intro_ie_reg	@ =REG_IE: to enable the VBlank IRQ
	movs r0, #8
	lsls r1, r0, #0x17	@ r1 = 0x04000000, REG_DISPCNT
	strh r5, [r6, #0]	@ IE = 1: VBlank
	strh r0, [r1, #4]	@ DISPSTAT = 8: VBlank IRQ enable
	ldrh r0, [r6, #4]	@ REG_WAITCNT
	lsrs r0, r0, #0xF	@ bit 15: a Game Boy (Color) cartridge (GBATEK)
	beq intro_graphics
	bl start_cgb_cartridge	@ does not return
intro_graphics:
	bl intro_load_graphics	@ header.s: all pictures, the 0x96 check, OAM
	movs r0, #0xEF
	lsls r0, r0, #7	@ 0x7780
	movs r1, #1
	lsls r1, r1, #0x1A	@ r1 = 0x04000000, REG_DISPCNT
	strh r0, [r1, #0xE]	@ BG3CNT = 0x7780: 256 colours, map at 0xB800, wrap, 256x256
	movs r0, #0x54
	str r0, [sp, #8]	@ BG3X = 84 px
	movs r0, #0x76
	str r0, [sp, #4]	@ BG3Y = 118 px
	movs r0, #0x15
	lsls r0, r0, #0xA
	str r0, [r1, #0x38]	@ REG_BG3X = 0x5400 (84.0)
	movs r0, #0x3B
	lsls r0, r0, #9
	str r0, [r1, #0x3C]	@ REG_BG3Y = 0x7600 (118.0): the ball is off the screen
	ldr r1, intro_blend_base	@ =REG_WIN0H: base for the blend registers
	ldr r0, intro_blend_start	@ =0x10003F5F: BLDCNT 0x3F5F, BLDALPHA 0x1000
	str r0, [r1, #0x10]	@ BLDCNT and BLDALPHA: alpha, EVA 0, EVB 16 (all white)
	bl intro_reset_letters	@ c = -126 for each letter
	bl intro_link_reset	@ MultiBoot state byte (0x0300000C + 0xF) = 0
	ldr r0, intro_sound_area	@ =INTRO_SOUND_AREA: sound driver work area
	bl SoundDriverInit
	ldr r0, intro_sound_mode	@ =0x00940A00: 10 channels, 13379 Hz, 8-bit D/A
	bl SoundDriverMode
	ldr r1, intro_player0_tracks	@ =INTRO_PLAYER0_TRACKS: six tracks of player 0
	ldr r0, intro_player0	@ =INTRO_PLAYER0: music player 0, intro songs
	movs r2, #6
	bl MusicPlayerOpen
	ldr r1, intro_player1_tracks	@ =INTRO_PLAYER1_TRACKS: six tracks of player 1
	ldr r0, intro_player1	@ =INTRO_PLAYER1: music player 1, Select+Start and buttons
	movs r2, #6
	bl MusicPlayerOpen
	b intro_next_frame	@ enter the loop at its end: r7 becomes 0
@ ---- the per-frame loop: the letters ----
@ BAKED IN: 7 letters. r5 starts at 7 and decrements before the first pass,
@ so the passes are slots 6 (G) down to 0 (Y).
intro_frame:
	movs r5, #7
	b intro_next_letter
intro_letter:	@ one letter, slot r5 = n
	movs r0, #6
	subs r2, r0, r5	@ r2 = 6 - n: its cell k
	lsls r0, r2, #2
	adds r0, r0, r2
	adds r0, #8	@ r0 = 5k + 8 = 38 - 5n: its start frame s
	cmp r0, r7
	str r2, [sp, #0x30]
	bgt intro_letter_state	@ not started yet
	ldr r3, intro_letter_timers	@ =LETTER_TIMERS: letter timers
	lsls r1, r5, #2
	ldr r2, [r3, r1]
	adds r2, #1
	str r2, [r3, r1]	@ timer + 1
intro_letter_state:
	ldr r3, intro_letter_timers	@ =LETTER_TIMERS: letter timers
	lsls r1, r5, #2
	ldr r2, [r3, r1]	@ r2 = t
	ldr r3, intro_letter_states	@ =LETTER_STATES: letter states
	lsls r1, r5, #4
	adds r1, r1, r3
	lsls r4, r5, #3
	str r1, [sp, #0x18]
	str r2, [sp, #0x1C]
	ldr r6, [r1, #8]	@ r6 = c
	movs r3, #7
	lsls r3, r3, #0x18	@ 0x07000000, OAM
	str r4, [sp, #0x2C]
	adds r4, r4, r3	@ r4 = its OAM entry
	cmp r6, #0
	bge intro_letter_bounce	@ landed: only the bounce and the pulse
	cmp r0, r7
	bgt intro_letter_flying	@ not started: c stays -126
	adds r6, #2
	str r6, [r1, #8]	@ c + 2
@ In flight (or waiting to start): position, size and colour.
intro_letter_flying:
	lsls r0, r5, #0x10
	asrs r0, r0, #0x10	@ n
	ldr r1, [sp, #0x18]
	bl intro_letter_path	@ X, Y from t (r2)
	movs r0, #0x14
	muls r0, r5
	ldr r1, intro_letter_blocks	@ =LETTER_AFFINE: affine blocks, 20 bytes each
	adds r1, r0, r1
	str r1, [sp, #0x28]
	str r1, [sp, #0x24]
	ldr r0, [sp, #0x18]
	bl intro_letter_affine	@ the block: screen centre, scale 2z
	lsls r0, r5, #5
	ldr r3, intro_affine_group1	@ =OAM + 0x26: group 1 PA (group g at + 32g + 6)
	movs r2, #1	@ one group
	adds r1, r0, r3	@ group n + 1
	ldr r0, [sp, #0x24]
	movs r3, #8	@ OAM spacing
	adds r0, #0xC	@ block + 0xC: scale X, scale Y, angle
	bl thumb_ObjAffineSet
	movs r3, #0x60
	cmn r6, r3
	ble intro_letter_color	@ c <= -96 (4x or more, too big for the box): stay hidden
	ldr r0, [r4, #0]	@ attributes 0 and 1
	lsls r2, r3, #3
	orrs r2, r0	@ | 0x300: affine, double size (shown)
	movs r0, #0x3F
	mvns r0, r0	@ r0 = -64: X offset from the centre to the box corner
	adds r1, r0, #0	@ r1 = -64: the same for Y
	cmp r6, r0
	str r2, [r4, #0]
	bge intro_letter_narrow	@ c >= -64 (2x or less)
	cmp r5, #4
	bge intro_letter_place	@ slots 4-6 (M A G): keep the 64x64 until -64
intro_letter_narrow:	@ slots 0-3 (Y O B E) narrow from -75, the others from -64
	movs r3, #0x4B
	cmn r6, r3
	blt intro_letter_place	@ c < -75: keep the 64x64
	cmp r6, #0
	bge intro_letter_landed	@ c = 0: landed this frame
	@ Narrow: tall shape (32x64 at size 3), and tile + 4 (two 8bpp tiles to
	@ the right), so the 32 columns are those of the letter. The box is 64 wide.
	ldrh r0, [r4, #0]
	movs r3, #1
	lsls r3, r3, #0xF
	orrs r0, r3	@ attr0 bit 15: shape 2, tall
	strh r0, [r4, #0]
	ldr r0, [sp, #0x2C]
	ldr r2, intro_oam_ptr	@ =intro_oam: source of the tile number (to add 4)
	adds r0, r0, r2
	ldrh r2, [r4, #4]
	ldrh r0, [r0, #4]	@ attribute 2 in intro_oam
	lsrs r2, r2, #0xA
	lsls r2, r2, #0xA	@ keep priority and palette
	adds r0, #4
	lsls r0, r0, #0x16
	lsrs r0, r0, #0x16	@ tile + 4
	orrs r0, r2
	strh r0, [r4, #4]
	movs r0, #0x1F
	mvns r0, r0	@ r0 = -32: half the box width; r1 is still -64
	b intro_letter_place
intro_letter_landed:	@ landed: a plain 32x64 sprite, full size
	movs r3, #3
	lsls r3, r3, #8
	bics r2, r3	@ not affine, not double size
	movs r0, #0xF
	mvns r0, r0	@ r0 = -16
	lsls r1, r0, #1	@ r1 = -32
	str r2, [r4, #0]
intro_letter_place:	@ place it: attr1 X = centre X + r0, attr0 Y = centre Y + r1
	ldr r2, [sp, #0x28]
	ldr r3, intro_oam_x_mask	@ =0xFE00FFFF: all bits except attr1 X (16-24)
	ldrh r2, [r2, #8]	@ screen X from the block
	adds r0, r2, r0
	ldr r2, [r4, #0]
	ands r2, r3
	lsls r0, r0, #0x17
	lsrs r0, r0, #0x17
	lsls r0, r0, #0x10
	orrs r0, r2
	str r0, [r4, #0]	@ X, 9 bits
	ldr r2, [sp, #0x28]
	ldrh r2, [r2, #0xA]	@ screen Y from the block
	adds r1, r2, r1
	lsrs r0, r0, #8
	lsls r0, r0, #8
	lsls r1, r1, #0x18
	lsrs r1, r1, #0x18
	orrs r0, r1
	str r0, [r4, #0]	@ Y, 8 bits
intro_letter_color:	@ colour from the depth: set (-c >> 4) + 1, t = 2 x (-c & 15)
	negs r0, r6
	lsls r1, r0, #0x1C
	lsrs r1, r1, #0x1C
	lsls r1, r1, #1
	ldr r2, [sp, #0x30]
	asrs r0, r0, #4
	lsls r2, r2, #2
	adds r0, #1
	adds r2, #1	@ OBJ colour 4k + 1
	bl intro_fade_colors
intro_letter_bounce:	@ bounce: t = 63 to 97, add intro_bounce[t - 63] to attr0 Y
	ldr r2, [sp, #0x1C]
	subs r0, r2, #7
	subs r0, #0x38	@ t - 63
	cmp r0, #0x22
	bhi intro_letter_pulse	@ not in 0-34
	ldr r0, intro_bounce_ptr	@ =intro_bounce: 35 Y steps, signed bytes, sum 0
	ldr r2, [sp, #0x1C]
	adds r0, r0, r2
	subs r0, #0x40
	ldrb r1, [r0, #1]	@ intro_bounce[t - 63]
	ldr r0, [r4, #0]
	lsrs r2, r0, #8
	lsls r2, r2, #8
	adds r0, r0, r1
	lsls r0, r0, #0x18
	lsrs r0, r0, #0x18	@ Y + step, mod 256
	orrs r0, r2
	str r0, [r4, #0]
intro_letter_pulse:	@ pulse: t = 96 to 176, blue (set 1) to magenta (set 0) and back
	ldr r2, [sp, #0x1C]
	subs r1, r2, #7
	subs r1, #0x59	@ t - 96
	cmp r1, #0x50
	bhi intro_next_letter	@ not in 0-80
	movs r0, #5
	bl thumb_DivArm	@ r0 = (t - 96) / 5: 0-16
	subs r0, #8
	bl abs
	ldr r2, [sp, #0x30]
	lsls r1, r0, #2	@ t for the fade = 4 x |q - 8|: 32 ... 0 ... 32
	lsls r0, r2, #2
	adds r2, r0, #1	@ OBJ colour 4k + 1
	movs r0, #0	@ set 0 -> 1
	bl intro_fade_colors
intro_next_letter:	@ next letter
	subs r5, #1
	bmi intro_after_letters
	b intro_letter
@ ---- the per-frame loop: the shine, the display, sound, buttons ----
intro_after_letters:
	movs r4, #7
	lsls r4, r4, #0x18	@ r4 = 0x07000000, OAM
	cmp r7, #0x6C
	beq intro_shine_event	@ frame 108
	cmp r7, #0xB4
	bne intro_shine_running	@ not frame 180
@ Frames 108 and 180: move BG3 (the ball) and restart the shine blend.
@ At 108, the ball goes to screen (-28, 42), left of the letters. At 180, BG3Y
@ becomes -138, which puts the ball at screen Y 170, below the screen.
@ DISPCNT and OAM do not change in this frame.
intro_shine_event:
	ldr r0, [sp, #8]
	movs r1, #6
	subs r0, #0x38
	str r0, [sp, #8]	@ BG3X - 56
	ldr r0, [sp, #4]
	str r1, [sp, #0x10]	@ EVA = 6
	subs r0, #0x80
	str r0, [sp, #4]	@ BG3Y - 128
	movs r0, #0xA
	str r0, [sp, #0xC]	@ EVB = 10
	ldr r0, intro_blend_shine	@ =0x10001F5F: BLDCNT 0x1F5F, BLDALPHA 0x1000
	ldr r1, intro_blend_base	@ =REG_WIN0H: base for the blend registers
	str r0, [r1, #0x10]	@ BLDCNT: alpha, 1st BG0-3+OBJ, 2nd BG0-3+OBJ (no backdrop)
	b intro_every_frame
intro_shine_running:
	cmp r7, #0x6C
	ble intro_display_plain	@ frames 0-107: DISPCNT 0x1002
@ Frames 109-210 (not 180): the shine runs.
	ldr r0, [sp, #8]
	subs r0, #3
	str r0, [sp, #8]	@ BG3X - 3: the ball moves right 3 px
	@ Sprite 9, the ball: affine (the streak), or hidden with Select+Start.
	@ It moves 4 px further right.
	ldr r0, [sp, #0x20]
	cmp r0, #0
	bne ball_sprite_hidden
	movs r0, #1	@ no Select+Start: attr0 bit 8, affine
	b ball_sprite_update
ball_sprite_hidden:
	movs r0, #2	@ Select+Start: attr0 bit 9 only, hidden
ball_sprite_update:
	movs r3, #3
	ldr r1, [r4, #0x48]	@ attributes 0 and 1 of OAM entry 9
	lsls r3, r3, #8
	bics r1, r3
	lsls r0, r0, #0x1E
	lsrs r0, r0, #0x1E
	lsls r0, r0, #8
	orrs r0, r1
	ldr r1, intro_oam_x_mask	@ =0xFE00FFFF: all bits except attr1 X (16-24)
	ands r1, r0
	movs r3, #1
	lsls r3, r3, #0x12
	adds r0, r0, r3	@ X + 4
	ldr r3, intro_oam_x_mask	@ =0xFE00FFFF: all bits except attr1 X (16-24)
	bics r0, r3
	orrs r0, r1
	str r0, [r4, #0x48]
	@ The OBJ window: copy entries 0-8 (the letters, the logo) to 16-24, and
	@ change their mode bits from semi-transparent (1) to OBJ window (2).
	@ BAKED IN: 9 entries.
	movs r5, #0
obj_window_copy_loop:
	lsls r0, r5, #3
	adds r0, r0, r4
	adds r1, r0, #7
	adds r1, #0x79	@ + 0x80: entry + 16
	movs r2, #3	@ CpuSet: 3 halfwords, attributes 0-2
	adds r6, r1, #0
	bl CpuSet
	ldrh r0, [r6, #0]
	movs r3, #3
	lsls r3, r3, #0xA
	eors r0, r3	@ attr0 bits 10-11: 1 -> 2
	adds r5, #1
	cmp r5, #9
	strh r0, [r6, #0]
	blt obj_window_copy_loop
	movs r0, #6
	adds r1, r7, #0
	bl thumb_DivArm	@ r1 = frame mod 6
	cmp r1, #0
	bne intro_shine_display
	@ Every 6th frame, the shine gets stronger: EVA + 1, EVB - 1. From frame
	@ 174, EVB is -1; the register field is then 0x1F, which means 16.
	ldr r1, [sp, #0x10]
	ldr r0, [sp, #0xC]
	adds r1, #1
	subs r0, #1
	str r0, [sp, #0xC]
	lsls r0, r0, #8
	orrs r0, r1
	str r1, [sp, #0x10]
	ldr r1, intro_blend_base	@ =REG_WIN0H: base for the blend registers
	strh r0, [r1, #0x12]	@ BLDALPHA
intro_shine_display:
	ldr r0, intro_winout_shine	@ =0x00003F27: WINOUT
	ldr r1, intro_blend_base	@ =REG_WIN0H
	strh r0, [r1, #0xA]	@ WINOUT: OBJ window all on; outside BG0-2 + effects
	ldr r0, intro_dispcnt_shine	@ =0x00009802: DISPCNT for the shine
	b intro_set_dispcnt
intro_display_plain:
	ldr r0, intro_dispcnt_plain	@ =0x00001002: DISPCNT before the shine
intro_set_dispcnt:
	movs r1, #1
	lsls r1, r1, #0x1A	@ r1 = 0x04000000, REG_DISPCNT
	strh r0, [r1, #0]
@ Every frame: BG3 position, sound, the songs, Select+Start.
intro_every_frame:
	ldr r0, [sp, #8]
	lsls r0, r0, #8
	movs r1, #1
	lsls r1, r1, #0x1A	@ r1 = 0x04000000
	str r0, [r1, #0x38]	@ REG_BG3X
	ldr r0, [sp, #4]
	lsls r0, r0, #8
	str r0, [r1, #0x3C]	@ REG_BG3Y
	cmp r7, #0x10
	blt intro_check_end_song	@ before frame 16: no SoundDriverMain
	bl SoundDriverMain
	cmp r7, #0x10
	bne intro_check_end_song
	ldr r1, intro_song_start_ptr	@ =song_intro: frame 16
	b intro_start_song
intro_check_end_song:
	cmp r7, #0xA2
	bne intro_select_start_check
	ldr r1, intro_song_end_ptr	@ =song_intro_end: frame 162
intro_start_song:
	ldr r0, intro_player0	@ =INTRO_PLAYER0: music player 0
	bl MusicPlayerStart
@ The Select+Start check: frames 65-143, once. The first word of the header
@ copy must not be 0xFFFFFFFF (that is, the 0x96 check passed).
intro_select_start_check:
	subs r0, r7, #7
	subs r0, #0x3A	@ frame - 65
	cmp r0, #0x4F
	bcs intro_select_start_fade	@ not in 0-78
	ldr r0, [sp, #0x20]
	cmp r0, #0
	bne intro_select_start_fade	@ already set
	ldr r0, intro_header_base	@ =HEADER_COPY_BASE: + 0x24 = copy (0x03000088)
	movs r3, #1
	ldr r0, [r0, #0x24]	@ header bytes 0x04-0x07
	cmn r0, r3
	beq intro_select_start_fade	@ 0xFFFFFFFF: blanked by the 0x96 check
	ldr r0, intro_keyinput_reg	@ =REG_KEYINPUT: 0 = pressed
	ldrb r0, [r0, #0]
	cmp r0, #0xF3
	bne intro_select_start_fade	@ not only Select + Start (A B Sel Start R L U D)
	ldr r1, intro_song_select_start_ptr	@ =song_hold_select_start
	ldr r0, intro_player1	@ =INTRO_PLAYER1: music player 1
	bl MusicPlayerStart
	movs r0, #1
	str r0, [sp, #0x20]	@ set the flag: wait for MultiBoot at the end
@ With the flag, from frame 57: the logo (colour 31) fades to white.
intro_select_start_fade:
	cmp r7, #0x38
	ble intro_end_of_frame
	ldr r0, [sp, #0x20]
	cmp r0, #0
	beq intro_end_of_frame
	ldr r1, [sp, #0]
	cmp r1, #0x20
	bge intro_logo_fade
	ldr r1, [sp, #0]
	adds r1, #2
	str r1, [sp, #0]	@ + 2 per frame, up to 32
intro_logo_fade:
	movs r2, #0x1F	@ OBJ colours 31-33 (31 is the logo colour)
	movs r0, #6	@ set 6 (magenta) -> 7 (white)
	ldr r1, [sp, #0]
	bl intro_fade_colors
@ The end of the frame: the link port, the VBlank wait.
intro_end_of_frame:
	bl intro_link_poll	@ multiboot.s: look for a MultiBoot master; result unused
	ldr r1, intro_ie_reg	@ =REG_IE: + 8 is REG_IME
	movs r0, #1
	strh r0, [r1, #8]	@ IME = 1 (intro_link_poll disables and enables it)
	bl thumb_VBlankIntrWait
	cmp r7, #0x10
	bge intro_next_frame
	@ Frames 0-15, in VBlank: the logo fades in, EVA + 1, EVB - 1.
	ldr r1, [sp, #0x10]
	ldr r0, [sp, #0xC]
	adds r1, #1
	subs r0, #1
	str r0, [sp, #0xC]
	lsls r0, r0, #8
	orrs r0, r1
	str r1, [sp, #0x10]
	ldr r1, intro_blend_base	@ =REG_WIN0H: base for the blend registers
	strh r0, [r1, #0x12]	@ BLDALPHA
intro_next_frame:	@ next frame
	adds r7, #1
	cmp r7, #0xD2
	bgt intro_check_header	@ after frame 210
	b intro_frame
@ ---- the end: the logo check and the complement check ----
intro_check_header:
	ldr r0, intro_header_copy	@ =HEADER_COPY: the header copy, from byte 0x04
	bl check_cart_header
	movs r6, #0
	adds r7, r0, #0	@ r7 = 0 good, 1 bad
	cmp r0, #0
	ldr r5, intro_bios_ram	@ =BIOS_RAM_MIRROR: mirror of 0x03007FF0 (BIOS RAM bytes)
	bne intro_wait_multiboot	@ bad
	ldr r0, [sp, #0x20]
	cmp r0, #0
	beq intro_hand_over	@ good, no Select+Start: start the cartridge
@ ---- the failure path: wait for MultiBoot ----
@ Bad header, or Select+Start held. MULTIBOOT_FLAG = 1 tells intro_link_poll
@ that the BIOS is ready as a MultiBoot slave. INTRO_FLAG stays 0 until
@ decode_cart_logo gets a received header.
intro_wait_multiboot:
	movs r0, #1
	strb r0, [r5, #0xB]	@ MULTIBOOT_FLAG (0x03007FFB) = 1
	strb r6, [r5, #7]	@ INTRO_FLAG (0x03007FF7) = 0
intro_wait_loop:	@ wait loop, one frame per loop
	bl intro_link_poll
	lsls r0, r0, #0x18
	lsrs r0, r0, #0x18
	strb r0, [r5, #0xA]	@ SOFT_RESET_FLAG (0x03007FFA) = low byte of the result
	bne intro_hand_over	@ a MultiBoot program has arrived: start it
	bl SoundDriverMain
	bl thumb_VBlankIntrWait
	cmp r7, #0
	bne intro_wait_loop	@ bad header: only the wait, forever
	ldrb r0, [r5, #7]
	cmp r0, #0
	bne intro_wait_loop	@ a MultiBoot header has arrived: no cancel now
	ldrb r0, [r5, #0xB]
	cmp r0, #0
	beq intro_wait_fade_back	@ a button was pressed: fade back in
	@ Select+Start, still waiting: A, B or the d-pad cancels.
	ldr r0, intro_keyinput_reg	@ =REG_KEYINPUT
	ldrb r0, [r0, #0]
	mvns r0, r0
	movs r3, #0xF3
	ands r0, r3	@ pressed: A, B, Right, Left, Up, Down (not Select, Start)
	beq intro_wait_loop
	ldr r1, intro_song_wait_button_ptr	@ =song_wait_button
	ldr r0, intro_player1	@ =INTRO_PLAYER1: music player 1
	bl MusicPlayerStart
	strb r6, [r5, #0xB]	@ MULTIBOOT_FLAG = 0: no longer a slave
	b intro_wait_loop
intro_wait_fade_back:	@ logo back from white, one step per frame; then the cartridge
	ldr r1, [sp, #0]
	cmp r1, #0
	ble intro_hand_over
	ldr r1, [sp, #0]
	movs r2, #0x1F	@ OBJ colours 31-33
	subs r1, #1
	str r1, [sp, #0]
	movs r0, #6	@ set 6 -> 7, as in the fade out
	bl intro_fade_colors
	b intro_wait_loop
@ ---- the hand-over: fade everything to white ----
intro_hand_over:
	ldr r1, intro_blend_fade_out	@ =0x00103FBF: BLDCNT 0x3FBF, BLDALPHA 0x0010
	ldr r0, intro_blend_base	@ =REG_WIN0H: base for the blend registers
	str r1, [r0, #0x10]	@ BLDCNT: brighten everything; BLDALPHA EVA 16, EVB 0
	str r6, [r0, #0x14]	@ BLDY = 0 (and 0x04000056, unused)
	@ Set entries 0-8 (the letters, the logo) to normal mode. GBATEK: a
	@ semi-transparent sprite over a 2nd target is blended, not brightened.
	@ BAKED IN: 9 entries.
	movs r1, #0
intro_sprites_normal_loop:
	lsls r2, r1, #3
	ldr r7, [r4, r2]	@ r4 is still OAM
	movs r3, #3
	lsls r3, r3, #0xA
	bics r7, r3	@ attr0 bits 10-11 = 0: normal
	adds r1, #1
	cmp r1, #9
	str r7, [r4, r2]
	blt intro_sprites_normal_loop
	movs r7, #0
	mvns r7, r7	@ r7 = -1: counts frames 0-50
	adds r4, r0, #0	@ r4 = REG_WIN0H
	b intro_fade_out_next
intro_fade_out_loop:	@ 51 frames: BLDY + 1 each even frame, to 16 (white) at frame 30
	bl SoundDriverMain
	bl thumb_VBlankIntrWait
	lsrs r0, r7, #1
	bcs intro_fade_out_next	@ odd frame
	ldr r0, [sp, #0x14]
	cmp r0, #0x10
	beq intro_fade_out_next	@ already white
	ldr r0, [sp, #0x14]
	adds r0, #1
	str r0, [sp, #0x14]
	str r0, [r4, #0x14]	@ BLDY
intro_fade_out_next:
	adds r7, #1
	cmp r7, #0x32
	ble intro_fade_out_loop
	bl SoundDriverVSyncOff
	@ RegisterRamReset: 0xFF (everything) for a cartridge. 0xDE keeps EWRAM
	@ (bit 0) and the SIO registers (bit 5) for a MultiBoot program.
	@ SOFT_RESET_FLAG is not reset, and tells SoftReset which one to start.
	ldrb r0, [r5, #0xA]	@ SOFT_RESET_FLAG
	cmp r0, #0
	beq intro_reset_all
	movs r0, #0xDE
	b intro_reset_and_return
@ A branch after a branch: never reached, but it is code.
intro_unreached_branch:
	b intro_reset_all
	.balign 4
@ The literals of boot_intro. REG_WIN0H (0x04000040) is a base address for:
@   + 0xA   WINOUT
@   + 0x10  BLDCNT (a word store also writes BLDALPHA, + 0x12)
@   + 0x14  BLDY
intro_postflg_reg:
	.4byte REG_POSTFLG	@ set to 1 at the start: the BIOS has booted
intro_ie_reg:
	.4byte REG_IE	@ IE = VBlank at the start; + 8 is IME, set each frame
@ BLDCNT 0x3F5F: alpha; 1st target BG0-3 and OBJ, 2nd all and the backdrop.
@ BLDALPHA 0x1000: EVA 0, EVB 16. The logo starts invisible (all white).
intro_blend_start:
	.4byte 0x10003F5F	@ BLDCNT and BLDALPHA, at the start
intro_blend_base:
	.4byte REG_WIN0H	@ the base for WINOUT, BLDCNT, BLDALPHA, BLDY (above)
intro_sound_area:
	.4byte INTRO_SOUND_AREA	@ IWRAM: sound driver work area, for SoundDriverInit
intro_sound_mode:
	.4byte 0x00940A00	@ SoundDriverMode: 10 channels, 13379 Hz, 8-bit D/A (GBATEK)
intro_player0_tracks:
	.4byte INTRO_PLAYER0_TRACKS	@ IWRAM: music player 0 tracks, 6 x 0x50 bytes
intro_player0:
	.4byte INTRO_PLAYER0	@ IWRAM: music player 0, for song_intro and song_intro_end
intro_player1_tracks:
	.4byte INTRO_PLAYER1_TRACKS	@ IWRAM: six tracks of music player 1
intro_player1:
	.4byte INTRO_PLAYER1	@ IWRAM: music player 1, for Select+Start and the button
intro_letter_timers:
	.4byte LETTER_TIMERS	@ IWRAM: letter timers, 7 words
intro_letter_states:
	.4byte LETTER_STATES	@ IWRAM: letter states (X, Y, c), 7 x 16 bytes
intro_letter_blocks:
	.4byte LETTER_AFFINE	@ IWRAM: letter affine blocks, 7 x 20 bytes
intro_affine_group1:
	.4byte OAM + 0x26	@ PA of affine group 1: the letters use groups 1-7
intro_oam_ptr:
	.4byte intro_oam	@ the sprites as loaded: a narrow letter uses its tile + 4
intro_oam_x_mask:
	.4byte 0xFE00FFFF	@ mask: attributes 0 and 1 as a word, except attr1 X
intro_bounce_ptr:
	.4byte intro_bounce	@ the landing bounce: 35 Y steps
@ BLDCNT 0x1F5F: as 0x3F5F, but the backdrop is not a 2nd target, so only the
@ ball over a letter blends. BLDALPHA 0x1000, then EVA 6 / EVB 10 (in RAM).
intro_blend_shine:
	.4byte 0x10001F5F	@ BLDCNT and BLDALPHA for the shine: frames 108, 180
intro_winout_shine:
	.4byte 0x00003F27	@ WINOUT: OBJ window BG0-3+OBJ+effects; outside BG0-2+effects
intro_dispcnt_shine:
	.4byte 0x00009802	@ DISPCNT from 109: mode 2, BG3, OBJ, OBJ window, 2D mapping
intro_dispcnt_plain:
	.4byte 0x00001002	@ DISPCNT before the shine: mode 2, OBJ only, 2D mapping
intro_song_start_ptr:
	.4byte song_intro	@ frame 16
intro_song_end_ptr:
	.4byte song_intro_end	@ frame 162
intro_header_base:
	.4byte HEADER_COPY_BASE	@ IWRAM: + 0x24 is the header copy (probably a struct)
intro_keyinput_reg:
	.4byte REG_KEYINPUT	@ Select+Start in frames 65-143; buttons in the wait loop
intro_song_select_start_ptr:
	.4byte song_hold_select_start	@ Select and Start held in time
intro_header_copy:
	.4byte HEADER_COPY	@ IWRAM: the header copy, from byte 0x04, to check
@ 0x03007FF0 through the IWRAM mirror. Byte flags: + 7 INTRO_FLAG,
@ + 0xA SOFT_RESET_FLAG, + 0xB MULTIBOOT_FLAG.
intro_bios_ram:
	.4byte BIOS_RAM_MIRROR	@ the BIOS RAM bytes, for the wait and the end
intro_song_wait_button_ptr:
	.4byte song_wait_button	@ A, B or the d-pad, in the wait after Select+Start
@ BLDCNT 0x3FBF: brightness increase; 1st target all layers and the backdrop.
@ BLDALPHA 0x0010: EVA 16, EVB 0.
intro_blend_fade_out:
	.4byte 0x00103FBF	@ BLDCNT and BLDALPHA for the fade to white
intro_reset_all:
	movs r0, #0xFF	@ a cartridge: reset everything
intro_reset_and_return:
	bl RegisterRamReset
	add sp, #0x34
	pop {r4, r5, r6, r7}
	pop {r3}
	bx r3	@ to SoftReset
	.byte 0x00, 0x00
@ The high word of an unsigned 32 x 32 multiply: r0 = (r0 x r1) >> 32.
@ MidiKey2Freq (sound.s) calls it twice; nothing in this file calls it. The
@ MP2000 name is umul3232H32. Thumb entry, then ARM (umull has no Thumb form).
@ In: r0, r1. Out: r0. Clobbers r2, r3.
thumb_umul_high:
	adr r2, umul_high
	bx r2
	.arm
	.balign 4
umul_high:
	umull r2, r3, r0, r1
	add r0, r3, #0
	bx lr
