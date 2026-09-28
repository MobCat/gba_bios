@ data.s 0x30B0-0x3FFF: the BIOS data, up to the end of the BIOS. In address order:
@   - tables for the intro graphics and for the sound driver
@   - the intro colours
@   - the assets (.incbin from assets/)
@   - five small Thumb-to-ARM veneers (code, placed between the data)
@   - the sound driver jump table, voices, songs and samples
@
@ Two bounds in the code are labels in this file, and move with the data:
@   - copy_bios_data (header.s) copies only from intro_colors up to 0x4000.
@     All data that the intro copies with it must be at or after intro_colors.
@   - sound_read_byte (sound_driver.s) only returns bytes from sound_jump_table
@     up. Songs, voices and samples must be at or after sound_jump_table.
@ The BIOS ends at bios_end, which must stay below 0x4000.

@ ---------------------------------------------------------------------------
@ The intro graphics tables
@ ---------------------------------------------------------------------------

	.balign 4
@ The OBJ VRAM position of each 32x32 letter: G A M E B O Y, then the ball.
@ Units are 64 bytes (one 8bpp tile), from OBJ_VRAM.
@ intro_load_graphics copies the 4x4 tiles of each letter to its position, one row
@ of four tiles at a time. In the 2D mapping, tile rows are 1 KiB apart.
@ For the seven letters, the position is two tiles right and two tiles down from
@ the top-left of a 64x64 sprite (intro_oam). Thus the letter is in the middle of
@ a larger sprite, in which it can rotate and grow.
@ The ball position (0x148) is the top-left of its own 32x32 sprite.
intro_letter_tiles:
	.2byte 0x0022, 0x0028, 0x0082, 0x0088, 0x00E2, 0x00E8, 0x0142, 0x0148
	.balign 4
	
@ BitUnPack parameters for the art of each letter (GBATEK: UnPackInfo).
@ 512 bytes in, 2 bits per pixel to 8, and a word that is added to every non-zero
@ pixel. intro_load_graphics copies this to the stack and writes 4 x the letter
@ number into that word. Thus the three colours of letter k are OBJ palette
@ entries 4k+1 to 4k+3. Pixel value 0 stays 0 (transparent).
intro_letter_unpack:
	.4byte 0x08020200	@ source length 0x200, source width 2, destination width 8
	.4byte 0x00000000	@ added to non-zero pixels (replaced per letter)
	.balign 4
	
@ BitUnPack parameters for the cartridge logo, after decode_cart_logo.
@ 448 bytes of 1bpp to 8bpp. Set pixels get +30: palette entry 31, which
@ load_intro_palette sets to magenta.
logo_unpack:
	.4byte 0x080101C0	@ source length 0x1C0, source width 1, destination width 8
	.4byte 0x0000001E	@ added to set pixels: 1 + 30 = entry 31

@ ---------------------------------------------------------------------------
@ The sound driver tables: the same values as the MP2000 tables
@ ---------------------------------------------------------------------------

@ The length in ticks of each wait and each note.
@ Wait commands 0x80-0xB0 (W00-W96) index this table from 0x80. Note commands
@ 0xD0-0xFF (N01-N96) index it from 0xCF. 49 entries and three bytes of padding.
	.balign 4
sound_clock_table:
	.byte 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F
	.byte 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x1C, 0x1E, 0x20, 0x24, 0x28, 0x2A, 0x2C
	.byte 0x30, 0x34, 0x36, 0x38, 0x3C, 0x40, 0x42, 0x44, 0x48, 0x4C, 0x4E, 0x50, 0x54, 0x58, 0x5A, 0x5C
	.byte 0x60, 0x00, 0x00, 0x00
	
@ The octave shift and the semitone of each MIDI key 0-179, one byte per key:
@   high nibble  the number of octaves to shift the frequency down (14 for the
@                lowest keys, 0 for the highest)
@   low nibble   the semitone: an index into the twelve of sound_freq_table
@ MidiKey2Freq and the note code of the driver use it.
	.balign 4
sound_scale_table:
	.byte 0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xEB, 0xD0, 0xD1, 0xD2, 0xD3
	.byte 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xDB, 0xC0, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7
	.byte 0xC8, 0xC9, 0xCA, 0xCB, 0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xBB
	.byte 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xAB, 0x90, 0x91, 0x92, 0x93
	.byte 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0x9B, 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87
	.byte 0x88, 0x89, 0x8A, 0x8B, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B
	.byte 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x50, 0x51, 0x52, 0x53
	.byte 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x5B, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47
	.byte 0x48, 0x49, 0x4A, 0x4B, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B
	.byte 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x10, 0x11, 0x12, 0x13
	.byte 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07
	.byte 0x08, 0x09, 0x0A, 0x0B
	
@ The twelve semitones of an octave, as 2^(n/12) with 0x80000000 as 1.0:
@ C, C#, D ... B.
	.balign 4
sound_freq_table:
	.4byte 0x80000000
	.4byte 0x879C7C97
	.4byte 0x8FACD61E
	.4byte 0x9837F052
	.4byte 0xA14517CC
	.4byte 0xAADC0848
	.4byte 0xB504F334
	.4byte 0xBFC886BB
	.4byte 0xCB2FF52A
	.4byte 0xD744FCCB
	.4byte 0xE411F03A
	.4byte 0xF1A1BF39
	
@ The number of samples that the mixer makes per frame, for each sample rate.
@ One entry for each of the twelve rates of SoundDriverMode: 96 (5734 Hz), 132,
@ 176, 224 (13379 Hz), 264, 304, 352, 448, 528, 608, 672, 704 (42048 Hz).
@ The rate is this value x 59.73.
	.balign 4
sound_pcm_samples_per_vblank:
	.2byte 0x0060, 0x0084, 0x00B0, 0x00E0, 0x0108, 0x0130, 0x0160, 0x01C0
	.2byte 0x0210, 0x0260, 0x02A0, 0x02C0

@ ---------------------------------------------------------------------------
@ The intro colours
@ ---------------------------------------------------------------------------
@ The letter colours, which the intro fades between.
@ Each entry is a word, not a pair of halfwords. The word holds one colour with its
@ components spread out, so that a blend cannot carry from one component into the
@ next: red in bits 0-4, green in bits 10-14, blue in bits 20-24.
@ intro_fade_colors(set, t, entry) blends set into set + 1 by t/32, and writes
@ three OBJ palette entries:
@   entry + 2  from the third colour of the set
@   entry + 1  from the second colour
@   entry      from the first colour
@ With entry = 4k + 1, these are the three colours of letter k: the three greys of
@ gameboy_art.png, from light to dark.
@
@ The first word is not a colour: intro_fade_colors starts at word 1. Its address
@ is also the lower bound of copy_bios_data (see the file header). Then come eight
@ sets of three. Each set is a colour and two paler ones:
@   0 magenta, 1 blue, 2 cyan, 3 green, 4 yellow, 5 red, 6 magenta, 7 white.
@ As each letter flies in, boot_intro (intro.s) fades it through the sets from
@ white back to blue (sets 7, 6 to 1). Then it pulses the letter between blue and
@ magenta (sets 1 and 0).
	.balign 4
intro_colors:
	.4byte 0xFFFFFFFF	@ not a colour
	.4byte 0x01F0001F, 0x01F0281F, 0x01F0581F	@ 0: magenta  (R31 B31; G 0, 10, 22)
	.4byte 0x01F00000, 0x01F0280A, 0x01F05816	@ 1: blue     (B31;     R and G 0, 10, 22)
	.4byte 0x01F07C00, 0x01F07C0A, 0x01F07C16	@ 2: cyan     (G31 B31; R 0, 10, 22)
	.4byte 0x00007C00, 0x00A07C0A, 0x01607C16	@ 3: green    (G31;     R and B 0, 10, 22)
	.4byte 0x00007C1F, 0x00A07C1F, 0x01607C1F	@ 4: yellow   (R31 G31; B 0, 10, 22)
	.4byte 0x0000001F, 0x00A0281F, 0x0160581F	@ 5: red      (R31;     G and B 0, 10, 22)
	.4byte 0x01F0001F, 0x01F0281F, 0x01F0581F	@ 6: magenta
	.4byte 0x01F07C1F, 0x01F07C1F, 0x01F07C1F	@ 7: white
	
@ Four colours (BGR555) that load_intro_palette copies to palette entries 28-31,
@ first of the BG palette, then of the OBJ palette.
@ Entries 29-31 are the three colours of the ball (cell 7 of gameboy_art:
@ 4 x 7 + 1 to 3). Entry 31 is also the colour of the Nintendo logo (logo_unpack).
@ Neither the ball nor the logo uses entry 28. Entries 29 and 30 have bit 15 set,
@ which the hardware ignores.
	.balign 4
intro_palette:
@ blue, pale magenta, lighter magenta, magenta
	.2byte 0x7C00, 0xFF1F, 0xFD5F, 0x7C1F	

@ ---------------------------------------------------------------------------
@ The assets (assets/, from lift.py; the art from convert.py)
@ ---------------------------------------------------------------------------
@ The Huffman header (4-bit, 212 bytes out) and tree for the cartridge logo.
@ decode_cart_logo puts these 36 bytes in front of the 156 logo bytes of the
@ cartridge header (the bitstream), and decodes them together.
	.balign 4
logo_tree:
	.incbin "assets/logo_tree.bin"
@ The data that check_cart_header compares with cartridge header bytes 0x04-0x9F.
@ The compare is byte for byte (0x9C and 0x9E masked). This data is only compared:
@ the logo on the screen comes from the cartridge.
	.balign 4
logo_reference:
	.incbin "assets/logo_reference.bin"
@ G A M E B O Y and the ball: eight 32x32 sprites, 2bpp, 2 KiB.
@ Compressed with LZ77, then with Huffman (4-bit). load_gameboy_art copies it to
@ IWRAM. intro_load_graphics decompresses both layers, and unpacks each letter
@ into OBJ VRAM with intro_letter_unpack. png/gameboy_art.png is this art.
	.balign 4
gameboy_art:
	.incbin "assets/gameboy_art.huff"
gameboy_art_end:
	@ load_gameboy_art copies it to 0x03000564, and the Huffman decode writes to
	@ 0x03001564. Thus it must fit in the 4 KiB between the two addresses.
	.if gameboy_art_end - gameboy_art > 0x1000
	.error "assets/gameboy_art.huff is over 4 KiB: it would run into what it decodes to"
	.endif
@ The ten intro sprites, as load_intro_oam copies them to OAM: attributes 0, 1
@ and 2 of each, and the fourth halfword (the OAM affine parameter slot).
@ The first four of these halfwords are affine group 0, which does not change:
@ PA 1.0, PB 0.25, PC 0, PD 0 (the slant of the ball streak, sprite 9).
@ Groups 1-7 (the letters) are rewritten every frame.
@   0-6  the letters, right to left: Y O B E M A G at X = 173, 150, 127, 104,
@        80, 57, 34; Y = 32. 64x64, 256 colours, semi-transparent, priority
@        2, affine parameters 1-7. They start hidden (attribute 0 bit 9
@        without bit 8). The intro shows them and moves them.
@   7, 8 the Nintendo logo, two 64x32 halves at X = 55 and 119, Y = 102,
@        tiles 0x340 and 0x350 (where place_cart_logo puts it).
@   9    the ball as a streak across the Nintendo logo: 32x32, 256 colours,
@        affine group 0 when shown (from frame 109). Hidden before then and
@        after Select+Start. The ball is also BG3: the shine that crosses the
@        letters (frames 109-179, see intro.s).
@ The OAM entry of each letter, and thus the order of the letter animations,
@ is fixed here and in boot_intro.
	.balign 4
intro_oam:
	.2byte 0x2620, 0xC2AD, 0x0A40, 0x0100	@ 0 Y  X 173, tiles 0x240
	.2byte 0x2620, 0xC496, 0x098C, 0x0040	@ 1 O  X 150, tiles 0x18C
	.2byte 0x2620, 0xC67F, 0x0980, 0x0000	@ 2 B  X 127, tiles 0x180
	.2byte 0x2620, 0xC868, 0x08CC, 0x0000	@ 3 E  X 104, tiles 0x0CC
	.2byte 0x2620, 0xCA50, 0x08C0, 0x0000	@ 4 M  X  80, tiles 0x0C0
	.2byte 0x2620, 0xCC39, 0x080C, 0x0000	@ 5 A  X  57, tiles 0x00C
	.2byte 0x2620, 0xCE22, 0x0800, 0x0000	@ 6 G  X  34, tiles 0x000
	.2byte 0x6466, 0xC037, 0x5B40, 0x0000	@ 7 left half of the logo
	.2byte 0x6466, 0xC077, 0x5B50, 0x0000	@ 8 right half of the logo
	.2byte 0x2268, 0x8174, 0x0290, 0x0000	@ 9 the ball, tiles 0x290
@ A small bounce after each letter lands.
@ boot_intro adds one of these values to the Y of the letter each frame, for
@ 35 frames. They sum to 0, so the letter stops where it landed.
	.balign 4
intro_bounce:
	.byte 0xFE, 0xFE, 0xFE, 0xFF, 0xFF, 0xFF, 0x00, 0xFF, 0x00, 0x00, 0x01, 0x00, 0x01, 0x01, 0x01, 0x02
	.byte 0x02, 0x02, 0xFF, 0xFF, 0x00, 0xFF, 0x00, 0x00, 0x01, 0x00, 0x01, 0x01, 0x00, 0xFF, 0x00, 0x00
	.byte 0x01, 0x00, 0x00, 0x00

@ ---------------------------------------------------------------------------
@ Veneers: Thumb code calls these to reach ARM routines. `bx pc` switches to
@ ARM at the next word, which branches to the routine. The ARM routine returns
@ to the Thumb caller with bx lr.
@ ---------------------------------------------------------------------------
	.thumb
	.balign 4
thumb_Halt:
	bx pc
	.balign 4, 0
	.arm
	.balign 4
thumb_Halt_arm:
	b Halt
	.thumb
	.balign 4
thumb_enter_cgb_mode:
	bx pc
	.balign 4, 0
	.arm
	.balign 4
thumb_enter_cgb_mode_arm:
	b enter_cgb_mode
	.thumb
	.balign 4
thumb_DivArm:
	bx pc
	.balign 4, 0
	.arm
	.balign 4
thumb_DivArm_arm:
	b DivArm
	.thumb
	.balign 4
thumb_VBlankIntrWait:
	bx pc
	.balign 4, 0
	.arm
	.balign 4
thumb_VBlankIntrWait_arm:
	b VBlankIntrWait
	.thumb
	.balign 4
thumb_ObjAffineSet:
	bx pc
	.balign 4, 0
	.arm
	.balign 4
thumb_ObjAffineSet_arm:
	b ObjAffineSet

@ ---------------------------------------------------------------------------
@ The sound driver data. sound_read_byte reads only from this address up.
@ ---------------------------------------------------------------------------
@ The MP2000 jump table: the handler for each track command from 0xB1 (FINE)
@ to 0xCE (EOT), then six routines of the driver. SoundGetJumpList (SWI 0x2A)
@ copies all 36 entries to a game, which can then replace any of them.
@ Commands that have no handler of their own go to ply_fine.
	.balign 4
sound_jump_table:
	.4byte ply_fine       + 1	@ 0xB1 FINE
	.4byte ply_goto       + 1	@ 0xB2 GOTO
	.4byte ply_patt       + 1	@ 0xB3 PATT
	.4byte ply_pend       + 1	@ 0xB4 PEND
	.4byte ply_rept       + 1	@ 0xB5 REPT
	.4byte ply_fine       + 1	@ 0xB6
	.4byte ply_fine       + 1	@ 0xB7
	.4byte ply_fine       + 1	@ 0xB8
	.4byte ply_fine       + 1	@ 0xB9 MEMACC in later drivers
	.4byte ply_prio       + 1	@ 0xBA PRIO
	.4byte ply_tempo      + 1	@ 0xBB TEMPO
	.4byte ply_keysh      + 1	@ 0xBC KEYSH
	.4byte ply_voice      + 1	@ 0xBD VOICE
	.4byte ply_vol        + 1	@ 0xBE VOL
	.4byte ply_pan        + 1	@ 0xBF PAN
	.4byte ply_bend       + 1	@ 0xC0 BEND
	.4byte ply_bendr      + 1	@ 0xC1 BENDR
	.4byte ply_lfos       + 1	@ 0xC2 LFOS
	.4byte ply_lfodl      + 1	@ 0xC3 LFODL
	.4byte ply_mod        + 1	@ 0xC4 MOD
	.4byte ply_modt       + 1	@ 0xC5 MODT
	.4byte ply_fine       + 1	@ 0xC6
	.4byte ply_fine       + 1	@ 0xC7
	.4byte ply_tune       + 1	@ 0xC8 TUNE
	.4byte ply_fine       + 1	@ 0xC9
	.4byte ply_fine       + 1	@ 0xCA
	.4byte ply_fine       + 1	@ 0xCB
	.4byte ply_port       + 1	@ 0xCC PORT
	.4byte ply_fine       + 1	@ 0xCD XCMD in later drivers
	.4byte ply_endtie     + 1	@ 0xCE EOT
	.4byte SampleFreqSet  + 1	@ 30
	.4byte TrackStop      + 1	@ 31
	.4byte FadeOutBody    + 1	@ 32
	.4byte TrkVolPitSet   + 1	@ 33
	.4byte RealClearChain + 1	@ 34
	.4byte SoundMainBTM   + 1	@ 35: the end of SoundDriverMain
@ The voice group of all songs in this file (MP2000 ToneData, 12 bytes each).
@ Type 0 is a DirectSound sample. Key 60 (C4) is the key at which the sample
@ plays at its own rate. Attack, decay, sustain and release are the envelope.
@   0 wave_sine   1 wave_39D0   2 wave_sine, with a different envelope
	.balign 4
intro_voices:
	.byte 0x00, 0x3C, 0x00, 0x00	@ type, key, length, pan/sweep
	.4byte wave_sine
	.byte 0xFF, 0x00, 0x4D, 0xBC	@ attack, decay, sustain, release
	.byte 0x00, 0x3C, 0x00, 0x00	@ type, key, length, pan/sweep
	.4byte wave_39D0
	.byte 0xFF, 0xA5, 0x9A, 0xF9	@ attack, decay, sustain, release
	.byte 0x00, 0x3C, 0x00, 0x00	@ type, key, length, pan/sweep
	.4byte wave_sine
	.byte 0xFF, 0xA5, 0x80, 0xF6	@ attack, decay, sustain, release
@ Note 3 of 3: G6 at tick 15. Also sets the tempo for the whole song.
song_wait_button_track1:
	.byte 0xBC, 0x00	      @ KEYSH 0: transpose by 0 semitones
	.byte 0xBB, 0x5F	      @ TEMPO 95: 190 beats per minute
	.byte 0xBD, 0x00	      @ VOICE 0: intro_voices entry 0
	.byte 0xBE, 0x4B	      @ VOL 75 (of 127)
	.byte 0xBF, 0x40	      @ PAN 64 (64 is the centre)
	.byte 0x8F	            @ wait 15 ticks
	.byte 0xD5, 0x5B, 0x70	@ note G6 (key 91), velocity 112, 6 ticks long
	.byte 0x86	            @ wait 6 ticks
	.byte 0xB1	            @ FINE: the end of the track
@ Note 2 of 3: D6 at tick 10.
song_wait_button_track2:
	.byte 0xBC, 0x00	      @ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x00	      @ VOICE 0: intro_voices entry 0
	.byte 0xBE, 0x4B	      @ VOL 75 (of 127)
	.byte 0xBF, 0x40	      @ PAN 64 (64 is the centre)
	.byte 0x8A	            @ wait 10 ticks
	.byte 0xD5, 0x56, 0x70	@ note D6 (key 86), velocity 112, 6 ticks long
	.byte 0x86	            @ wait 6 ticks
	.byte 0xB1	            @ FINE: the end of the track
@ Note 1 of 3: B5 at tick 5.
song_wait_button_track3:
	.byte 0xBC, 0x00	      @ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x00	      @ VOICE 0: intro_voices entry 0
	.byte 0xBE, 0x4B	      @ VOL 75 (of 127)
	.byte 0xBF, 0x40	      @ PAN 64 (64 is the centre)
	.byte 0x85	            @ wait 5 ticks
	.byte 0xD5, 0x53, 0x70	@ note B5 (key 83), velocity 112, 6 ticks long
	.byte 0x86	            @ wait 6 ticks
	.byte 0xB1	            @ FINE: the end of the track
@ MP2000 songs: a header, then a pointer to each track. The header holds the
@ number of tracks, a block count (0), the priority, the reverb (bit 7 on, bits
@ 0-6 the amount) and the voice group.
@ Each track is a list of commands. The commands in this file set the tempo,
@ the voice, the volume and the pan, wait, play a note, and end the track.
@ A beat is 24 ticks.

@ A, B or the d-pad after Select+Start (with a good header): the BIOS stops the
@ wait for MultiBoot and starts the cartridge. With a bad header, the buttons do
@ nothing. Three notes.
	.balign 4
@ B5, D6 and G6, 5 ticks apart: a rising G major arpeggio on voice 0
@ (wave_sine). Each track is one note. Track 1 plays last.
song_wait_button:
	.byte 3, 0, 0, 0xBC	@ tracks, blocks, priority, reverb
	.4byte intro_voices	@ voices
	.4byte song_wait_button_track1
	.4byte song_wait_button_track2
	.4byte song_wait_button_track3
	.balign 4
@ An MP2000 wave (assets/wave_sine.bin): a sine.
@ A 16-byte header: type 0, status 0x4000 (loops), frequency 8565909 (8365 Hz,
@ x 1024), loop start 1, 33 samples. Then 33 signed 8-bit samples of a sine, and
@ one more sample for the loop repeat.
wave_sine:
	.incbin "assets/wave_sine.bin"
	.byte 0x00, 0x00	@ padding
@ Note 4 of 4: D6 at tick 15. Also sets the tempo for the whole song.
song_hold_select_start_track1:
	.byte 0xBC, 0x00	      @ KEYSH 0: transpose by 0 semitones
	.byte 0xBB, 0x54	      @ TEMPO 84: 168 beats per minute
	.byte 0xBD, 0x00	      @ VOICE 0: intro_voices entry 0
	.byte 0xBE, 0x55	      @ VOL 85 (of 127)
	.byte 0xBF, 0x40	      @ PAN 64 (64 is the centre)
	.byte 0x8F	            @ wait 15 ticks
	.byte 0xD5, 0x56, 0x70	@ note D6 (key 86), velocity 112, 6 ticks long
	.byte 0x86	            @ wait 6 ticks
	.byte 0xB1	            @ FINE: the end of the track
@ Note 3 of 4: G6 at tick 10.
song_hold_select_start_track2:
	.byte 0xBC, 0x00	      @ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x00	      @ VOICE 0: intro_voices entry 0
	.byte 0xBE, 0x55	      @ VOL 85 (of 127)
	.byte 0xBF, 0x40	      @ PAN 64 (64 is the centre)
	.byte 0x8A	            @ wait 10 ticks
	.byte 0xD5, 0x5B, 0x70	@ note G6 (key 91), velocity 112, 6 ticks long
	.byte 0x86	            @ wait 6 ticks
	.byte 0xB1	            @ FINE: the end of the track
@ Note 2 of 4: D6 at tick 5.
song_hold_select_start_track3:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x00	@ VOICE 0: intro_voices entry 0
	.byte 0xBE, 0x55	@ VOL 85 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0x85	@ wait 5 ticks
	.byte 0xD5, 0x56, 0x70	@ note D6 (key 86), velocity 112, 6 ticks long
	.byte 0x86	@ wait 6 ticks
	.byte 0xB1	@ FINE: the end of the track
@ Note 1 of 4: G6 at tick 0.
song_hold_select_start_track4:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x00	@ VOICE 0: intro_voices entry 0
	.byte 0xBE, 0x55	@ VOL 85 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0xD5, 0x5B, 0x70	@ note G6 (key 91), velocity 112, 6 ticks long
	.byte 0x86	@ wait 6 ticks
	.byte 0xB1	@ FINE: the end of the track
	.byte 0x00, 0x00, 0x00	@ padding
	.balign 4
@ Select+Start held in frames 65-143, with header byte 0xB2 = 0x96. Four notes.
@ Only Select and Start: the low byte of KEYINPUT is exactly 0xF3. The BIOS then
@ waits for MultiBoot instead of starting the cartridge.
@ G6, D6, G6, D6, 5 ticks apart, on voice 0 (wave_sine). Each track is
@ one note. Track 1 plays last.
song_hold_select_start:
	.byte 4, 0, 0, 0xB7	@ tracks, blocks, priority, reverb
	.4byte intro_voices	@ voices
	.4byte song_hold_select_start_track1
	.4byte song_hold_select_start_track2
	.4byte song_hold_select_start_track3
	.4byte song_hold_select_start_track4
@ Note 1 of 6: F4 at tick 0, with C5. Also sets the tempo for the whole song.
song_intro_track1:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBB, 0x4A	@ TEMPO 74: 148 beats per minute
	.byte 0xBD, 0x01	@ VOICE 1: intro_voices entry 1
	.byte 0xBE, 0x78	@ VOL 120 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0xE7, 0x41, 0x60	@ note F4 (key 65), velocity 96, 24 ticks long
	.byte 0x98	@ wait 24 ticks
	.byte 0xB1	@ FINE: the end of the track
@ Note 2 of 6: C5 at tick 0, with F4.
song_intro_track2:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x01	@ VOICE 1: intro_voices entry 1
	.byte 0xBE, 0x78	@ VOL 120 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0xE7, 0x48, 0x70	@ note C5 (key 72), velocity 112, 24 ticks long
	.byte 0x98	@ wait 24 ticks
	.byte 0xB1	@ FINE: the end of the track
@ Note 3 of 6: E5 at tick 2.
song_intro_track3:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x01	@ VOICE 1: intro_voices entry 1
	.byte 0xBE, 0x78	@ VOL 120 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0x82	@ wait 2 ticks
	.byte 0xE7, 0x4C, 0x6C	@ note E5 (key 76), velocity 108, 24 ticks long
	.byte 0x98	@ wait 24 ticks
	.byte 0xB1	@ FINE: the end of the track
@ Note 4 of 6: G5 at tick 4.
song_intro_track4:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x01	@ VOICE 1: intro_voices entry 1
	.byte 0xBE, 0x78	@ VOL 120 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0x84	@ wait 4 ticks
	.byte 0xE7, 0x4F, 0x6C	@ note G5 (key 79), velocity 108, 24 ticks long
	.byte 0x98	@ wait 24 ticks
	.byte 0xB1	@ FINE: the end of the track
@ Note 5 of 6: B5 at tick 6.
song_intro_track5:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x01	@ VOICE 1: intro_voices entry 1
	.byte 0xBE, 0x78	@ VOL 120 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0x86	@ wait 6 ticks
	.byte 0xE7, 0x53, 0x6C	@ note B5 (key 83), velocity 108, 24 ticks long
	.byte 0x98	@ wait 24 ticks
	.byte 0xB1	@ FINE: the end of the track
@ Note 6 of 6: D6 at tick 10.
song_intro_track6:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x01	@ VOICE 1: intro_voices entry 1
	.byte 0xBE, 0x78	@ VOL 120 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0x8A	@ wait 10 ticks
	.byte 0xE7, 0x56, 0x60	@ note D6 (key 86), velocity 96, 24 ticks long
	.byte 0x98	@ wait 24 ticks
	.byte 0xB1	@ FINE: the end of the track
	.balign 4
@ Frame 16 of the intro, as the letters come in. Six notes.
@ F4 and C5 together, then E5, G5, B5 and D6 at ticks 2, 4, 6 and 10: a
@ rolled chord on voice 1 (wave_39D0), every note 24 ticks long. Each track
@ is one note.
song_intro:
	.byte 6, 0, 0, 0xD0	@ tracks, blocks, priority, reverb
	.4byte intro_voices	@ voices
	.4byte song_intro_track1
	.4byte song_intro_track2
	.4byte song_intro_track3
	.4byte song_intro_track4
	.4byte song_intro_track5
	.4byte song_intro_track6
@ Note 4 of 6: E7 at tick 15. Also sets the tempo for the whole song.
song_multiboot_track1:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBB, 0x63	@ TEMPO 99: 198 beats per minute
	.byte 0xBD, 0x00	@ VOICE 0: intro_voices entry 0
	.byte 0xBE, 0x5E	@ VOL 94 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0x8F	@ wait 15 ticks
	.byte 0xD5, 0x64, 0x78	@ note E7 (key 100), velocity 120, 6 ticks long
	.byte 0x86	@ wait 6 ticks
	.byte 0xB1	@ FINE: the end of the track
@ Note 3 of 6: D7 at tick 10.
song_multiboot_track2:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x00	@ VOICE 0: intro_voices entry 0
	.byte 0xBE, 0x5E	@ VOL 94 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0x8A	@ wait 10 ticks
	.byte 0xD5, 0x62, 0x78	@ note D7 (key 98), velocity 120, 6 ticks long
	.byte 0x86	@ wait 6 ticks
	.byte 0xB1	@ FINE: the end of the track
@ Note 2 of 6: C7 at tick 5.
song_multiboot_track3:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x00	@ VOICE 0: intro_voices entry 0
	.byte 0xBE, 0x5E	@ VOL 94 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0x85	@ wait 5 ticks
	.byte 0xD5, 0x60, 0x78	@ note C7 (key 96), velocity 120, 6 ticks long
	.byte 0x86	@ wait 6 ticks
	.byte 0xB1	@ FINE: the end of the track
@ Note 1 of 6: B6 at tick 0, softer than the rest (velocity 80).
song_multiboot_track4:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x00	@ VOICE 0: intro_voices entry 0
	.byte 0xBE, 0x5E	@ VOL 94 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0xD5, 0x5F, 0x50	@ note B6 (key 95), velocity 80, 6 ticks long
	.byte 0x86	@ wait 6 ticks
	.byte 0xB1	@ FINE: the end of the track
@ Note 5 of 6: F#7 at tick 20.
song_multiboot_track5:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x00	@ VOICE 0: intro_voices entry 0
	.byte 0xBE, 0x5E	@ VOL 94 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0x94	@ wait 20 ticks
	.byte 0xD5, 0x66, 0x78	@ note F#7 (key 102), velocity 120, 6 ticks long
	.byte 0x86	@ wait 6 ticks
	.byte 0xB1	@ FINE: the end of the track
@ Note 6 of 6: G7 at tick 25, held twice as long as the rest.
song_multiboot_track6:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x00	@ VOICE 0: intro_voices entry 0
	.byte 0xBE, 0x5E	@ VOL 94 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0x98	@ wait 24 ticks
	.byte 0x81	@ wait 1 tick
	.byte 0xDB, 0x67, 0x78	@ note G7 (key 103), velocity 120, 12 ticks long
	.byte 0x8C	@ wait 12 ticks
	.byte 0xB1	@ FINE: the end of the track
	.byte 0x00, 0x00	@ padding
	.balign 4
@ During a MultiBoot transfer, when a counter reaches 57. Six notes.
@ B6, C7, D7, E7, F#7 and G7, 5 ticks apart: a rising scale to G on voice 0
@ (wave_sine). The first note is softer, and the last is twice as long. Each
@ track is one note, in the order 4, 3, 2, 1, 5, 6.
song_multiboot:
	.byte 6, 0, 0, 0xB2	@ tracks, blocks, priority, reverb
	.4byte intro_voices	@ voices
	.4byte song_multiboot_track1
	.4byte song_multiboot_track2
	.4byte song_multiboot_track3
	.4byte song_multiboot_track4
	.4byte song_multiboot_track5
	.4byte song_multiboot_track6
@ Note 2 of 2: C8 at tick 4. Also sets the tempo for the whole song.
song_intro_end_track1:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBB, 0x4A	@ TEMPO 74: 148 beats per minute
	.byte 0xBD, 0x02	@ VOICE 2: intro_voices entry 2
	.byte 0xBE, 0x55	@ VOL 85 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0x84	@ wait 4 ticks
	.byte 0xD3, 0x6C, 0x78	@ note C8 (key 108), velocity 120, 4 ticks long
	.byte 0x85	@ wait 5 ticks
	.byte 0xB1	@ FINE: the end of the track
@ Note 1 of 2: C7 at tick 0.
song_intro_end_track2:
	.byte 0xBC, 0x00	@ KEYSH 0: transpose by 0 semitones
	.byte 0xBD, 0x02	@ VOICE 2: intro_voices entry 2
	.byte 0xBE, 0x55	@ VOL 85 (of 127)
	.byte 0xBF, 0x40	@ PAN 64 (64 is the centre)
	.byte 0xD3, 0x60, 0x70	@ note C7 (key 96), velocity 112, 4 ticks long
	.byte 0x84	@ wait 4 ticks
	.byte 0xB1	@ FINE: the end of the track
	.byte 0x00, 0x00, 0x00	@ padding
	.balign 4
@ Frame 162 of the intro. Two notes.
@ C7, then C8 4 ticks later: an octave on voice 2 (wave_sine with its own
@ envelope). Each track is one note. Track 1 plays last.
song_intro_end:
	.byte 2, 0, 0, 0xD0	@ tracks, blocks, priority, reverb
	.4byte intro_voices	@ voices
	.4byte song_intro_end_track1
	.4byte song_intro_end_track2
	.balign 4
@ An MP2000 wave (assets/wave_39D0.bin): the sample of voice 1.
@ A 16-byte header: type 0, status 0x4000 (loops), frequency 3102296 (3030 Hz,
@ x 1024), loop start 0, 1312 samples. Then the samples, and one more.
@ This is the last data in the BIOS.
wave_39D0:
	.incbin "assets/wave_39D0.bin"
@ The end of the BIOS. build.py counts the free space from this address.
bios_end:
	.org 0x4000, 0	@ zero fill to 16 KiB; more than 16 KiB does not assemble
