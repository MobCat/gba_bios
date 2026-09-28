@ sound_driver.s 0x1DC4-0x28CD: the sound SWIs, part 2.
@ It holds the mixer (SoundDriverMain, part ARM), SoundDriverVSync, the song player
@ (MPlayMain), notes (ply_note), the channel and track helpers, the command
@ handlers (ply_*), SoundGetJumpList and the BIOS read guard (sound_read_byte).
@ Part 1 is sound.s: the setup, the player SWIs, and the SoundArea, player and
@ song header layouts. Read its header first.
@ At the end are four small MultiBoot functions (mb_crc_word-mb_master_wait).
@ They come before multiboot.s in the address order.
@
@ Sequence per frame:
@   1. VBlank IRQ -> SoundDriverVSync (0x1D). The two sound DMAs read the PCM
@      buffer from the top down, one frame of samples per frame. SoundDriverVSync
@      counts frames in pcmDmaCounter. Every pcmDmaPeriod frames, it turns both
@      DMAs off and on again, so they start again at the top.
@   2. Later in the frame, SoundDriverMain (0x1C):
@      a. SoundArea.MPlayMainHead(SoundArea.musicPlayerHead): MPlayMain for the
@         newest player. It first runs the player opened before it, and so on.
@         Per player: FadeOutBody, then the number of ticks that the tempo gives
@         (tempoI / 150 per frame). Each tick runs every track: the gate times
@         of its notes count down, its commands are read until one waits, and
@         its LFO steps. Then changed volume and pitch go to its channels.
@      b. SoundArea.CgbSound(SoundArea): does nothing in the BIOS.
@      c. The mix. It selects the buffer frame after the frame that the DMA
@         plays (from pcmDmaCounter). It fills that frame with an echo of its
@         old contents (reverb) or with 0. Then, for each of maxChans channels:
@         one step of its envelope, and pcmSamplesPerVBlank samples of its wave,
@         resampled to the output rate. Each sample x the right volume goes
@         into buffer A, and x the left volume into buffer B.
@   3. At the same time, timer 0 overflows once per sample. FIFO A and FIFO B
@      each play one byte. When a FIFO is half empty, its DMA moves the next 16
@      bytes of the buffer into it (GBATEK: in sound FIFO mode, each request is
@      4 words, whatever the count).
@
@ The PCM buffer has two halves of 0x630 bytes. SoundDriverInit routes them:
@   A  SoundArea + 0x350  DMA1, FIFO A, the right side
@   B  SoundArea + 0x980  DMA2, FIFO B, the left side
@ Each half is pcmDmaPeriod frames of pcmSamplesPerVBlank samples. The same
@ position in both halves is the same moment. Samples are signed 8-bit. The
@ mixer adds channels with plain 8-bit adds: a loud total wraps round and is
@ not clipped.
@
@ Songs. MusicPlayerStart points each track at its commands (data.s: the
@ track_XXXX bytes). A tick is 1/24 of a beat (the MP2000 convention). The rule
@ "TEMPO byte x 2 = beats per minute" is inferred from the maths.
@ Where MPlayMain expects a command, it reads:
@   00-7F  a data byte: runs the last command 0xBD or above again (running
@          status), with this byte as its first argument (for example, another
@          note). With no running status yet, the byte is a wait, read from
@          0x80 bytes before sound_clock_table.
@   80-B0  wait: sound_clock_table[n - 0x80] ticks, 0-96 (W00-W96)
@   B1-CE  a handler, sound_jump_table[n - 0xB1](player, track):
@          B1 FINE  end the track         BD VOICE n  select voice n
@          B2 GOTO a  jump                BE VOL n    volume 0-127
@          B3 PATT a  call a pattern      BF PAN n    pan, 0x40 = centre
@          B4 PEND  return from it        C0 BEND n   pitch bend, 0x40 = none
@          B5 REPT n a  repeat            C1 BENDR n  bend range, semitones
@          BA PRIO n  priority            C2 LFOS n   LFO speed
@          BB TEMPO n  n x 2 beats/min    C3 LFODL n  LFO delay, ticks
@          BC KEYSH n  transpose          C4 MOD n    LFO depth
@          C8 TUNE n  fine tune           C5 MODT n   LFO: pitch, volume, pan
@          CC PORT r v  write a register  CE EOT (k)  end a TIE note
@          The other slots (B6-B9, C6, C7, C9-CB, CD) are ply_fine: they end
@          the track. (a = 4 address bytes, little-endian.)
@   CF-FF  a note: SoundArea.plynote = ply_note. CF is TIE (held until EOT).
@          D0-FF last sound_clock_table[n - 0xCF] ticks (N01-N96). Up to three
@          data bytes follow: key, velocity, and ticks to add to the length.
@          A missing byte repeats the value of the last note.
@ The command names are from MP2000. The handlers match its jump table, slot
@ for slot.
@
@ A PCM channel (MP2000 SoundChannel): 0x40 bytes. The SoundArea has 12 at
@ +0x50, and the mixer runs the first maxChans. ply_note fills one per note.
@   0x00 u8  statusFlags  0 = off. 0x80 start, 0x40 stop (released), 0x10
@                         loop, 0x04 echo. Bits 0-1: the envelope phase (3
@                         attack, 2 decay, 1 sustain). On = any bit of 0xC7.
@   0x01 u8  type         the voice type: bits 0-2 a CGB channel 1-4 (0 =
@                         PCM), bit 3 fixed (played without resampling)
@   0x02 u8  rightVolume  velocity x the track volMR / 128
@   0x03 u8  leftVolume   velocity x the track volML / 128
@   0x04 u8  attack       added to the level each frame, up to 255
@   0x05 u8  decay        level x decay / 256 each frame, down to sustain
@   0x06 u8  sustain      the level held
@   0x07 u8  release      level x release / 256 each frame after the stop
@   0x08 u8  key          the key played (for a drum: its own key)
@   0x09 u8  envelopeVolume   the level, 0-255
@   0x0A u8  envelopeVolumeRight  the mixer volumes: rightVolume (leftVolume)
@   0x0B u8  envelopeVolumeLeft     x level x (masterVolume + 1) / 16 / 256
@   0x0C u8  pseudoEchoVolume  after the release, the level is held here
@   0x0D u8  pseudoEchoLength    for this many frames (0: no echo)
@   0x10 u8  gateTime     ticks until the note is released (0: until EOT)
@   0x11 u8  midiKey      the track key for this note; EOT searches for it
@   0x12 u8  velocity
@   0x13 u8  priority     player + track priority: decides which note loses a channel
@   0x18 u32 count        samples left before the end of the wave
@   0x1C u32 fw           the position between two samples, 0 to pcmFreq
@   0x20 u32 frequency    the sample rate of the note, Hz (MidiKey2Freq)
@   0x24 ptr wav          the WaveData
@   0x28 ptr currentPointer  the next sample
@   0x2C ptr track        the track that plays it; 0 if none
@   0x30 ptr prev         the channels of a track are a two-way list that
@   0x34 ptr next           starts at track +0x20, newest first
@ A CGB channel (SoundArea.cgbChans; the BIOS has none) is filled by the same
@ code. It uses the same fields, and also 0x1D (modify: 1 volume, 2 pitch),
@ 0x1E (length) and 0x1F (sweep).
@
@ A track (MP2000 MusicPlayerTrack): 0x50 bytes. MPlayMain clears 0x00-0x3F
@ when the track starts.
@   0x00 u8  flags       0x80 exists, 0x40 start (set up on the next tick).
@                        0x03 volume changed: bit 0 for TrkVolPitSet to
@                        calculate it, bit 1 for MPlayMain to send it to the
@                        channels. 0x0C pitch changed: bits 2 and 3, the same.
@   0x01 u8  wait        ticks to the next command
@   0x02 u8  patternLevel  PATT calls in progress, 0-3
@   0x03 u8  repN        REPT count so far
@   0x04 u8  gateTime    length of the last note, ticks
@   0x05 u8  key         key of the last note
@   0x06 u8  velocity    velocity of the last note
@   0x07 u8  runningStatus  the last command 0xBD or above
@   0x08 s8  keyM        TrkVolPitSet: semitones to add to each key
@   0x09 u8  pitM          and 1/256ths of a semitone (fine adjustment for MidiKey2Freq)
@   0x0A s8  keyShift    KEYSH
@   0x0B s8  keyShiftX   0: for the library of a game
@   0x0C s8  tune        TUNE, -64..63: +-1 semitone
@   0x0D u8  pitX        0: for the library of a game
@   0x0E s8  bend        BEND, -64..63
@   0x0F u8  bendRange   BENDR, semitones (2 at start)
@   0x10 u8  volMR       TrkVolPitSet: right volume
@   0x11 u8  volML         and left volume
@   0x12 u8  vol         VOL, 0-127
@   0x13 u8  volX        fade-out volume, 64 = full (64 at start)
@   0x14 s8  pan         PAN, -64..63
@   0x15 s8  panX        drum pan (ply_note)
@   0x16 s8  modM        LFO output
@   0x17 u8  mod         MOD: depth, 0 = off
@   0x18 u8  modT        MODT: 0 pitch, 1 volume, 2 pan
@   0x19 u8  lfoSpeed    LFOS (22 at start)
@   0x1A u8  lfoSpeedC   LFO phase
@   0x1B u8  lfoDelay    LFODL: ticks from a note to the LFO
@   0x1C u8  lfoDelayC   delay ticks left
@   0x1D u8  priority    PRIO
@   0x1E u8  pseudoEchoVolume  copied to the channel of each note. Nothing in
@   0x1F u8  pseudoEchoLength    the BIOS sets them (0: no echo).
@   0x20 ptr chan        the newest channel of the track
@   0x24     the voice (12 bytes, copied by VOICE): 0x24 type (1 at start),
@            0x25 key, 0x26 length, 0x27 pan_sweep, 0x28 wave (or a voice
@            table), 0x2C-0x2F attack, decay, sustain, release (or a table)
@   0x40 ptr cmdPtr      the next command byte
@   0x44 ptr patternStack[3]  PATT return addresses
@
@ A voice (MP2000 ToneData): 12 bytes, in the voice table of a song (data.s:
@ intro_voices).
@   +0  type       0x80 drum kit, 0x40 key split, 0x08 fixed, bits 0-2 CGB channel
@   +1  key        for a drum, the key it plays
@   +2  length     for CGB
@   +3  pan_sweep  for a drum, 0x80 + pan; for CGB, a sweep
@   +4  wave       for a kit or split: its own voice table
@   +8  attack, decay, sustain, release; for a split: the key-to-voice table
@
@ A wave (MP2000 WaveData; data.s: wave_sine, wave_39D0):
@   +0     type (not read)
@   +3     bits 6-7: loops (GBATEK: status 0x4000, a forward loop)
@   +4     freq (see MidiKey2Freq)
@   +8     loop start
@   +0xC   size (samples)
@   +0x10  the samples, signed 8-bit, and one more sample: the interpolation
@          reads one sample past the current sample (GBATEK: 0, or a copy of
@          the first sample of the loop).
@
@ The BIOS read guard: sound_read_byte changes a value read from the BIOS below
@ sound_jump_table to 0. Thus the song data of a game cannot return the BIOS
@ code to the game. Only some reads go through it (see sound_read_byte). GBATEK:
@ the read in MidiKey2Freq does not, and dumps the BIOS.
@ Because of the guard, all data that the songs in the BIOS use must be at
@ sound_jump_table or after it.
@
@ RAM: the SoundArea (through SOUND_AREA_PTR), and the players and tracks it
@   links to.
@ I/O: DMA1CNT_H, DMA2CNT_H (SoundDriverVSync); any byte of 0x04000060-0x0400015F
@   (PORT); SIO registers (the MultiBoot functions).

@ SWI 0x1C
@
@ SoundDriverMain SWI 0x1C: the main routine of the sound driver (GBATEK).
@ Matches MP2000 SoundMain and SoundMainRAM, but is an earlier version: it has
@ no VCOUNT limit (maxLines).
@ GBATEK: call it every 1/60 s. Call SoundDriverVSync directly after the VBlank
@   interrupt, then this SWI after the BG and OBJ work.
@ In:  nothing; the SoundArea through SOUND_AREA_PTR. Does nothing unless its
@      ident is "Smsh". The SoundArea is locked while this runs.
@ Does: runs the players, calls CgbSound, and mixes a frame (see the file header).
@      The per-sample loops are ARM (sound_main_reverb, sound_main_mix). The rest
@      is Thumb (sound_main_channels, sound_main_next_channel).
@ Out: nothing. Keeps r4-r11. The ARM parts run from the BIOS itself (the m4a
@      library of a game copies its SoundMainRAM to IWRAM).
@ Stack, below the saved registers:
@      [sp]       sample count of the frame, while a channel is mixed
@      [sp+4]     channels left
@      [sp+8]     position of the frame in buffer A
@      [sp+0xC]   loop start of the wave
@      [sp+0x10]  loop length (0: no loop)
@      [sp+0x14]  the SoundArea (the pushed r0)
SoundDriverMain:
	.thumb
	ldr r0, driver_sound_area_ptr	@ =SOUND_AREA_PTR
	ldr r0, [r0, #0]	@ r0 = the SoundArea
	ldr r2, driver_smsh	@ =SOUND_IDENT: "Smsh"
	ldr r3, [r0, #0]
	cmp r2, r3
	beq sound_main_lock
	bx lr	@ not set up, or busy: return
sound_main_lock:
	.inst.n 0x1C5B	@ adds r3, r3, #1: lock
	str r3, [r0, #0]
	push {r4, r5, r6, r7, lr}
	mov r1, r8
	mov r2, r9
	mov r3, sl
	mov r4, fp
	push {r0, r1, r2, r3, r4}	@ the SoundArea, then r8-r11
	sub sp, #0x14	@ the locals, [sp] to [sp+0x10]
	ldr r3, [r0, #0x20]	@ MPlayMainHead
	cmp r3, #0
	beq sound_main_cgb	@ no player open
	ldr r0, [r0, #0x24]	@ musicPlayerHead
	bl call_r3	@ MPlayMain(musicPlayerHead): the songs
	ldr r0, [sp, #0x14]
sound_main_cgb:
	ldr r3, [r0, #0x28]
	bl call_r3	@ CgbSound(SoundArea): DummyFunc in the BIOS, does nothing
	ldr r0, [sp, #0x14]
	ldr r3, [r0, #0x10]
	mov r8, r3	@ r8 = pcmSamplesPerVBlank
	ldr r5, main_pcm_offset	@ =0x00000350: offset of buffer A
	adds r5, r5, r0	@ r5 = buffer A
	ldrb r4, [r0, #4]	@ r4 = pcmDmaCounter
	subs r7, r4, #1
	bls sound_main_frame	@ 0 or 1 (DMA on the last frame, or off): mix frame 0
	ldrb r1, [r0, #0xB]
	subs r1, r1, r7	@ else frame pcmDmaPeriod - counter + 1: the frame
	mov r2, r8	@ after the frame that the DMA plays
	muls r2, r1
	adds r5, r5, r2	@ r5 = that frame in buffer A
sound_main_frame:
	str r5, [sp, #8]
	ldr r6, main_pcm_half_size	@ =0x00000630: offset from buffer A to buffer B
	ldrb r3, [r0, #5]	@ r3 = reverb
	cmp r3, #0
	beq sound_main_clear	@ no reverb: clear the frame
	adr r1, sound_main_reverb
	bx r1	@ to ARM: the reverb
	.arm
	.balign 4
@ sound_main_reverb: starts the frame with reverb (SoundDriverMain, ARM).
@ For each sample of the frame: (A + B of this frame + A + B of the next frame)
@ x reverb / 512, stored to both A and B. This is an echo, the same on both
@ sides. The two frames hold what was mixed into them on the last pass through
@ the buffer, about pcmDmaPeriod frames ago.
@ A result with bit 7 set (negative) gets +1: it rounds toward 0, probably so
@ that an echo dies away and does not stay at -1. SoundMainRAM in MP2000 does
@ the same.
@ In:  r0 SoundArea, r3 reverb, r4 pcmDmaCounter, r5 the frame, r6 0x630,
@      r8 samples per frame. Continues to sound_main_channels (Thumb).
@      Clobbers r0, r1, r4, r5, r7.
sound_main_reverb:
	cmp r4, #2
	addeq r7, r0, #0x350	@ counter 2: this is the last frame; the next is frame 0
	addne r7, r5, r8	@ else the next frame follows this one
	mov r4, r8	@ r4 = samples left
	.balign 4
sound_main_reverb_loop:
	ldrsb r0, [r5, r6]	@ B, this frame
	ldrsb r1, [r5]	@ + A
	add r0, r0, r1
	ldrsb r1, [r7, r6]	@ + B, the next frame
	add r0, r0, r1
	ldrsb r1, [r7], #1	@ + A, the next frame
	add r0, r0, r1
	mul r1, r0, r3
	asr r0, r1, #9	@ x reverb / 512
	tst r0, #0x80
	addne r0, r0, #1	@ negative: round toward 0
	strb r0, [r5, r6]	@ to B
	strb r0, [r5], #1	@ and to A
	subs r4, r4, #1
	bgt sound_main_reverb_loop
	adr r0, sound_main_channels + 1
	bx r0	@ back to Thumb: the channels
sound_main_clear:	@ no reverb: clear the frame in both halves
	.thumb
	movs r0, #0
	mov r1, r8
	adds r6, r6, r5	@ r6 = the frame in buffer B
	lsrs r1, r1, #3	@ carry = bit 2 of the count: 4 more samples
	bcc sound_main_clear_8
	stmia r5!, {r0}
	stmia r6!, {r0}
sound_main_clear_8:
	lsrs r1, r1, #1	@ carry = bit 3: 8 more samples
	bcc sound_main_clear_loop
	stmia r5!, {r0}
	stmia r6!, {r0}
	stmia r5!, {r0}
	stmia r6!, {r0}
sound_main_clear_loop:	@ then 16 per loop, count / 16 times (all counts in
	stmia r5!, {r0}	@ sound_pcm_samples_per_vblank are multiples
	stmia r6!, {r0}	@ of 4 and at least 96; the code relies on it)
	stmia r5!, {r0}
	stmia r6!, {r0}
	stmia r5!, {r0}
	stmia r6!, {r0}
	stmia r5!, {r0}
	stmia r6!, {r0}
	.inst.n 0x1E49	@ subs r1, r1, #1
	bgt sound_main_clear_loop
@ sound_main_channels: the channel loop (SoundDriverMain, Thumb). Both ways of
@ starting the frame continue here. It is the channel part of SoundMainRAM in
@ MP2000. For each of maxChans channels (SoundArea + 0x50, 0x40 apart):
@   - off: skip it.
@   - starting: set it up from its wave.
@   - do one step of its envelope (one step per frame).
@   - calculate its left and right volume.
@   - mix it with sound_main_mix (ARM).
@ The envelope (statusFlags bits 0-1; the level is at +0x09):
@   start    level 0, the attack phase, at the first sample of the wave. (Start
@            and stop set together: off.)
@   attack   level + attack, until 255: then decay
@   decay    level x decay / 256, until at or below sustain: then sustain
@            (sustain 0: as at the end of the release)
@   sustain  level unchanged
@   release  (stop flag 0x40) level x release / 256, until at or below
@            pseudoEchoVolume. Then the level is held there for
@            pseudoEchoLength frames (echo flag 0x04). If pseudoEchoVolume is
@            0: off at once.
@ The volume: v = level x (masterVolume + 1) / 16. The mixer right volume
@ (+0x0A) = rightVolume x v / 256, left (+0x0B) = leftVolume x v / 256.
sound_main_channels:
	ldr r4, [sp, #0x14]	@ the SoundArea
	ldr r0, [r4, #0x14]
	mov r9, r0	@ r9 = pcmFreq
	ldr r0, [r4, #0x18]
	mov ip, r0	@ ip = divFreq
	ldrb r0, [r4, #6]	@ r0 = maxChans
	adds r4, #0x50	@ r4 = channel 0
sound_main_channel_loop:
	str r0, [sp, #4]	@ channels left, including this one
	ldr r3, [r4, #0x24]	@ r3 = its wave
	ldrb r6, [r4, #0]	@ r6 = statusFlags
	movs r0, #0xC7
	tst r0, r6
	bne sound_main_channel_on
	b sound_main_next_channel	@ off: next channel
sound_main_channel_on:
	movs r0, #0x80
	tst r0, r6
	beq sound_main_envelope	@ not starting
	movs r0, #0x40
	tst r0, r6
	bne sound_main_channel_off	@ start and stop together: off
	movs r6, #3
	strb r6, [r4, #0]	@ attack phase; start flag cleared
	adds r0, r3, #0
	adds r0, #0x10
	str r0, [r4, #0x28]	@ position = first sample of the wave
	ldr r0, [r3, #0xC]
	str r0, [r4, #0x18]	@ count = size of the wave
	movs r5, #0
	strb r5, [r4, #9]	@ level 0
	str r5, [r4, #0x1C]	@ fw 0
	ldrb r2, [r3, #3]	@ wave status, high byte
	movs r0, #0xC0
	tst r0, r2
	beq sound_main_attack
	movs r0, #0x10
	orrs r6, r0
	strb r6, [r4, #0]	@ it loops: set the loop flag
	b sound_main_attack	@ the first attack step
sound_main_envelope:
	ldrb r5, [r4, #9]	@ r5 = level
	movs r0, #4
	tst r0, r6
	beq sound_main_release
	ldrb r0, [r4, #0xD]	@ echo: length - 1
	.inst.n 0x1E40	@ subs r0, r0, #1
	strb r0, [r4, #0xD]
	bhi sound_main_set_volume	@ frames left: level unchanged
sound_main_channel_off:
	movs r0, #0
	strb r0, [r4, #0]	@ off
	b sound_main_next_channel
sound_main_release:
	movs r0, #0x40
	tst r0, r6
	beq sound_main_decay
	ldrb r0, [r4, #7]	@ released: level x release / 256
	muls r5, r0
	lsrs r5, r5, #8
	ldrb r0, [r4, #0xC]
	cmp r5, r0
	bhi sound_main_set_volume	@ still above the echo level
sound_main_echo_start:
	ldrb r5, [r4, #0xC]	@ at or below it: level = echo volume,
	cmp r5, #0
	beq sound_main_channel_off	@ (0: off)
	movs r0, #4
	orrs r6, r0
	strb r6, [r4, #0]	@ and the echo starts
	b sound_main_set_volume
sound_main_decay:
	movs r2, #3
	ands r2, r6	@ the phase
	cmp r2, #2
	bne sound_main_attack_check
	ldrb r0, [r4, #5]	@ decay: level x decay / 256
	muls r5, r0
	lsrs r5, r5, #8
	ldrb r0, [r4, #6]
	cmp r5, r0
	bhi sound_main_set_volume	@ still above sustain
	adds r5, r0, #0	@ level = sustain
	beq sound_main_echo_start	@ sustain 0: as at the end of the release
	.inst.n 0x1E76	@ subs r6, r6, #1
	strb r6, [r4, #0]	@ phase 1: sustain
	b sound_main_set_volume
sound_main_attack_check:
	cmp r2, #3
	bne sound_main_set_volume	@ sustain: level unchanged
sound_main_attack:
	ldrb r0, [r4, #4]	@ attack: level + attack
	adds r5, r5, r0
	cmp r5, #0xFF
	bcc sound_main_set_volume
	movs r5, #0xFF	@ 255 or more: level 255,
	.inst.n 0x1E76	@ subs r6, r6, #1
	strb r6, [r4, #0]	@ phase 2: decay
sound_main_set_volume:
	strb r5, [r4, #9]	@ new level
	ldr r0, [sp, #0x14]
	ldrb r0, [r0, #7]	@ masterVolume
	.inst.n 0x1C40	@ adds r0, r0, #1
	muls r0, r5
	lsrs r5, r0, #4	@ r5 = level x (masterVolume + 1) / 16
	ldrb r0, [r4, #2]
	muls r0, r5
	lsrs r0, r0, #8
	strb r0, [r4, #0xA]	@ right = rightVolume x r5 / 256
	ldrb r0, [r4, #3]
	muls r0, r5
	lsrs r0, r0, #8
	strb r0, [r4, #0xB]	@ left = leftVolume x r5 / 256
	movs r0, #0x10
	ands r0, r6
	str r0, [sp, #0x10]	@ loop length: 0 if it does not loop
	beq sound_main_to_mix
	adds r0, r3, #0
	adds r0, #0x10
	ldr r1, [r3, #8]
	adds r0, r0, r1
	str r0, [sp, #0xC]	@ loop start = samples + loop start of the wave
	ldr r0, [r3, #0xC]
	subs r0, r0, r1
	str r0, [sp, #0x10]	@ loop length: size - loop start
sound_main_to_mix:
	ldr r5, [sp, #8]	@ r5 = the frame in buffer A
	ldr r2, [r4, #0x18]	@ r2 = count
	ldr r3, [r4, #0x28]	@ r3 = position
	adr r0, sound_main_mix
	bx r0	@ to ARM: mix the channel
	.balign 4, 0
	.arm
	.balign 4
@ sound_main_mix: adds one channel to the frame (SoundDriverMain, ARM).
@ In:  r2 count (samples left in the wave), r3 position, r4 the channel,
@      r5 the frame in buffer A, r8 samples per frame, r9 pcmFreq, ip divFreq,
@      [sp+0xC] and [sp+0x10] the loop. sl and fp get the right and left volume.
@ For each output sample: s = a sample of the wave, A += s x right / 256,
@ B += s x left / 256 (8-bit, wrapping).
@ A fixed voice (type bit 3) uses one wave sample per output sample. Other
@ voices move through the wave at frequency / pcmFreq samples per output sample:
@   - fw (+0x1C) increases by frequency for each output sample.
@   - Each time fw reaches pcmFreq, the mixer moves past one sample. It moves
@     4 or 2 samples at a time while that is safe, then 1.
@   - s is interpolated between the current sample and the next one:
@     s0 + (s1 - s0) x fw x divFreq / 2^23, that is fw / pcmFreq of the way.
@ At the end of the wave: if the wave loops, back to its loop start. If not, the
@ channel is off (statusFlags = 0) and the rest of the frame stays unchanged.
@ Saves count, position and fw to the channel, then continues to
@ sound_main_next_channel (Thumb). Uses r0, r1, r6, r7, lr; restores r8 from [sp].
sound_main_mix:
	str r8, [sp]	@ save the sample count of the frame
	ldrb sl, [r4, #0xA]	@ sl = right volume
	ldrb fp, [r4, #0xB]	@ fp = left volume
	ldrb r0, [r4, #1]
	tst r0, #8
	beq mix_resample	@ not fixed: resample
	.balign 4
mix_fixed_loop:	@ fixed: one wave sample per output sample
	ldrsb r6, [r3], #1
	mul r1, r6, fp
	ldrb r0, [r5, #0x630]
	add r0, r0, r1, asr #8
	strb r0, [r5, #0x630]	@ B += s x left / 256
	mul r1, r6, sl
	ldrb r0, [r5]
	add r0, r0, r1, asr #8
	strb r0, [r5], #1	@ A += s x right / 256
	subs r2, r2, #1
	bne mix_fixed_next
	ldr r2, [sp, #0x10]	@ the end of the wave:
	cmp r2, #0
	ldrne r3, [sp, #0xC]	@ loops: count = loop length, position = loop start
	bne mix_fixed_next
	strb r2, [r4]	@ no loop: off
	b mix_channel_done
	.balign 4
mix_fixed_next:
	subs r8, r8, #1
	bgt mix_fixed_loop
	b mix_save_position
	.balign 4
mix_resample:	@ resampled:
	ldr r7, [r4, #0x1C]	@ r7 = fw
	ldr lr, [r4, #0x20]	@ lr = frequency (the fw step)
	.balign 4
mix_advance:
	cmp r7, r9, lsl #2
	bcc mix_pass_2
	.balign 4
mix_pass_4:	@ fw at least 4 x pcmFreq: advance 4 samples,
	cmp r2, #4
	ble mix_pass_1	@ unless the wave ends within them
	sub r2, r2, #4
	add r3, r3, #4
	sub r7, r7, r9, lsl #2
	cmp r7, r9, lsl #2
	bcs mix_pass_4
	.balign 4
mix_pass_2:
	cmp r7, r9, lsl #1
	bcc mix_pass_1_check
	cmp r2, #2	@ at least 2 x pcmFreq: advance 2
	ble mix_pass_1
	sub r2, r2, #2
	add r3, r3, #2
	sub r7, r7, r9, lsl #1
	.balign 4
mix_pass_1_check:
	cmp r7, r9
	bcc mix_interpolate	@ below pcmFreq: advance 0
	.balign 4
mix_pass_1:	@ advance 1 sample
	subs r2, r2, #1
	bne mix_pass_1_next
	ldr r2, [sp, #0x10]	@ the end of the wave:
	cmp r2, #0
	ldrne r3, [sp, #0xC]	@ loops: position = loop start
	bne mix_pass_1_fw
	strb r2, [r4]	@ no loop: off
	b mix_channel_done
	.balign 4
mix_pass_1_next:
	add r3, r3, #1
	.balign 4
mix_pass_1_fw:
	sub r7, r7, r9
	cmp r7, r9
	bcs mix_pass_1
	.balign 4
mix_interpolate:	@ an output sample, interpolated:
	ldrsb r0, [r3]	@ s0
	ldrsb r1, [r3, #1]	@ s1: the wave has one extra sample after its end for this
	sub r1, r1, r0
	mul r6, r1, r7
	mul r1, r6, ip
	add r6, r0, r1, asr #0x17	@ s = s0 + (s1 - s0) x fw x divFreq / 2^23
	mul r1, r6, fp
	ldrb r0, [r5, #0x630]
	add r0, r0, r1, asr #8
	strb r0, [r5, #0x630]	@ B += s x left / 256
	mul r1, r6, sl
	ldrb r0, [r5]
	add r0, r0, r1, asr #8
	strb r0, [r5], #1	@ A += s x right / 256
	add r7, r7, lr	@ fw += frequency
	subs r8, r8, #1
	beq mix_save_fw	@ frame complete
	cmp r7, r9
	bcc mix_interpolate	@ still between the same two samples
	b mix_advance
	.balign 4
mix_save_fw:
	str r7, [r4, #0x1C]	@ fw
	.balign 4
mix_save_position:
	str r2, [r4, #0x18]	@ count
	str r3, [r4, #0x28]	@ position
	.balign 4
mix_channel_done:
	ldr r8, [sp]	@ restore the sample count of the frame
	adr r0, sound_main_next_channel + 1
	bx r0	@ back to Thumb
@ sound_main_next_channel: runs after each channel (SoundDriverMain, Thumb).
@ It goes to the next channel (r4 + 0x40) while channels are left ([sp+4]).
@ Then it unlocks the SoundArea, restores r4-r11, and returns to the caller of
@ SoundDriverMain (through call_r3).
sound_main_next_channel:
	.thumb
	ldr r0, [sp, #4]
	.inst.n 0x1E40	@ subs r0, r0, #1
	ble sound_main_exit	@ no channels left
	adds r4, #0x40	@ next channel
	b sound_main_channel_loop
sound_main_exit:
	ldr r0, [sp, #0x14]
	ldr r3, driver_smsh	@ =SOUND_IDENT
	str r3, [r0, #0]	@ unlock the SoundArea
	add sp, #0x18	@ remove the locals and the pushed SoundArea
	pop {r0, r1, r2, r3, r4, r5, r6, r7}	@ r8-r11 (as r0-r3), then r4-r7
	mov r8, r0
	mov r9, r1
	mov sl, r2
	mov fp, r3
	pop {r3}	@ the return address, for the bx r3 below
@ call_r3: bx r3. The driver calls a function pointer with "bl call_r3" and the
@ address in r3. The callee (Thumb or ARM, by bit 0) returns directly to the
@ instruction after the bl. SoundDriverMain also ends here, with its return
@ address in r3. MP2000 does the same.
call_r3:
	bx r3
	.balign 4
main_pcm_offset:
	.4byte 0x00000350	@ offset of PCM buffer A (FIFO A, right) in the SoundArea
main_pcm_half_size:
	.4byte 0x00000630	@ size of each half: buffer B = buffer A + this
@ SWI 0x1D
@
@ SoundDriverVSync SWI 0x1D: resets the sound DMA (GBATEK: a very short call).
@ Probably an earlier form of m4aSoundVSync in MP2000. That function also accepts
@ "Smsh" + 1 and handles the DMA repeat.
@ GBATEK: the timing is critical. Call it directly after the VBlank interrupt,
@   every 1/60 s.
@ Does: nothing unless the SoundArea ident is "Smsh". Thus, if the VBlank IRQ
@      comes while SoundDriverMain (or another locking SWI) runs, this frame is
@      not counted. Else pcmDmaCounter - 1. When that is 0 or less:
@      pcmDmaCounter = pcmDmaPeriod, and DMA1CNT_H and DMA2CNT_H get 0, then
@      0xB600. When a DMA is turned on, it reloads its source. Thus both DMAs
@      start again at the top of their half of the buffer.
@      The DMAs play pcmDmaPeriod frames of the buffer, then go back to its top.
@      This stays in step with the frames, whatever the timer has done.
@ Out: nothing. Clobbers r0-r3. boot_irq (system.s) calls it in the intro.
SoundDriverVSync:
	ldr r0, driver_sound_area_ptr	@ =SOUND_AREA_PTR
	ldr r0, [r0, #0]	@ r0 = the SoundArea
	ldr r2, driver_smsh	@ =SOUND_IDENT
	ldr r3, [r0, #0]
	cmp r2, r3
	bne vsync_return	@ not set up, or busy: do nothing
	ldrb r1, [r0, #4]
	.inst.n 0x1E49	@ subs r1, r1, #1
	strb r1, [r0, #4]	@ pcmDmaCounter - 1
	bgt vsync_return	@ frames left in this pass: return
	ldrb r1, [r0, #0xB]
	strb r1, [r0, #4]	@ pcmDmaCounter = pcmDmaPeriod
	movs r0, #0
	movs r1, #0xB6
	lsls r1, r1, #8	@ 0xB600: on, FIFO timing, 32-bit, repeat
	ldr r2, vsync_dma1cnt_h	@ =REG_DMA1CNT_H: DMA1CNT_H
	ldr r3, vsync_dma2cnt_h	@ =REG_DMA2CNT_H: DMA2CNT_H
	strh r0, [r2, #0]	@ DMA1 off
	strh r0, [r3, #0]	@ DMA2 off
	strh r1, [r2, #0]	@ DMA1 on: restarts at the top of buffer A
	strh r1, [r3, #0]	@ DMA2 on: restarts at the top of buffer B
vsync_return:
	bx lr
	.balign 4
vsync_dma1cnt_h:
	.4byte REG_DMA1CNT_H	@ DMA1CNT_H: DMA1 (buffer A to FIFO A) control
vsync_dma2cnt_h:
	.4byte REG_DMA2CNT_H	@ DMA2CNT_H: DMA2 (buffer B to FIFO B) control
driver_sound_area_ptr:
	.4byte SOUND_AREA_PTR	@ holds the address of the SoundArea (SoundDriverInit)
driver_smsh:
	.4byte SOUND_IDENT	@ "Smsh": the SoundArea ident when idle
@ MPlayMain(player): runs one frame of one player, and of the players opened
@ before it. Matches an earlier version of MPlayMain in MP2000 (no clock count;
@ the channel volume is calculated inline). MusicPlayerOpen puts it in
@ SoundArea.MPlayMainHead and in +0x38 of each later player. SoundDriverMain
@ calls it.
@ In:  r0 = the player. Does nothing unless its ident is "Smsh". The player is
@      locked while this runs.
@ Does: 1. If the player has a next (+0x38, the player opened before it), calls
@          it with +0x3C. Thus all open players run, the oldest first.
@       2. If status bit 31 is set (paused or stopped): returns.
@       3. FadeOutBody.
@       4. tempoC += tempoI. While tempoC is 150 or more: one tick, then
@          tempoC - 150. In a tick, for each track that exists (flags 0x80):
@          - For each of its channels: gate time - 1 (unless 0). At 0, the
@            note is released (flag 0x40). Channels that are off are
@            unlinked (RealClearChain).
@          - If the track starts (0x40): its bytes 0x00-0x3F are cleared, then
@            flags 0x80, bendRange 2, volX 64, lfoSpeed 22, voice type 1.
@          - While its wait is 0: read and run a command (see the file
@            header). A handler that turns the track off ends its tick.
@          - wait - 1. Then the LFO, if lfoSpeed and mod are not 0: after
@            lfoDelayC ticks, lfoSpeedC += lfoSpeed and modM = mod x t / 64.
@            t is a triangle wave of lfoSpeedC, -64..64 over its 256 steps.
@            A new modM marks pitch (modT 0) or volume as changed.
@          Then status = one bit for each track that existed (bit n = track
@          n). If no track exists: status = 0x80000000 (stopped), and return.
@       5. For each track with changes (flags bits 0-3): TrkVolPitSet. Then,
@          for each channel:
@          - volume changed: rightVolume = velocity x volMR / 128,
@            leftVolume = velocity x volML / 128.
@          - pitch changed: frequency = MidiKey2Freq(wave, key + keyM (at
@            least 0), pitM). For a CGB channel: SoundArea.MidiKeyToCgbFreq.
@          Then the flags bits 0-3 of the track are cleared.
@ Out: nothing. Keeps r4-r11.
@ Note: status is written from fp, which is only set for a track that exists.
@ In a tick with no track at all, fp still holds the bits of an earlier tick,
@ or r11 of the caller (read from the code, not run).
MPlayMain:
	ldr r2, mplay_smsh	@ =SOUND_IDENT
	ldr r3, [r0, #0x34]	@ player ident
	cmp r2, r3
	beq mplay_lock
	bx lr	@ not open, or already running: return
mplay_lock:
	.inst.n 0x1C5B	@ adds r3, r3, #1: lock
	str r3, [r0, #0x34]
	push {r4, r5, r6, r7, lr}
	mov r4, r8
	mov r5, r9
	mov r6, sl
	mov r7, fp
	push {r4, r5, r6, r7}
	adds r7, r0, #0	@ r7 = player
	ldr r3, [r7, #0x38]	@ the player opened before this one
	cmp r3, #0
	beq mplay_check_status
	ldr r0, [r7, #0x3C]
	bl call_r3	@ run it first
mplay_check_status:
	ldr r0, [r7, #4]	@ status
	cmp r0, #0
	bge mplay_playing
	b mplay_exit	@ bit 31: paused or stopped
mplay_playing:
	ldr r0, mplay_sound_area_ptr	@ =SOUND_AREA_PTR
	ldr r0, [r0, #0]
	mov r8, r0	@ r8 = the SoundArea
	adds r0, r7, #0
	bl FadeOutBody
	ldrh r0, [r7, #0x22]
	ldrh r1, [r7, #0x20]
	adds r0, r0, r1	@ tempoC + tempoI
	b mplay_tempo_check
mplay_tick:	@ one tick:
	ldrb r2, [r7, #8]	@ r2 = tracks left
	ldr r5, [r7, #0x2C]	@ r5 = track
	movs r3, #1	@ r3 = the status bit of the track
	movs r4, #0	@ r4 = the bits of tracks that exist
mplay_tick_track:
	ldrb r0, [r5, #0]
	movs r1, #0x80
	tst r1, r0
	bne mplay_track_on
	b mplay_next_track	@ does not exist: next track
mplay_track_on:
	mov r9, r2	@ save the loop registers while the track runs
	mov sl, r3
	orrs r4, r3
	mov fp, r4
	ldr r4, [r5, #0x20]	@ its channels:
	cmp r4, #0
	beq mplay_track_start
mplay_gate_loop:
	ldrb r1, [r4, #0]
	movs r0, #0xC7
	tst r0, r1
	beq mplay_unlink_channel	@ off: unlink it
	ldrb r0, [r4, #0x10]	@ gate time
	cmp r0, #0
	beq mplay_gate_next	@ 0: held until an EOT
	.inst.n 0x1E40	@ subs r0, r0, #1
	strb r0, [r4, #0x10]
	bne mplay_gate_next
	movs r0, #0x40
	orrs r1, r0
	strb r1, [r4, #0]	@ gate time ended: released
	b mplay_gate_next
mplay_unlink_channel:
	adds r0, r4, #0
	bl RealClearChain
mplay_gate_next:
	ldr r4, [r4, #0x34]	@ next channel
	cmp r4, #0
	bne mplay_gate_loop
mplay_track_start:
	ldrb r3, [r5, #0]
	movs r0, #0x40
	tst r0, r3
	beq mplay_check_wait	@ not starting
	adds r0, r5, #0
	bl SoundMainBTM	@ starting: clear bytes 0x00-0x3F of the track
	movs r0, #0x80
	strb r0, [r5, #0]	@ flags = exists
	movs r0, #2
	strb r0, [r5, #0xF]	@ bendRange 2
	movs r0, #0x40
	strb r0, [r5, #0x13]	@ volX 64, full
	movs r0, #0x16
	strb r0, [r5, #0x19]	@ lfoSpeed 22
	movs r0, #1
	adds r1, r5, #6
	strb r0, [r1, #0x1E]	@ voice type (+0x24) 1, until a VOICE
	b mplay_check_wait
mplay_read_command:	@ a command:
	ldr r2, [r5, #0x40]
	ldrb r1, [r2, #0]	@ (read without sound_read_byte)
	cmp r1, #0x80
	bcs mplay_command_byte
	ldrb r1, [r5, #7]	@ a data byte: the running status again,
	b mplay_dispatch	@ with this byte as its argument
mplay_command_byte:
	.inst.n 0x1C52	@ adds r2, r2, #1
	str r2, [r5, #0x40]	@ a command: move past it
	cmp r1, #0xBD
	bcc mplay_dispatch
	strb r1, [r5, #7]	@ 0xBD and up: the new running status
mplay_dispatch:
	cmp r1, #0xCF
	bcc mplay_handler_check
	mov r0, r8	@ 0xCF-0xFF, a note:
	ldr r3, [r0, #0x38]	@ plynote (ply_note)
	adds r0, r1, #0
	subs r0, #0xCF	@ r0 = index of the note length
	adds r1, r7, #0	@ r1 = player
	adds r2, r5, #0	@ r2 = track
	bl call_r3
	b mplay_check_wait
mplay_handler_check:
	cmp r1, #0xB0
	bls mplay_wait_command
	adds r0, r1, #0	@ 0xB1-0xCE, a handler:
	subs r0, #0xB1
	strb r0, [r7, #0xA]	@ player.cmd = the slot
	mov r3, r8
	ldr r3, [r3, #0x34]	@ MPlayJumpTable
	lsls r0, r0, #2
	adds r3, r3, r0
	ldr r3, [r3, #0]
	adds r0, r7, #0	@ r0 = player
	adds r1, r5, #0	@ r1 = track
	bl call_r3
	ldrb r0, [r5, #0]
	cmp r0, #0
	beq mplay_track_done	@ track ended: next track
	b mplay_check_wait
mplay_wait_command:
	ldr r0, mplay_clock_table	@ =sound_clock_table
	subs r1, #0x80	@ 0x80-0xB0, a wait:
	adds r1, r1, r0
	ldrb r0, [r1, #0]
	strb r0, [r5, #1]	@ wait = sound_clock_table[n - 0x80]
mplay_check_wait:
	ldrb r0, [r5, #1]
	cmp r0, #0
	beq mplay_read_command	@ no wait: next command
	.inst.n 0x1E40	@ subs r0, r0, #1
	strb r0, [r5, #1]	@ wait - 1
	ldrb r1, [r5, #0x19]	@ the LFO: lfoSpeed,
	cmp r1, #0
	beq mplay_track_done
	ldrb r0, [r5, #0x17]	@ mod,
	cmp r0, #0
	beq mplay_track_done
	ldrb r0, [r5, #0x1C]	@ lfoDelayC
	cmp r0, #0
	beq mplay_lfo_step
	.inst.n 0x1E40	@ subs r0, r0, #1
	strb r0, [r5, #0x1C]	@ delay not ended
	b mplay_track_done
mplay_lfo_step:
	ldrb r0, [r5, #0x1A]
	adds r0, r0, r1
	strb r0, [r5, #0x1A]	@ phase += lfoSpeed, 8 bits
	adds r1, r0, #0
	subs r0, #0x40
	lsls r0, r0, #0x18
	bpl mplay_lfo_falling	@ phase 0x40-0xBF: the falling half
	lsls r2, r1, #0x18
	asrs r2, r2, #0x18	@ else t = the phase, signed: -64..63
	b mplay_lfo_apply
mplay_lfo_falling:
	movs r0, #0x80
	subs r2, r0, r1	@ t = 0x80 - phase: 64..-63
mplay_lfo_apply:
	ldrb r0, [r5, #0x17]
	muls r0, r2
	asrs r2, r0, #6	@ r2 = mod x t / 64
	ldrb r0, [r5, #0x16]
	eors r0, r2
	lsls r0, r0, #0x18
	beq mplay_track_done	@ modM unchanged
	strb r2, [r5, #0x16]	@ modM
	ldrb r0, [r5, #0]
	ldrb r1, [r5, #0x18]
	cmp r1, #0
	bne mplay_lfo_volume
	movs r1, #0xC	@ modT 0: pitch changed
	b mplay_lfo_mark
mplay_lfo_volume:
	movs r1, #3	@ else volume changed
mplay_lfo_mark:
	orrs r0, r1
	strb r0, [r5, #0]
mplay_track_done:
	mov r2, r9
	mov r3, sl
	mov r4, fp
mplay_next_track:
	.inst.n 0x1E52	@ subs r2, r2, #1
	ble mplay_tick_done
	movs r0, #0x50
	adds r5, r5, r0	@ next track
	lsls r3, r3, #1	@ and its status bit
	b mplay_tick_track
mplay_tick_done:
	mov r6, fp	@ the tracks that existed (see the note above)
	cmp r6, #0
	bne mplay_set_status
	movs r0, #0x80
	lsls r0, r0, #0x18
	str r0, [r7, #4]	@ none: status = 0x80000000, stopped
	b mplay_exit
mplay_set_status:
	str r6, [r7, #4]	@ status = the track bits
	ldrh r0, [r7, #0x22]
	subs r0, #0x96	@ tempoC - 150
mplay_tempo_check:
	strh r0, [r7, #0x22]
	cmp r0, #0x96
	bcc mplay_update_channels
	b mplay_tick	@ 150 or more: one tick
mplay_update_channels:	@ send the changes to the channels:
	ldrb r2, [r7, #8]	@ r2 = tracks left
	ldr r5, [r7, #0x2C]	@ r5 = track
mplay_update_track:
	ldrb r0, [r5, #0]
	movs r1, #0x80
	tst r1, r0
	beq mplay_update_next_track	@ does not exist
	movs r1, #0xF
	tst r1, r0
	beq mplay_update_next_track	@ nothing changed
	mov r9, r2
	adds r0, r7, #0
	adds r1, r5, #0
	bl TrkVolPitSet	@ volMR, volML, keyM, pitM
	ldr r4, [r5, #0x20]
	cmp r4, #0
	beq mplay_update_done
mplay_update_channel:	@ each channel:
	ldrb r1, [r4, #0]
	movs r0, #0xC7
	tst r0, r1
	bne mplay_update_volume
	adds r0, r4, #0
	bl RealClearChain	@ off: unlink it
	b mplay_update_next_channel
mplay_update_volume:
	ldrb r0, [r4, #1]
	movs r6, #7
	ands r6, r0	@ r6 = its CGB channel, 0 for PCM
	ldrb r3, [r5, #0]
	movs r0, #3
	tst r0, r3
	beq mplay_update_pitch
	ldrb r1, [r4, #0x12]	@ volume changed: velocity
	ldrb r0, [r5, #0x10]
	muls r0, r1
	asrs r0, r0, #7
	strb r0, [r4, #2]	@ rightVolume = velocity x volMR / 128
	ldrb r0, [r5, #0x11]
	muls r0, r1
	asrs r0, r0, #7
	strb r0, [r4, #3]	@ leftVolume = velocity x volML / 128
	cmp r6, #0
	beq mplay_update_pitch
	ldrb r0, [r4, #0x1D]
	movs r1, #1
	orrs r0, r1
	strb r0, [r4, #0x1D]	@ CGB: modify |= 1 (volume)
mplay_update_pitch:
	movs r0, #0xC
	tst r0, r3
	beq mplay_update_next_channel
	ldrb r1, [r4, #8]	@ pitch changed: key
	movs r0, #8
	ldrsb r0, [r5, r0]	@ + keyM
	adds r2, r1, r0
	bpl mplay_update_key
	movs r2, #0	@ at least 0
mplay_update_key:
	cmp r6, #0
	beq mplay_update_pcm_freq
	mov r0, r8
	ldr r3, [r0, #0x30]	@ CGB: MidiKeyToCgbFreq(channel, key, pitM)
	adds r1, r2, #0
	ldrb r2, [r5, #9]
	adds r0, r6, #0
	bl call_r3
	str r0, [r4, #0x20]
	ldrb r0, [r4, #0x1D]
	movs r1, #2
	orrs r0, r1
	strb r0, [r4, #0x1D]	@ modify |= 2 (pitch)
	b mplay_update_next_channel
mplay_update_pcm_freq:
	adds r1, r2, #0
	ldrb r2, [r5, #9]	@ pitM
	ldr r0, [r4, #0x24]	@ the wave
	bl MidiKey2Freq
	str r0, [r4, #0x20]	@ frequency
mplay_update_next_channel:
	ldr r4, [r4, #0x34]
	cmp r4, #0
	bne mplay_update_channel
mplay_update_done:
	ldrb r0, [r5, #0]
	movs r1, #0xF0
	ands r0, r1
	strb r0, [r5, #0]	@ clear the change bits
	mov r2, r9
mplay_update_next_track:
	.inst.n 0x1E52	@ subs r2, r2, #1
	ble mplay_exit
	movs r0, #0x50
	adds r5, r5, r0	@ next track
	bgt mplay_update_track	@ (always: an IWRAM address is positive)
mplay_exit:
	ldr r0, mplay_smsh	@ =SOUND_IDENT
	str r0, [r7, #0x34]	@ unlock the player
	pop {r0, r1, r2, r3, r4, r5, r6, r7}
	mov r8, r0
	mov r9, r1
	mov sl, r2
	mov fp, r3
	pop {r0}
	bx r0
	.balign 4
mplay_clock_table:
	.4byte sound_clock_table	@ ticks for each wait, 0x80-0xB0
mplay_sound_area_ptr:
	.4byte SOUND_AREA_PTR	@ holds the address of the SoundArea
mplay_smsh:
	.4byte SOUND_IDENT	@ "Smsh": the player ident when idle
@ SoundMainBTM(r0): clears the 64 bytes (16 words) at r0 and returns r0 + 64.
@ Used for a player (MusicPlayerOpen) and for the first 0x40 bytes of a
@ starting track (MPlayMain). In sound_jump_table (slot 35). Matches MP2000
@ SoundMainBTM. Clobbers r1-r3, ip.
SoundMainBTM:
	mov ip, r4
	movs r1, #0
	movs r2, #0
	movs r3, #0
	movs r4, #0
	stmia r0!, {r1, r2, r3, r4}
	stmia r0!, {r1, r2, r3, r4}
	stmia r0!, {r1, r2, r3, r4}
	stmia r0!, {r1, r2, r3, r4}
	mov r4, ip
	bx lr
@ RealClearChain(channel): removes a channel from the channel list of its track,
@ and sets its track (+0x2C) to 0. List links: prev +0x30, next +0x34, and the
@ first channel at track + 0x20. Does nothing if the channel has no track.
@ The next pointer of the channel stays, so a caller that walks the list can
@ continue from it. Matches MP2000 RealClearChain. In sound_jump_table
@ (slot 34).
@ In:  r0 = the channel. Out: nothing. Clobbers r1-r3.
RealClearChain:
	ldr r3, [r0, #0x2C]	@ its track
	cmp r3, #0
	beq clearchain_return	@ none: nothing to do
	ldr r1, [r0, #0x34]	@ r1 = next
	ldr r2, [r0, #0x30]	@ r2 = prev
	cmp r2, #0
	beq clearchain_was_first
	str r1, [r2, #0x34]	@ prev.next = next
	b clearchain_fix_next
clearchain_was_first:
	str r1, [r3, #0x20]	@ it was first: first channel of the track = next
clearchain_fix_next:
	cmp r1, #0
	beq clearchain_no_track
	str r2, [r1, #0x30]	@ next.prev = prev
clearchain_no_track:
	movs r1, #0
	str r1, [r0, #0x2C]	@ no track
clearchain_return:
	bx lr
@ TrackStop(player, track): silences a track immediately.
@ For each of its channels that is not off: a CGB channel first gets
@ SoundArea.CgbOscOff(its number). Then statusFlags = 0 and track = 0. (A
@ channel that is already off keeps its track pointer.) Then the channel list
@ of the track is emptied (+0x20 = 0). The flags of the track and its position
@ in the song do not change.
@ Does nothing if the track does not exist (flags bit 7). Matches MP2000
@ TrackStop. The player SWIs and FadeOutBody call it. In sound_jump_table
@ (slot 31).
@ In:  r1 = the track (r0, the player, is not used). Out: nothing.
@ Clobbers r0-r3.
TrackStop:
	push {r4, r5, r6, lr}
	adds r5, r1, #0	@ r5 = track
	ldrb r1, [r5, #0]
	movs r0, #0x80
	tst r0, r1
	beq trackstop_return	@ does not exist: return
	ldr r4, [r5, #0x20]	@ r4 = its first channel
	cmp r4, #0
	beq trackstop_empty_list
	movs r6, #0
trackstop_channel_loop:
	ldrb r0, [r4, #0]
	cmp r0, #0
	beq trackstop_next_channel	@ already off
	ldrb r0, [r4, #1]
	movs r3, #7
	ands r0, r3	@ its CGB channel
	beq trackstop_channel_off
	ldr r3, note_sound_area_ptr	@ =SOUND_AREA_PTR
	ldr r3, [r3, #0]
	ldr r3, [r3, #0x2C]
	bl call_r3	@ CgbOscOff(channel): DummyFunc, does nothing
trackstop_channel_off:
	strb r6, [r4, #0]	@ off
	str r6, [r4, #0x2C]	@ no track
trackstop_next_channel:
	ldr r4, [r4, #0x34]	@ next channel (the list is dropped, not unlinked)
	cmp r4, #0
	bne trackstop_channel_loop
trackstop_empty_list:
	str r4, [r5, #0x20]	@ no channels
trackstop_return:
	pop {r4, r5, r6}
	pop {r0}
	bx r0
@ ply_note(n, player, track): plays a note, commands 0xCF-0xFF.
@ Matches MP2000 ply_note, probably an earlier version (the drum pan goes to
@ panX of the track; the channel volume is calculated inline). MPlayMain calls
@ it through SoundArea.plynote, which SoundDriverInit points here.
@ In:  r0 = the command - 0xCF (0 TIE, 1-48 N01-N96), r1 = player, r2 = track,
@      with its cmdPtr directly after the command.
@ Does: 1. gateTime (+0x04) = sound_clock_table[r0]. Then up to three data
@          bytes (below 0x80): key (+0x05), velocity (+0x06), and ticks added
@          to gateTime. For a missing byte, the value of the last note stays.
@          These reads do not go through sound_read_byte.
@       2. The voice:
@          - plain voice: the voice of the track (+0x24).
@          - drum kit (type 0x80): voice number key of the kit table.
@          - key split (0x40): the voice that its key table gives.
@          A drum plays its own key. If pan_sweep bit 7 is set, the drum pan
@          goes to panX (volume changed). A kit or split found inside another:
@          no note.
@       3. Priority = player + track priority, at most 255.
@       4. A channel:
@          - CGB voice (type bits 0-2 = 1-4): that CGB channel, if the
@            SoundArea has CGB channels (the BIOS has none: no note). The
@            channel must be off, released, of lower priority, or of equal
@            priority from this track or a later one.
@          - PCM voice, from the first maxChans channels: the first that is
@            off. Else the released one with the lowest priority. Else the
@            playing one with the lowest priority, if that is below the
@            priority of this note (or equal, from this track or a later one;
@            tracks are compared by address). None: no note.
@       5. The channel is unlinked from its old track and put first in the
@          list of this track. The LFO restarts: lfoDelayC = lfoDelay, and if
@          that is not 0, lfoSpeedC = modM = 0. Then TrkVolPitSet. The channel
@          gets:
@          - gateTime, midiKey and velocity from the track, the priority, the key
@          - type, wave and envelope from the voice
@          - the echo of the track (+0x1E)
@          - rightVolume and leftVolume (velocity x volMR, volML / 128)
@          - frequency = MidiKey2Freq(wave, key + keyM (at least 0), pitM).
@            For CGB: SoundArea.MidiKeyToCgbFreq, and the length and sweep of
@            the voice.
@          statusFlags = 0x80: the mixer starts the channel.
@       6. The flags bits 0-3 of the track are cleared.
@ Out: nothing. Keeps r4-r11.
@ Locals: [sp] player, [sp+4] SoundArea, [sp+8] the key, [sp+0xC] the CGB
@      channel (0: PCM), [sp+0x10] the priority. r9 = the voice.
ply_note:
	push {r4, r5, r6, r7, lr}
	mov r4, r8
	mov r5, r9
	mov r6, sl
	mov r7, fp
	push {r4, r5, r6, r7}
	sub sp, #0x14
	str r1, [sp, #0]	@ [sp] = player
	adds r5, r2, #0	@ r5 = track
	ldr r1, note_sound_area_ptr	@ =SOUND_AREA_PTR
	ldr r1, [r1, #0]
	str r1, [sp, #4]	@ [sp+4] = the SoundArea
	ldr r1, note_clock_table	@ =sound_clock_table
	adds r0, r0, r1
	ldrb r0, [r0, #0]
	strb r0, [r5, #4]	@ gateTime = sound_clock_table[n]
	ldr r3, [r5, #0x40]	@ the data bytes after the command:
	ldrb r0, [r3, #0]
	cmp r0, #0x80
	bcs note_voice
	strb r0, [r5, #5]	@ key
	.inst.n 0x1C5B	@ adds r3, r3, #1
	ldrb r0, [r3, #0]
	cmp r0, #0x80
	bcs note_args_done
	strb r0, [r5, #6]	@ velocity
	.inst.n 0x1C5B	@ adds r3, r3, #1
	ldrb r0, [r3, #0]
	cmp r0, #0x80
	bcs note_args_done
	ldrb r1, [r5, #4]
	adds r1, r1, r0
	strb r1, [r5, #4]	@ gateTime + extra ticks
	.inst.n 0x1C5B	@ adds r3, r3, #1
note_args_done:
	str r3, [r5, #0x40]	@ cmdPtr = after the bytes read
note_voice:
	adds r4, r5, #0
	adds r4, #0x24	@ r4 = voice of the track
	ldrb r2, [r4, #0]	@ r2 = its type
	movs r0, #0xC0
	tst r0, r2
	beq note_plain_voice	@ a plain voice
	ldrb r3, [r5, #5]	@ kit or split: select by the key
	movs r0, #0x40
	tst r0, r2
	beq note_kit_voice
	ldr r1, [r5, #0x2C]	@ split: its key table
	adds r1, r1, r3
	ldrb r0, [r1, #0]	@ voice number = table[key]
	b note_table_voice
note_kit_voice:
	adds r0, r3, #0	@ kit: voice number = key
note_table_voice:
	lsls r1, r0, #1
	adds r1, r1, r0
	lsls r1, r1, #2	@ x 12
	ldr r0, [r5, #0x28]	@ voice table of the kit or split
	adds r1, r1, r0
	mov r9, r1	@ r9 = the voice to play
	mov r6, r9
	ldrb r1, [r6, #0]
	movs r0, #0xC0
	tst r0, r1
	beq note_drum_pan
	b note_exit	@ a kit or split again: no note
note_drum_pan:
	movs r0, #0x80
	tst r0, r2
	beq note_priority	@ split: key of the track
	ldrb r1, [r6, #3]	@ kit: pan_sweep of the drum
	movs r0, #0x80
	tst r0, r1
	beq note_drum_key
	subs r1, #0xC0
	lsls r1, r1, #1
	strb r1, [r5, #0x15]	@ panX = (pan_sweep - 0xC0) x 2
	ldrb r0, [r5, #0]
	movs r1, #3
	orrs r0, r1
	strb r0, [r5, #0]	@ volume changed
note_drum_key:
	ldrb r3, [r6, #1]	@ and the key of the drum
	b note_priority
note_plain_voice:
	mov r9, r4	@ r9 = voice of the track
	ldrb r3, [r5, #5]	@ r3 = key of the track
note_priority:
	str r3, [sp, #8]	@ [sp+8] = the key to play
	ldr r6, [sp, #0]
	ldrb r1, [r6, #9]	@ player priority
	ldrb r0, [r5, #0x1D]	@ + track priority
	adds r0, r0, r1
	cmp r0, #0xFF
	bls note_cgb_check
	movs r0, #0xFF
note_cgb_check:
	str r0, [sp, #0x10]	@ [sp+0x10] = priority, at most 255
	mov r6, r9
	ldrb r0, [r6, #0]
	movs r6, #7
	ands r6, r0
	str r6, [sp, #0xC]	@ [sp+0xC] = the CGB channel, 0 for PCM
	beq note_find_pcm_channel
	ldr r0, [sp, #4]
	ldr r4, [r0, #0x1C]	@ cgbChans
	cmp r4, #0
	bne note_cgb_channel
	b note_exit	@ none (the BIOS): no note
note_cgb_channel:
	.inst.n 0x1E76	@ subs r6, r6, #1
	lsls r0, r6, #6
	adds r4, r4, r0	@ r4 = that CGB channel
	ldrb r1, [r4, #0]
	movs r0, #0xC7
	tst r0, r1
	beq note_take_channel	@ off: take it
	movs r0, #0x40
	tst r0, r1
	bne note_take_channel	@ released: take it
	ldrb r1, [r4, #0x13]
	ldr r0, [sp, #0x10]
	cmp r1, r0
	bcc note_take_channel	@ lower priority: take it
	beq note_cgb_same_priority
	b note_exit	@ higher: no note
note_cgb_same_priority:
	ldr r0, [r4, #0x2C]
	cmp r0, r5
	bcs note_take_channel	@ equal, from this track or a later one: take it
	b note_exit
note_find_pcm_channel:	@ PCM: find a channel
	ldr r6, [sp, #0x10]	@ r6 = lowest priority so far (starts at this note)
	adds r7, r5, #0	@ r7 = its track (starts at this track)
	movs r2, #0	@ r2 = 1 after a released channel is found
	mov r8, r2	@ r8 = the selected channel: none yet
	ldr r4, [sp, #4]
	ldrb r3, [r4, #6]	@ r3 = maxChans
	adds r4, #0x50	@ r4 = channel 0
note_pcm_loop:
	ldrb r1, [r4, #0]
	movs r0, #0xC7
	tst r0, r1
	beq note_take_channel	@ off: take it now
	movs r0, #0x40
	tst r0, r1
	beq note_pcm_playing
	cmp r2, #0	@ released:
	bne note_pcm_priority
	.inst.n 0x1C52	@ adds r2, r2, #1
	ldrb r6, [r4, #0x13]	@ the first released one is selected,
	ldr r7, [r4, #0x2C]	@ whatever its priority
	b note_pcm_choose
note_pcm_playing:
	cmp r2, #0	@ playing: only if no released one is found yet
	bne note_pcm_next
note_pcm_priority:
	ldrb r0, [r4, #0x13]
	cmp r0, r6
	bcs note_pcm_equal
	adds r6, r0, #0	@ lower priority: select it
	ldr r7, [r4, #0x2C]
	b note_pcm_choose
note_pcm_equal:
	bhi note_pcm_next	@ higher: do not select
	ldr r0, [r4, #0x2C]
	cmp r0, r7
	bls note_pcm_earlier_track
	adds r7, r0, #0	@ equal, a later track: select it
	b note_pcm_choose
note_pcm_earlier_track:
	bcc note_pcm_next	@ equal, an earlier track: no (the same track: yes)
note_pcm_choose:
	mov r8, r4
note_pcm_next:
	adds r4, #0x40
	.inst.n 0x1E5B	@ subs r3, r3, #1
	bgt note_pcm_loop
	mov r4, r8
	cmp r4, #0
	beq note_exit	@ no channel selected: no note
note_take_channel:	@ r4 = the channel:
	adds r0, r4, #0
	bl RealClearChain	@ remove from the list of its old track
	movs r1, #0
	str r1, [r4, #0x30]	@ prev = none
	ldr r3, [r5, #0x20]
	str r3, [r4, #0x34]	@ next = first channel of the track
	cmp r3, #0
	beq note_link_first
	str r4, [r3, #0x30]
note_link_first:
	str r4, [r5, #0x20]	@ first channel of the track = this one
	str r5, [r4, #0x2C]	@ track = this track
	ldrb r0, [r5, #0x1B]
	strb r0, [r5, #0x1C]	@ lfoDelayC = lfoDelay
	cmp r0, r1
	beq note_setup_channel
	strb r1, [r5, #0x1A]	@ a delay: LFO phase 0,
	strb r1, [r5, #0x16]	@ modM 0
note_setup_channel:
	ldr r0, [sp, #0]
	adds r1, r5, #0
	bl TrkVolPitSet
	ldr r0, [r5, #4]
	str r0, [r4, #0x10]	@ gateTime, midiKey = key, velocity (+0x13 next)
	ldr r0, [sp, #0x10]
	strb r0, [r4, #0x13]	@ priority
	ldr r0, [sp, #8]
	strb r0, [r4, #8]	@ key
	mov r6, r9
	ldrb r0, [r6, #0]
	strb r0, [r4, #1]	@ type
	ldr r7, [r6, #4]
	str r7, [r4, #0x24]	@ wave
	ldr r0, [r6, #8]
	str r0, [r4, #4]	@ attack, decay, sustain, release
	ldrh r0, [r5, #0x1E]
	strh r0, [r4, #0xC]	@ echo volume and length
	ldrb r1, [r4, #0x12]
	ldrb r0, [r5, #0x10]
	muls r0, r1
	asrs r0, r0, #7
	strb r0, [r4, #2]	@ rightVolume = velocity x volMR / 128
	ldrb r0, [r5, #0x11]
	muls r0, r1
	asrs r0, r0, #7
	strb r0, [r4, #3]	@ leftVolume = velocity x volML / 128
	ldrb r1, [r4, #8]
	movs r0, #8
	ldrsb r0, [r5, r0]
	adds r3, r1, r0	@ key + keyM,
	bpl note_freq
	movs r3, #0	@ at least 0
note_freq:
	ldr r6, [sp, #0xC]
	cmp r6, #0
	beq note_pcm_freq
	mov r6, r9	@ CGB:
	ldrb r0, [r6, #2]
	strb r0, [r4, #0x1E]	@ length
	ldrb r1, [r6, #3]
	movs r0, #0x80
	tst r0, r1
	bne note_cgb_freq
	strb r1, [r4, #0x1F]	@ sweep (unless bit 7: drum pan)
note_cgb_freq:
	ldrb r2, [r5, #9]
	adds r1, r3, #0
	ldr r0, [sp, #0xC]
	ldr r3, [sp, #4]
	ldr r3, [r3, #0x30]
	bl call_r3	@ MidiKeyToCgbFreq(channel, key, pitM)
	b note_start
note_pcm_freq:
	ldrb r2, [r5, #9]
	adds r1, r3, #0
	adds r0, r7, #0
	bl MidiKey2Freq	@ (wave, key, pitM)
note_start:
	str r0, [r4, #0x20]	@ frequency
	movs r0, #0x80
	strb r0, [r4, #0]	@ start
	ldrb r1, [r5, #0]
	movs r0, #0xF0
	ands r0, r1
	strb r0, [r5, #0]	@ clear the change bits of the track
note_exit:
	add sp, #0x14
	pop {r0, r1, r2, r3, r4, r5, r6, r7}
	mov r8, r0
	mov r9, r1
	mov sl, r2
	mov fp, r3
	pop {r0}
	bx r0
	.balign 4, 0
	.balign 4
note_sound_area_ptr:
	.4byte SOUND_AREA_PTR	@ holds the address of the SoundArea (TrackStop, ply_note)
note_clock_table:
	.4byte sound_clock_table	@ ticks for each note length (ply_note)
@ ply_endtie: EOT (0xCE), slot 29 of sound_jump_table. Ends a TIE note.
@ Matches MP2000 ply_endtie, but this version does not skip a channel that
@ is already released.
@ If a data byte (below 0x80) follows, it is the key and becomes the track key
@ (+0x05). Else the key is the track key. The first channel of the track that
@ is on (start or envelope bits, 0x83) with that midiKey (+0x11) is released
@ (flag 0x40).
@ In:  r1 = the track. Out: nothing. Clobbers r0-r3.
ply_endtie:
	push {r4, lr}
	ldr r2, [r1, #0x40]
	ldrb r3, [r2, #0]	@ (read without sound_read_byte)
	cmp r3, #0x80
	bcs endtie_track_key
	strb r3, [r1, #5]	@ a key: it becomes the track key
	.inst.n 0x1C52	@ adds r2, r2, #1
	str r2, [r1, #0x40]
	b endtie_find
endtie_track_key:
	ldrb r3, [r1, #5]	@ none: use the track key
endtie_find:
	ldr r1, [r1, #0x20]	@ its channels:
	cmp r1, #0
	beq endtie_return
	movs r4, #0x83
endtie_channel_loop:
	ldrb r2, [r1, #0]
	tst r2, r4
	beq endtie_next_channel	@ not playing
	ldrb r0, [r1, #0x11]
	cmp r0, r3
	bne endtie_next_channel	@ another key
	movs r0, #0x40
	orrs r2, r0
	strb r2, [r1, #0]	@ released; only the first match
	b endtie_return
endtie_next_channel:
	ldr r1, [r1, #0x34]
	cmp r1, #0
	bne endtie_channel_loop
endtie_return:
	pop {r4}
	pop {r0}
	bx r0
@ ply_fine: FINE (0xB1), ends the track. It is also every unused slot of
@ sound_jump_table (0xB6-0xB9, 0xC6, 0xC7, 0xC9-0xCB, 0xCD), and the action for
@ PATT nested too deep. Matches MP2000 ply_fine.
@ Each channel of the track that is on is released (flag 0x40: its note dies
@ away by itself). Each channel is unlinked (RealClearChain). Then flags = 0:
@ the track no longer exists.
@ In:  r1 = the track. Out: nothing. Clobbers r0-r3.
ply_fine:
	push {r4, r5, lr}
	adds r5, r1, #0	@ r5 = track
	ldr r4, [r5, #0x20]	@ its channels:
	cmp r4, #0
	beq fine_track_off
fine_channel_loop:
	ldrb r1, [r4, #0]
	movs r0, #0xC7
	tst r0, r1
	beq fine_unlink
	movs r0, #0x40
	orrs r1, r0
	strb r1, [r4, #0]	@ on: released
fine_unlink:
	adds r0, r4, #0
	bl RealClearChain	@ remove it from the track
	ldr r4, [r4, #0x34]	@ (RealClearChain keeps next)
	cmp r4, #0
	bne fine_channel_loop
fine_track_off:
	movs r0, #0
	strb r0, [r5, #0]	@ flags = 0: track ended
	pop {r4, r5}
	pop {r0}
	bx r0
@ SWI 0x2A: copies sound_jump_table
@
@ SoundGetJumpList SWI 0x2A: matches the MP2000 routine that copies its jump
@ table template (MPlayJumpTableCopy in decompilations).
@ GBATEK (undocumented): receives pointers to 36 more sound functions.
@   r0 = the destination, 4-aligned. GBATEK gives a 120h-byte buffer.
@ Does: copies 36 words (0x90 bytes) from sound_jump_table: the 30 command
@      handlers, then SampleFreqSet, TrackStop, FadeOutBody, TrkVolPitSet,
@      RealClearChain, SoundMainBTM. Each word goes through sound_read_byte,
@      which lets all of them through (its allowed range starts at the table).
@      Probably so that the m4a library of a game can use the BIOS handlers.
@ Out: r0 = the destination + 0x90. Clobbers r1-r3, ip.
SoundGetJumpList:
	mov ip, lr
	movs r1, #0x24	@ 36 words
	ldr r2, chk_jump_table	@ =sound_jump_table
jumplist_copy_loop:
	ldr r3, [r2, #0]
	bl sound_read_byte	@ (address check: always allowed here)
	stmia r0!, {r3}
	.inst.n 0x1D12	@ adds r2, r2, #4
	.inst.n 0x1E49	@ subs r1, r1, #1
	bgt jumplist_copy_loop
	bx ip
@ ldrb_r3_r2: r3 = the byte at r2, through sound_read_byte. The result is 0 if
@ r2 is in the BIOS below sound_jump_table (or unmapped). Used for the lowest
@ address byte in ply_goto. Keeps r0-r2.
ldrb_r3_r2:
	ldrb r3, [r2, #0]
@ reads [r2] only if it is not in the BIOS below sound_jump_table
@
@ sound_read_byte: the guard of the driver against reads of the BIOS. It does
@ not read memory itself: r3 holds a value just read from the address in r2,
@ and r3 = 0 if that address is not allowed.
@   Allowed:     sound_jump_table to the end of the BIOS (0x3FFF), and 0x02000000 up.
@   Not allowed: 0 to sound_jump_table - 1, and 0x4000-0x01FFFFFF.
@ The MP2000 library has the same check (named chk_adr_r2 in decompilations).
@ Checked:
@   - SoundGetJumpList
@   - the argument bytes of each handler (ld_r3_tp_adr_i, ld_r3_tp_adr_i_r2),
@     except the REPT count test and the PORT register
@   - the three VOICE words
@   - the lowest GOTO address byte
@ Not checked: command bytes, note data bytes, the EOT key, the VOICE number,
@ the other three GOTO bytes, the kit and split tables that ply_note reads,
@ song headers, waves, and wave.freq in MidiKey2Freq.
@ Thus a song, its voices and all other data that the BIOS plays must be at
@ sound_jump_table or after it (README.md). If not, some of the data reads as 0.
@ In:  r2 = the address, r3 = the value. Out: r3. Keeps r0-r2.
sound_read_byte:
	push {r0}
	lsrs r0, r2, #0x19
	bne chk_return	@ 0x02000000 and up: allowed
	ldr r0, chk_jump_table	@ =sound_jump_table
	cmp r2, r0
	bcc chk_refused	@ below sound_jump_table: refused
	lsrs r0, r2, #0xE
	beq chk_return	@ below 0x4000: allowed
chk_refused:
	movs r3, #0	@ refused: 0
chk_return:
	pop {r0}
	bx lr
	.balign 4
chk_jump_table:
	.4byte sound_jump_table	@ the table, and the lowest BIOS address the driver may read
@ ld_r3_tp_adr_i: reads a handler argument. r3 = the next command byte of track
@ r1, through sound_read_byte. The cmdPtr (+0x40) of the track moves past it.
@ Out: r3 = the byte, r2 = its address. Keeps r0, r1.
ld_r3_tp_adr_i:
	ldr r2, [r1, #0x40]
@ ld_r3_tp_adr_i_r2: the same, but the byte address is already in r2 (ply_port).
ld_r3_tp_adr_i_r2:
	adds r3, r2, #1
	str r3, [r1, #0x40]	@ cmdPtr = r2 + 1
	ldrb r3, [r2, #0]
	b sound_read_byte
@ ply_goto: GOTO (0xB2) a. The track continues at a (the 4 bytes after the
@ command, little-endian). Only the lowest byte goes through sound_read_byte.
@ ply_patt also ends here, and ply_rept enters at ply_goto_read. Matches
@ MP2000 ply_goto.
@ In:  r1 = the track. Out: nothing. Clobbers r0, r2, r3.
ply_goto:
	push {lr}
ply_goto_read:	@ (entry from ply_rept)
	ldr r2, [r1, #0x40]	@ the address bytes
	ldrb r0, [r2, #3]
	lsls r0, r0, #8
	ldrb r3, [r2, #2]
	orrs r0, r3
	lsls r0, r0, #8
	ldrb r3, [r2, #1]
	orrs r0, r3
	lsls r0, r0, #8
	bl ldrb_r3_r2	@ the lowest byte, checked
	orrs r0, r3
	str r0, [r1, #0x40]	@ continue there
	pop {r0}
	bx r0
@ ply_patt: PATT (0xB3) a. Calls the pattern at a. The return address (after
@ a) goes on the stack of the track (+0x44 + 4 x level). The level (+0x02)
@ increases by 1, and the command continues as GOTO. With 3 calls already in
@ progress: FINE instead, and the track ends. Matches MP2000 ply_patt.
@ In:  r1 = the track. Out: nothing. Clobbers r0, r2, r3.
ply_patt:
	ldrb r2, [r1, #2]	@ the level
	cmp r2, #3
	bcs patt_too_deep	@ stack full
	lsls r2, r2, #2
	adds r3, r1, r2
	ldr r2, [r1, #0x40]
	.inst.n 0x1D12	@ adds r2, r2, #4
	str r2, [r3, #0x44]	@ return address: after the 4 bytes
	ldrb r2, [r1, #2]
	.inst.n 0x1C52	@ adds r2, r2, #1
	strb r2, [r1, #2]
	b ply_goto
patt_too_deep:
	b ply_fine
@ ply_pend: PEND (0xB4), the end of a pattern. If a PATT is in progress, the
@ level (+0x02) decreases by 1 and the track continues at the return address.
@ Else it does nothing. Matches MP2000 ply_pend.
@ In:  r1 = the track. Out: nothing. Clobbers r2, r3.
ply_pend:
	ldrb r2, [r1, #2]
	cmp r2, #0
	beq pend_return	@ not in a pattern
	.inst.n 0x1E52	@ subs r2, r2, #1
	strb r2, [r1, #2]
	lsls r2, r2, #2
	adds r3, r1, r2
	ldr r2, [r3, #0x44]
	str r2, [r1, #0x40]	@ return to after the PATT
pend_return:
	bx lr
@ ply_rept: REPT (0xB5) n a, repeat. If n = 0, it always jumps to a (an endless
@ loop). Else repN (+0x03) counts the passes. It jumps to a while repN + 1 < n,
@ so the part from a to here plays n times. Then repN = 0 and the track
@ continues after a. Matches MP2000 ply_rept. The test for 0 reads n
@ directly; the count reads n through sound_read_byte.
@ In:  r1 = the track. Out: nothing. Clobbers r0, r2, r3, ip.
ply_rept:
	push {lr}
	ldr r2, [r1, #0x40]
	ldrb r3, [r2, #0]	@ n
	cmp r3, #0
	bne rept_count
	.inst.n 0x1C52	@ adds r2, r2, #1
	str r2, [r1, #0x40]
	b ply_goto_read	@ 0: always jump
rept_count:
	ldrb r3, [r1, #3]
	.inst.n 0x1C5B	@ adds r3, r3, #1
	strb r3, [r1, #3]	@ repN + 1
	mov ip, r3
	bl ld_r3_tp_adr_i	@ n again, checked; cmdPtr at a
	cmp ip, r3
	bcs rept_done
	b ply_goto_read	@ fewer than n passes: jump
rept_done:
	movs r3, #0
	strb r3, [r1, #3]	@ done: repN = 0
	.inst.n 0x1D52	@ adds r2, r2, #5
	str r2, [r1, #0x40]	@ cmdPtr = after n and a
	pop {r0}
	bx r0
@ ply_prio: PRIO (0xBA) n. The track priority (+0x1D) = n. Matches MP2000
@ ply_prio. In: r1 = the track. Clobbers r2, r3, ip.
ply_prio:
	mov ip, lr
	bl ld_r3_tp_adr_i
	strb r3, [r1, #0x1D]
	bx ip
@ ply_tempo: TEMPO (0xBB) n. tempoD (+0x1C) = 2n, tempoI (+0x20) = 2n x
@ tempoU / 256. 2n is beats per minute at 24 ticks per beat (inferred).
@ Matches MP2000 ply_tempo. In: r0 = the player, r1 = the track.
@ Clobbers r2, r3, ip.
ply_tempo:
	mov ip, lr
	bl ld_r3_tp_adr_i
	lsls r3, r3, #1
	strh r3, [r0, #0x1C]	@ tempoD = 2n
	ldrh r2, [r0, #0x1E]
	muls r3, r2
	lsrs r3, r3, #8
	strh r3, [r0, #0x20]	@ tempoI = tempoD x tempoU / 256
	bx ip
@ ply_keysh: KEYSH (0xBC) n. keyShift (+0x0A) = n, in signed semitones. Pitch
@ changed (flags |= 0x0C). Matches MP2000 ply_keysh.
@ In: r1 = the track. Clobbers r2, r3, ip.
ply_keysh:
	mov ip, lr
	bl ld_r3_tp_adr_i
	strb r3, [r1, #0xA]
	ldrb r3, [r1, #0]
	movs r2, #0xC
	orrs r3, r2
	strb r3, [r1, #0]
	bx ip
@ ply_voice: VOICE (0xBD) n. Copies voice n (12 bytes) of the player voice
@ table (+0x30) into the track (+0x24). Each word goes through sound_read_byte.
@ The number n is read directly. Matches MP2000 ply_voice.
@ In: r0 = the player, r1 = the track. Clobbers r2, r3, ip.
ply_voice:
	mov ip, lr
	ldr r2, [r1, #0x40]
	ldrb r3, [r2, #0]	@ n
	.inst.n 0x1C52	@ adds r2, r2, #1
	str r2, [r1, #0x40]
	lsls r2, r3, #1
	adds r2, r2, r3
	lsls r2, r2, #2	@ x 12
	ldr r3, [r0, #0x30]	@ the voice table
	adds r2, r2, r3
	ldr r3, [r2, #0]
	bl sound_read_byte
	str r3, [r1, #0x24]	@ type, key, length, pan_sweep
	ldr r3, [r2, #4]
	bl sound_read_byte
	str r3, [r1, #0x28]	@ the wave (or a table)
	ldr r3, [r2, #8]
	bl sound_read_byte
	str r3, [r1, #0x2C]	@ attack, decay, sustain, release (or a table)
	bx ip
@ ply_vol: VOL (0xBE) n. vol (+0x12) = n. Volume changed (flags |= 3).
@ Matches MP2000 ply_vol. In: r1 = the track. Clobbers r2, r3, ip.
ply_vol:
	mov ip, lr
	bl ld_r3_tp_adr_i
	strb r3, [r1, #0x12]
	ldrb r3, [r1, #0]
	movs r2, #3
	orrs r3, r2
	strb r3, [r1, #0]
	bx ip
@ ply_pan: PAN (0xBF) n. pan (+0x14) = n - 0x40 (0x40 is the centre). Volume
@ changed. Matches MP2000 ply_pan. In: r1 = the track.
@ Clobbers r2, r3, ip.
ply_pan:
	mov ip, lr
	bl ld_r3_tp_adr_i
	subs r3, #0x40
	strb r3, [r1, #0x14]
	ldrb r3, [r1, #0]
	movs r2, #3
	orrs r3, r2
	strb r3, [r1, #0]
	bx ip
@ ply_bend: BEND (0xC0) n. bend (+0x0E) = n - 0x40. Pitch changed.
@ Matches MP2000 ply_bend. In: r1 = the track. Clobbers r2, r3, ip.
ply_bend:
	mov ip, lr
	bl ld_r3_tp_adr_i
	subs r3, #0x40
	strb r3, [r1, #0xE]
	ldrb r3, [r1, #0]
	movs r2, #0xC
	orrs r3, r2
	strb r3, [r1, #0]
	bx ip
@ ply_bendr: BENDR (0xC1) n. bendRange (+0x0F) = n semitones. Pitch changed.
@ Matches MP2000 ply_bendr. In: r1 = the track.
@ Clobbers r2, r3, ip.
ply_bendr:
	mov ip, lr
	bl ld_r3_tp_adr_i
	strb r3, [r1, #0xF]
	ldrb r3, [r1, #0]
	movs r2, #0xC
	orrs r3, r2
	strb r3, [r1, #0]
	bx ip
@ ply_lfos: LFOS (0xC2) n. lfoSpeed (+0x19) = n. If n = 0, also modM (+0x16)
@ = 0. No change flag is set. Matches MP2000 ply_lfos.
@ In: r1 = the track. Clobbers r2, r3, ip.
ply_lfos:
	mov ip, lr
	bl ld_r3_tp_adr_i
	strb r3, [r1, #0x19]
	cmp r3, #0
	bne lfos_return
	strb r3, [r1, #0x16]
lfos_return:
	bx ip
@ ply_lfodl: LFODL (0xC3) n. lfoDelay (+0x1B) = n ticks, used from the next
@ note. Matches MP2000 ply_lfodl. In: r1 = the track.
@ Clobbers r2, r3, ip.
ply_lfodl:
	mov ip, lr
	bl ld_r3_tp_adr_i
	strb r3, [r1, #0x1B]
	bx ip
@ ply_mod: MOD (0xC4) n. mod (+0x17, the LFO depth) = n. If n = 0, also
@ modM = 0. Matches MP2000 ply_mod. In: r1 = the track.
@ Clobbers r2, r3, ip.
ply_mod:
	mov ip, lr
	bl ld_r3_tp_adr_i
	strb r3, [r1, #0x17]
	cmp r3, #0
	bne mod_return
	strb r3, [r1, #0x16]
mod_return:
	bx ip
@ ply_modt: MODT (0xC5) n. modT (+0x18) = n: what the LFO changes (0 pitch,
@ 1 volume, 2 pan). If the value changed, volume and pitch are both marked
@ changed (flags |= 0x0F). Matches MP2000 ply_modt.
@ In: r1 = the track. Clobbers r0, r2, r3, ip.
ply_modt:
	mov ip, lr
	bl ld_r3_tp_adr_i
	ldrb r0, [r1, #0x18]
	cmp r0, r3
	beq modt_return	@ same value: do nothing
	strb r3, [r1, #0x18]
	ldrb r3, [r1, #0]
	movs r2, #0xF
	orrs r3, r2
	strb r3, [r1, #0]
modt_return:
	bx ip
@ ply_tune: TUNE (0xC8) n. tune (+0x0C) = n - 0x40, in 64ths of a semitone.
@ Pitch changed. Matches MP2000 ply_tune. In: r1 = the track.
@ Clobbers r2, r3, ip.
ply_tune:
	mov ip, lr
	bl ld_r3_tp_adr_i
	subs r3, #0x40
	strb r3, [r1, #0xC]
	ldrb r3, [r1, #0]
	movs r2, #0xC
	orrs r3, r2
	strb r3, [r1, #0]
	bx ip
@ ply_port: PORT (0xCC) r v. Writes the byte v to the I/O address 0x04000060 + r
@ (the sound registers start there). r is read directly and not checked, so any
@ byte of 0x04000060-0x0400015F can be written. v goes through sound_read_byte.
@ Matches MP2000 ply_port. The songs in the BIOS do not use it.
@ In: r1 = the track. Clobbers r0, r2, r3, ip.
ply_port:
	mov ip, lr
	ldr r2, [r1, #0x40]
	ldrb r3, [r2, #0]	@ r
	.inst.n 0x1C52	@ adds r2, r2, #1
	ldr r0, port_sound_regs	@ =REG_SOUND1CNT_L: 0x04000060
	adds r0, r0, r3	@ r0 = 0x04000060 + r
	bl ld_r3_tp_adr_i_r2	@ r3 = v, checked; cmdPtr after both bytes
	strb r3, [r0, #0]
	bx ip
	.balign 4, 0
	.balign 4
port_sound_regs:
	.4byte REG_SOUND1CNT_L	@ the first sound register: the base of the PORT offsets
@ ---------------------------------------------------------------------------
@ The rest of this file is MultiBoot code, not sound driver code. It comes
@ before the first label of multiboot.s (MultiBoot, 0x28CE), and only that file
@ calls it. Read it with the GBATEK "Multiboot Transfer Protocol". The callers
@ were not followed far.
@ ---------------------------------------------------------------------------
@ mb_crc_word: the MultiBoot checksum. Updates the CRC r5 with the 32-bit word
@ r2, one bit at a time from bit 0: if (r5 xor r2) bit 0 is 1, r5 = (r5 >> 1)
@ xor r0, else r5 >> 1. This is the same as the GBATEK pseudo code for SWI
@ 0x25: c = c xor data, then 32 times: c = c shr 1, xor x on a carry.
@ In:  r0 = x (0xC37B normal, 0xA517 multiplay, as GBATEK; 0xA1C1 in the JOY
@      bus branch of intro_link_poll), r2 = the word, r5 = c.
@ Out: r5 = c. Clobbers r1, r2, r6 (0).
mb_crc_word:
	movs r6, #0x20	@ 32 bits
mb_crc_bit_loop:
	adds r1, r5, #0
	eors r1, r2
	lsrs r5, r5, #1
	lsrs r1, r1, #1	@ carry = bit 0 of c xor data
	bcc mb_crc_next_bit
	eors r5, r0	@ xor x
mb_crc_next_bit:
	lsrs r2, r2, #1	@ next data bit
	.inst.n 0x1E76	@ subs r6, r6, #1
	bne mb_crc_bit_loop
	bx lr
@ mb_decrypt: MultiBoot, receive side (intro_link_poll). Decrypts in place the
@ words that arrived since the last call (at most 0x89 per call), and updates
@ the checksum with each word (mb_crc_word). Per word: m = m x r1 + 1,
@ word = word xor m xor -address xor k. This reverses the GBATEK encryption
@ for SWI 0x25.
@ In:  r7 = the receive work area: +0x44 the next word to decrypt, +0x38 the
@      end of the data received so far, +0x04 m, +0x20 c.
@      r0 = x, r1 = the multiplier for m, r3 = k. From intro_link_poll:
@      0x6177614B "Kawa" and 0x20796220 " by " on the JOY bus, else 0x6F646573
@      "sedo" and the GBATEK k.
@ Out: r3 = the address after the last decrypted word (the caller stores it at
@      +0x44), r5 = c. +0x04 = m, +0x20 = c, +0x22 = c before the last word.
@      Uses +0x50 and +0x54 as scratch. Keeps r0, r2, r4, r6.
mb_decrypt:
	push {r2, r4, r6, lr}
	mov ip, r1	@ ip = the multiplier
	str r3, [r7, #0x54]	@ k
	ldr r3, [r7, #0x44]	@ r3 = the next word
	ldr r1, [r7, #0x38]	@ end of the received data
	subs r1, r1, r3
	asrs r1, r1, #2	@ words waiting
	ble mb_decrypt_return	@ none
	cmp r1, #0x89
	ble mb_decrypt_start
	movs r1, #0x89	@ at most 0x89
mb_decrypt_start:
	ldr r4, [r7, #4]	@ r4 = m
	ldrh r5, [r7, #0x20]	@ r5 = c
mb_decrypt_loop:
	str r1, [r7, #0x50]	@ words left (mb_crc_word uses r1)
	mov r1, ip
	muls r4, r1
	.inst.n 0x1C64	@ adds r4, r4, #1: m = m x multiplier + 1
	ldr r2, [r3, #0]	@ the word
	eors r2, r4
	negs r1, r3
	eors r2, r1
	ldr r1, [r7, #0x54]
	eors r2, r1	@ word xor m xor -address xor k
	stmia r3!, {r2}	@ decrypted, in place
	strh r5, [r7, #0x22]	@ c before this word
	bl mb_crc_word	@ c: update with this word
	ldr r1, [r7, #0x50]
	.inst.n 0x1E49	@ subs r1, r1, #1
	bne mb_decrypt_loop
	strh r5, [r7, #0x20]	@ c
	str r4, [r7, #4]	@ m
mb_decrypt_return:
	pop {r2, r4, r6, pc}
@ mb_master_send_wait: MultiBoot. Sends r0 and waits for the end of the
@ transfer (mb_master_wait). mb_master_send (multiboot.s) does a short delay,
@ sets SIODATA32 and SIOMLT_SEND = r0, and starts SIOCNT.
@ In:  r0 = the value, r6 = REG_SIODATA32, r7 = the MultiBoot parameters (+0x3A
@      is the SIOCNT value; 0 means multiplay, 0x2083).
@ Out: nothing. Clobbers r1.
mb_master_send_wait:
	push {lr}
	bl mb_master_send
	pop {r1}
	mov lr, r1
@ mb_master_wait: waits while SIOCNT bit 7 (start/busy) is set, that is, until
@ the serial transfer ends. In: r6 = REG_SIODATA32 (SIOCNT is +8).
@ Clobbers r1.
mb_master_wait:
	ldrh r1, [r6, #8]	@ SIOCNT
	lsrs r1, r1, #8	@ carry = bit 7
	bcs mb_master_wait
	bx lr
