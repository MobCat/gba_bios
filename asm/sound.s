@ sound.s 0x13C4-0x1927: the sound SWIs, part 1. All Thumb.
@   - Driver setup: SoundDriverInit, SoundDriverMode, SampleFreqSet, the DMA
@     on/off SWIs, SoundChannelClear.
@   - Music player SWIs: MusicPlayerOpen, Start, Stop, Continue, FadeOut.
@   - Helpers that the player uses: FadeOutBody, TrkVolPitSet, MidiKey2Freq.
@ Part 2 (the mixer, the song player and its command handlers) is sound_driver.s.
@
@ What it is
@   The BIOS copy of the Nintendo MP2000 sound driver ("m4a", "Sappy").
@   The SWIs are MP2000 functions with GBATEK names. The comment on each function
@   gives the MP2000 routine that it matches. Most match closely.
@   The differences from the m4a library that later games link in (noted where
@   they occur) suggest an earlier version (inferred).
@   SWIs 0x20-0x24 are undocumented in GBATEK ("SoundWhatever0-4"). This project
@   gave them the names in this source.
@
@ How it runs (the sound_driver.s header has the details)
@   Once:           SoundDriverInit(area) clears the work area (the "SoundArea")
@                   and stores its address at SOUND_AREA_PTR. It points DMA1 and
@                   DMA2 at FIFO A and B, from the two halves of its PCM buffer.
@                   It starts timer 0 at the sample rate (SampleFreqSet).
@                   SoundDriverMode changes the rate, channel count, volume and
@                   reverb.
@   Once:           MusicPlayerOpen(player, tracks, n) for each player. A player
@                   plays one song at a time on up to 16 tracks. The SoundArea
@                   calls the newest player (+0x20 function, +0x24 player). Each
@                   player calls the player opened before it (its +0x38, +0x3C).
@   Any time:       MusicPlayerStart(player, song). The song tracks start on the
@                   next frame. MusicPlayerStop, Continue and FadeOut act on a
@                   player.
@   VBlank IRQ:     Each frame, SoundDriverVSync (sound_driver.s) restarts the two
@                   sound DMAs at the top of the PCM buffer every pcmDmaPeriod
@                   frames.
@   After VBlank:   Each frame, SoundDriverMain (sound_driver.s) runs every player
@                   (MPlayMain: tempo, commands, notes onto channels). It also
@                   mixes one frame of every channel into the PCM buffer, just
@                   ahead of the DMA read position.
@   Between frames: Each timer 0 overflow plays a byte from FIFO A (right) and
@                   FIFO B (left). DMA1/DMA2 keep the FIFOs filled from the buffer.
@   The BIOS plays the boot chime this way. boot_intro (intro.s) calls
@   SoundDriverInit(0x03003B2C), SoundDriverMode(0x00940A00), MusicPlayerOpen
@   twice (6 tracks each), MusicPlayerStart, and SoundDriverMain each frame.
@   boot_irq (system.s) calls SoundDriverVSync on VBlank.
@
@ Locking
@   The SoundArea and each player have an ident word: 0x68736D53 ("Smsh" in
@   memory) when idle. A routine checks the ident, adds 1 to it while it works,
@   and writes "Smsh" back at the end. Other routines find the wrong ident and do
@   nothing. Thus an IRQ-time call (SoundDriverVSync) skips its work while
@   SoundDriverMain runs, and no routine re-enters a player.
@
@ 0x03007FC0
@   Every sound routine that finds the SoundArea loads this value and reads
@   [value + 0x30] = 0x03007FF0 (SOUND_AREA_PTR). No code uses the value without
@   the + 0x30 (checked: all seven places in this file). The literal pools
@   write it as SOUND_AREA_PTR - 0x30.
@
@ RAM
@   - SOUND_AREA_PTR.
@   - The SoundArea: 0xFB0 bytes, at the address given to SoundDriverInit
@     (0x03003B2C for the intro).
@   - Players (0x40 bytes) and tracks (0x50 bytes each), at the addresses given
@     to MusicPlayerOpen.
@   - One word on the stack of the caller, as scratch (SoundDriverInit,
@     SoundDriverVSyncOff).
@ I/O
@   - SOUNDCNT_H, SOUNDCNT_X, SOUNDBIAS bits 14-15 (SoundDriverInit,
@     SoundDriverMode).
@   - DMA1 and DMA2 SAD, DAD and CNT_H (SoundDriverInit, the VSyncOn/Off SWIs).
@   - TM0CNT_L/H (SampleFreqSet).
@   - VCOUNT (read only).
@   The code does not access SOUNDCNT_L (the PSG channels).
@
@ The SoundArea (MP2000 SoundInfo): 0xFB0 bytes. The offsets are the ones that
@ the code uses. (The GBATEK "SoundArea" listing is a summary without offsets.)
@   0x000 u32 ident            "Smsh" when set up and idle
@   0x004 u8  pcmDmaCounter    frames until SoundDriverVSync restarts the DMAs;
@                              also selects which frame to mix
@   0x005 u8  reverb           0-127, 0 = none (SoundDriverMode bits 0-6)
@   0x006 u8  maxChans         PCM channels mixed, 1-12 (8 after init)
@   0x007 u8  masterVolume     0-15 (15 after init)
@   0x008 u8  freq             sample rate index, 1-12 (4 after init)
@   0x00B u8  pcmDmaPeriod     number of whole frames that fit in 0x630 bytes
@   0x010 u32 pcmSamplesPerVBlank   samples mixed per frame (224 at rate 4)
@   0x014 u32 pcmFreq          sample rate in Hz (13379 at rate 4)
@   0x018 u32 divFreq          about 2^23 / pcmFreq: 1/pcmFreq for the mixer
@   0x01C ptr cgbChans         four CGB channels, 0x40 bytes each. 0 in the
@                              BIOS, which plays nothing on the PSG channels.
@   0x020 fn  MPlayMainHead    the main function of the newest player (MPlayMain), or 0
@   0x024 ptr musicPlayerHead  the newest player (the argument of MPlayMainHead)
@   0x028 fn  CgbSound         Hooks for the CGB (PSG) code of a game. Called by
@   0x02C fn  CgbOscOff          SoundDriverMain, TrackStop and ply_note.
@   0x030 fn  MidiKeyToCgbFreq   SoundDriverInit sets all four to DummyFunc,
@   0x03C fn  ExtVolPit          which only returns.
@   0x034 ptr MPlayJumpTable   command handlers 0xB1-0xCE: sound_jump_table
@   0x038 fn  plynote          note handler, 0xCF-0xFF: ply_note
@   0x050     chans[12]        PCM channels, 0x40 bytes each (sound_driver.s)
@   0x350 s8  pcm A[0x630]     mixed samples for FIFO A (right side), read by DMA1
@   0x980 s8  pcm B[0x630]     mixed samples for FIFO B (left side), read by DMA2
@   The code does not use 0x09-0x0A, 0x0C-0x0F and 0x40-0x4F.
@
@ A player (MP2000 MusicPlayerInfo): 0x40 bytes. MusicPlayerOpen clears it.
@   0x00 ptr songHeader       the song that plays
@   0x04 u32 status           Bit 31: paused or stopped. Other bits: one bit
@                             for each track that existed in the last tick.
@   0x08 u8  trackCount       number of tracks of this player, 1-16
@   0x09 u8  priority         the song priority; added to the track priority
@                             for each note
@   0x0A u8  cmd              sound_jump_table slot of the last handler
@   0x1C u16 tempoD           TEMPO byte x 2 (150 at start): beats per minute
@                             at 24 ticks per beat (inferred)
@   0x1E u16 tempoU           tempo scale, 0x100 = 1 (only MusicPlayerStart sets it)
@   0x20 u16 tempoI           tempoD x tempoU / 256: added to tempoC each frame
@   0x22 u16 tempoC           a tick runs each time this reaches 150
@   0x24 u16 fadeOI           fade-out: frames per step, 0 = no fade
@   0x26 u16 fadeOC           fade-out: frames until the next step
@   0x28 u16 fadeOV           fade-out: volume, from 0x100 down by 0x10 per step
@   0x2C ptr tracks           the tracks, 0x50 bytes each (sound_driver.s)
@   0x30 ptr tone             the song voice table, 12 bytes per voice
@   0x34 u32 ident            "Smsh" when opened and idle
@   0x38 fn  MPlayMainNext    The player opened before this one: its main
@   0x3C ptr musicPlayerNext  function and the player. MPlayMain calls it first.
@
@ A song header (data.s: song_intro and the others):
@   0x00      u8  trackCount
@   0x01      u8  not read by this code
@   0x02      u8  priority
@   0x03      u8  reverb (bit 7 set: MusicPlayerStart passes it to SoundDriverMode)
@   0x04      ptr the voice table
@   0x08 + 4n ptr the commands of track n

@ SWI 0x20
@
@ MusicPlayerOpen SWI 0x20: sets up a player and links it into the chain.
@ GBATEK: "SoundWhatever0", undocumented. Matches MP2000 MPlayOpen.
@ In:  r0 = the player (0x40 bytes), r1 = its tracks (0x50 bytes each),
@      r2 = number of tracks (below 1: does nothing; above 16: uses 16).
@ Does: clears the player (SoundMainBTM), then sets tracks (+0x2C), trackCount
@      (+0x08), status = 0x80000000 (paused), and the flags of each track = 0.
@      Then, if the SoundArea is idle, the player becomes the head of the chain
@      (SoundArea +0x20 = MPlayMain, +0x24 = this player). The player keeps the
@      old head in its +0x38/+0x3C, and its ident becomes "Smsh".
@      If the SoundArea is not set up, the SWI still clears the player. But it
@      does not link the player in and gives it no ident, so the other player
@      SWIs ignore it. (The later MP2000 MPlayOpen checks the SoundArea first.)
@ Out: nothing. The intro opens 0x030036EC and 0x0300390C, 6 tracks each.
MusicPlayerOpen:
	.thumb
	push {r4, r5, r7, lr}
	adds r4, r2, #0	@ r4 = track count
	adds r5, r1, #0	@ r5 = tracks
	adds r7, r0, #0	@ r7 = player
	cmp r2, #1
	blt open_return	@ no tracks: return
	cmp r4, #0x10
	ble open_clear_player
	movs r4, #0x10	@ at most 16
open_clear_player:
	adds r0, r7, #0
	bl SoundMainBTM	@ clear the player (0x40 bytes)
	str r5, [r7, #0x2C]	@ player.tracks
	ldr r0, mplay_status_paused	@ =0x80000000: status bit 31 (paused)
	strb r4, [r7, #8]	@ player.trackCount
	str r0, [r7, #4]	@ player.status = paused until MusicPlayerStart
	movs r0, #0
	b open_track_check
open_track_loop:	@ each track: flags = 0 (off)
	subs r1, r4, #1
	lsls r4, r1, #0x18
	lsrs r4, r4, #0x18
	strb r0, [r5, #0]
	adds r5, #0x50
open_track_check:
	cmp r4, #0
	bgt open_track_loop
	ldr r1, open_sound_area_base	@ =SOUND_AREA_PTR - 0x30
	ldr r4, open_smsh	@ =SOUND_IDENT: "Smsh"
	ldr r1, [r1, #0x30]	@ r1 = the SoundArea
	ldr r2, [r1, #0]
	cmp r2, r4
	bne open_return	@ not set up, or busy: return
	adds r2, #1
	str r2, [r1, #0]	@ lock the SoundArea
	ldr r2, [r1, #0x20]	@ main function of the current head
	cmp r2, #0
	beq open_link_head	@ none: this is the first player
	str r2, [r7, #0x38]	@ this player calls the old head first:
	ldr r2, [r1, #0x24]	@ its main function and its player
	str r2, [r7, #0x3C]
	str r0, [r1, #0x20]	@ (cleared, then set again below)
open_link_head:
	ldr r0, open_mplay_main	@ =MPlayMain + 1 (Thumb)
	str r7, [r1, #0x24]	@ new head: this player,
	str r0, [r1, #0x20]	@ run by MPlayMain
	str r4, [r1, #0]	@ unlock the SoundArea
	str r4, [r7, #0x34]	@ player.ident = "Smsh": ready
open_return:
	pop {r4, r5, r7}
	pop {r3}
	bx r3
	.balign 4
mplay_status_paused:
	.4byte 0x80000000	@ status bit 31: paused (a new player plays nothing)
open_sound_area_base:
	.4byte SOUND_AREA_PTR - 0x30	@ [this + 0x30] = SoundArea address
open_smsh:
	.4byte SOUND_IDENT	@ "Smsh": the ident of a SoundArea that is set up and idle
open_mplay_main:
	.4byte MPlayMain + 1	@ MPlayMain (Thumb): called by SoundDriverMain for players
@ SWI 0x21
@
@ MusicPlayerStart SWI 0x21: starts a song on a player.
@ GBATEK: "SoundWhatever1", undocumented. Matches MP2000 MPlayStart, without
@ the priority test of later versions: a new song always replaces the song that
@ plays.
@ In:  r0 = a player opened with MusicPlayerOpen, r1 = a song header.
@ Does: nothing unless the player ident is "Smsh". Else it sets:
@        songHeader = r1, status = 0 (playing), tone = the song voice table,
@        priority = the song priority, tempoD = tempoI = 150 (one tick per
@        frame), tempoU = 0x100, tempoC = 0, fadeOI = 0 (no fade).
@      For each track of the song, up to the player track count: TrackStop,
@      flags = 0xC0 (exists, start), cmdPtr = the song pointer for that track.
@      The other tracks of the player: TrackStop, flags = 0.
@      If bit 7 of the song reverb byte is set: SoundDriverMode(that byte),
@      which sets reverb to the low 7 bits.
@      On the next MPlayMain tick (sound_driver.s), the tracks are set up and
@      start to read commands.
@ Out: nothing. Clobbers r0-r3.
MusicPlayerStart:
	push {r4, r5, r6, r7, lr}
	adds r7, r0, #0	@ r7 = player
	ldr r0, [r0, #0x34]	@ player.ident
	ldr r3, start_smsh	@ =SOUND_IDENT
	adds r4, r1, #0	@ r4 = song header
	cmp r0, r3
	bne start_return	@ not idle: return
	adds r0, #1
	str r0, [r7, #0x34]	@ lock the player
	movs r1, #0
	str r1, [r7, #4]	@ status = 0: playing
	str r4, [r7, #0]	@ songHeader
	ldr r0, [r4, #4]
	str r0, [r7, #0x30]	@ tone = song voice table
	ldrb r0, [r4, #2]
	strb r0, [r7, #9]	@ priority = song priority
	movs r0, #0x96
	strh r0, [r7, #0x1C]	@ tempoD = 150
	strh r0, [r7, #0x20]	@ tempoI = 150: one tick per frame until a TEMPO
	movs r0, #0xFF
	adds r0, #1
	strh r0, [r7, #0x1E]	@ tempoU = 0x100
	strh r1, [r7, #0x22]	@ tempoC = 0
	strh r1, [r7, #0x24]	@ fadeOI = 0: no fade
	ldr r5, [r7, #0x2C]	@ r5 = track
	movs r6, #0	@ r6 = track number
	b start_track_check
start_track_loop:	@ each track of the song:
	adds r0, r7, #0
	adds r1, r5, #0
	bl TrackStop	@ silence its old notes
	movs r0, #0xC0
	strb r0, [r5, #0]	@ flags = exists + start
	lsls r0, r6, #2
	adds r0, r0, r4
	ldr r0, [r0, #8]
	str r0, [r5, #0x40]	@ cmdPtr = song track r6
	adds r5, #0x50
	adds r6, #1
start_track_check:
	ldrb r0, [r4, #0]	@ song track count
	cmp r6, r0
	bge start_unused_check
	ldrb r0, [r7, #8]	@ player track count
	cmp r0, r6
	bgt start_track_loop	@ while r6 is below both
	b start_unused_check
start_unused_loop:	@ each player track that the song does not use:
	adds r0, r7, #0
	adds r1, r5, #0
	bl TrackStop
	movs r0, #0
	strb r0, [r5, #0]	@ flags = 0: off
	adds r5, #0x50
	adds r6, #1
start_unused_check:
	ldrb r0, [r7, #8]
	cmp r0, r6
	bgt start_unused_loop
	ldrb r0, [r4, #3]	@ song reverb byte
	lsrs r1, r0, #8	@ carry = bit 7
	bcc start_unlock
	bl SoundDriverMode	@ reverb = bits 0-6 (the other fields are 0: unchanged)
start_unlock:
	ldr r0, start_smsh	@ =SOUND_IDENT
	str r0, [r7, #0x34]	@ unlock the player
start_return:
	pop {r4, r5, r6, r7}
	pop {r3}
	bx r3
	.balign 4, 0
	.balign 4
start_smsh:
	.4byte SOUND_IDENT	@ "Smsh": the ident of an idle player
@ SWI 0x22
@
@ MusicPlayerStop SWI 0x22: pauses a player and stops its notes.
@ GBATEK: "SoundWhatever2", undocumented. Matches MP2000 MPlayStop.
@ In:  r0 = the player. The SWI does nothing unless its ident is "Smsh".
@ Does: sets status bit 31 (paused) and calls TrackStop on every track. This
@      cuts off their notes at once, with no release.
@      The tracks keep their position in the song, so MusicPlayerContinue
@      continues from there with the next notes. The cut notes do not resume.
@ Out: nothing. Clobbers r0-r3.
MusicPlayerStop:
	push {r4, r5, r6, r7, lr}
	adds r7, r0, #0	@ r7 = player
	ldr r0, [r0, #0x34]
	ldr r6, stop_smsh	@ =SOUND_IDENT
	cmp r0, r6
	bne stop_return	@ not idle: return
	adds r0, #1
	str r0, [r7, #0x34]	@ lock the player
	ldr r0, [r7, #4]
	lsls r3, r6, #0x1F	@ 0x80000000 ("Smsh" has bit 0 set)
	orrs r0, r3
	str r0, [r7, #4]	@ status |= paused
	ldrb r5, [r7, #8]	@ r5 = tracks left
	ldr r4, [r7, #0x2C]	@ r4 = track
	b stop_track_check
stop_track_loop:
	adds r0, r7, #0
	adds r1, r4, #0
	bl TrackStop	@ stop its channels
	adds r4, #0x50
	subs r5, #1
stop_track_check:
	cmp r5, #0
	bgt stop_track_loop
	str r6, [r7, #0x34]	@ unlock the player
stop_return:
	pop {r4, r5, r6, r7}
	pop {r3}
	bx r3
	.balign 4, 0
	.balign 4
stop_smsh:
	.4byte SOUND_IDENT	@ "Smsh": ident of an idle player; bit 0 gives 0x80000000
@ SWI 0x23
@
@ MusicPlayerContinue SWI 0x23: resumes a paused player.
@ GBATEK: "SoundWhatever3", undocumented. Matches MP2000 MPlayContinue, but
@ does not lock the player while it works.
@ In:  r0 = the player. If its ident is "Smsh", the SWI clears status bit 31.
@      MPlayMain then runs the tracks again from the position where
@      MusicPlayerStop left them.
@ Out: nothing. Clobbers r1, r2.
MusicPlayerContinue:
	ldr r2, [r0, #0x34]
	ldr r1, continue_smsh	@ =SOUND_IDENT
	cmp r2, r1
	bne continue_return	@ not idle: return
	ldr r2, [r0, #4]
	str r1, [r0, #0x34]	@ (writes "Smsh" over "Smsh")
	lsls r2, r2, #1
	lsrs r2, r2, #1
	str r2, [r0, #4]	@ clear status bit 31: playing
continue_return:
	bx lr
	.balign 4
continue_smsh:
	.4byte SOUND_IDENT	@ "Smsh": the ident of an idle player
@ SWI 0x24
@
@ MusicPlayerFadeOut SWI 0x24: starts a fade-out on a player.
@ GBATEK: "SoundWhatever4", undocumented. Matches MP2000 m4aMPlayFadeOut, but
@ does not lock the player.
@ In:  r0 = the player, r1 = frames per step (16 bits). The SWI does nothing
@      unless the player ident is "Smsh".
@ Does: fadeOI = fadeOC = r1, fadeOV = 0x100. From the next frame, FadeOutBody
@      (called by MPlayMain) decreases the track volume in 16 steps of r1
@      frames each, then stops the tracks. The fade takes 16 x r1 frames.
@      r1 = 0 means no fade.
@ Out: nothing. Clobbers r1, r2.
MusicPlayerFadeOut:
	push {r7}
	ldr r7, [r0, #0x34]
	ldr r2, fadeout_smsh	@ =SOUND_IDENT
	cmp r7, r2
	bne fadeout_return	@ not idle: return
	strh r1, [r0, #0x26]	@ fadeOC = r1: frames until the first step
	strh r1, [r0, #0x24]	@ fadeOI = r1: frames per step
	movs r1, #0xFF
	adds r1, #1
	strh r1, [r0, #0x28]	@ fadeOV = 0x100: full volume
	str r2, [r0, #0x34]
fadeout_return:
	pop {r7}
	bx lr
	.balign 4, 0
	.balign 4
fadeout_smsh:
	.4byte SOUND_IDENT	@ "Smsh": the ident of an idle player
@ FadeOutBody: does one frame of the fade-out of a player.
@ MPlayMain calls it every frame that the player is not paused. It is also in
@ sound_jump_table (slot 32, for the library of a game).
@ Matches MP2000 FadeOutBody, fade-out only. Later versions can also fade in,
@ and can pause instead of stop.
@ In:  r0 = the player: its fadeOI (+0x24), fadeOC (+0x26), fadeOV (+0x28).
@ Does: nothing if fadeOI is 0. Else it decrements fadeOC. When fadeOC reaches
@      0, it subtracts 0x10 from fadeOV. Then:
@        - fadeOV 0 or less: TrackStop and flags = 0 on every track (the song
@          is over).
@        - else: fadeOC = fadeOI again. Each track that exists gets volX
@          (+0x13) = fadeOV / 4 (64 = full) and flags |= 3 (volume changed).
@          MPlayMain acts on these flags.
@      At the end, fadeOI stays set and fadeOC is 0, so the count continues from
@      0xFFFF. The tracks are already off, so nothing more happens.
@ Out: nothing. Clobbers r0-r3.
FadeOutBody:
	push {r4, r5, r6, r7, lr}
	adds r7, r0, #0	@ r7 = player
	ldrh r0, [r0, #0x24]	@ fadeOI
	cmp r0, #0
	beq fade_return	@ no fade
	ldrh r1, [r7, #0x26]
	subs r1, #1
	lsls r1, r1, #0x10
	lsrs r1, r1, #0x10
	strh r1, [r7, #0x26]	@ fadeOC - 1
	bne fade_return	@ no step yet
	ldrh r1, [r7, #0x28]
	subs r1, #0x10
	strh r1, [r7, #0x28]	@ fadeOV - 0x10
	lsls r1, r1, #0x10
	asrs r1, r1, #0x10
	cmp r1, #0
	bgt fade_set_volumes	@ still above 0: set the volumes
	ldrb r5, [r7, #8]	@ faded out: stop every track
	ldr r4, [r7, #0x2C]
	movs r6, #0
	b fade_stop_check
fade_stop_loop:
	adds r0, r7, #0
	adds r1, r4, #0
	bl TrackStop
	strb r6, [r4, #0]	@ flags = 0: the track is over
	adds r4, #0x50
	subs r5, #1
fade_stop_check:
	cmp r5, #0
	bgt fade_stop_loop
fade_return:
	pop {r4, r5, r6, r7}
	pop {r3}
	bx r3
fade_set_volumes:
	strh r0, [r7, #0x26]	@ fadeOC = fadeOI: frames until the next step
	ldrb r1, [r7, #8]	@ r1 = tracks left
	ldr r0, [r7, #0x2C]	@ r0 = track
	b fade_volume_check
fade_volume_loop:
	ldrb r2, [r0, #0]
	lsrs r3, r2, #8	@ carry = flags bit 7 (track exists)
	bcc fade_volume_next
	ldrh r3, [r7, #0x28]
	lsrs r3, r3, #2
	strb r3, [r0, #0x13]	@ volX = fadeOV / 4
	movs r3, #3
	orrs r2, r3
	strb r2, [r0, #0]	@ flags |= 3: volume changed
fade_volume_next:
	adds r0, #0x50
	subs r1, #1
fade_volume_check:
	cmp r1, #0
	bgt fade_volume_loop
	b fade_return
@ TrkVolPitSet: calculates the volume and pitch of a track from its settings.
@ Callers: MPlayMain, for a track whose flags request it; ply_note, for each
@ note. Also in sound_jump_table (slot 33).
@ Matches an earlier version of TrkVolPitSet in MP2000: it adds modM to the
@ volume, where later versions multiply by it.
@ In:  r0 = the player (only passed to ExtVolPit), r1 = the track.
@ Does: if flags bit 0 (volume) is set:
@        x = vol x volX / 32 (+ modM if modT is 1)
@        pan y = 2 x pan + panX (+ modM if modT is 2), limited to -128..127
@        volMR (+0x10, right) = (y + 128) x x / 256
@        volML (+0x11, left)  = (127 - y) x x / 256
@        Both are cut to 8 bits. Full volume, centre: vol 127 and volX 64 give
@        x = 254, volMR 127 and volML 126.
@      if flags bit 2 (pitch) is set, in 1/256ths of a semitone:
@        p = bend x bendRange x 4 + tune x 4 + (keyShift + keyShiftX) x 256
@            + pitX (+ modM x 16 if modT is 0)
@        keyM (+0x08) = p / 256, pitM (+0x09) = p mod 256
@        Thus BEND at full is bendRange semitones, and TUNE at full is one
@        semitone.
@      Then it calls SoundArea.ExtVolPit(player, track). This is DummyFunc
@      (does nothing) unless a game has set it. Last, it clears flags bits 0
@      and 2. The channels get the new values from MPlayMain, which examines
@      bits 1 and 3.
@ Out: nothing. Clobbers r0-r3.
TrkVolPitSet:
	push {r4, r5, r7, lr}
	ldrb r5, [r1, #0]	@ r5 = track flags
	adds r7, r1, #0	@ r7 = track
	lsrs r1, r5, #1	@ carry = bit 0: calculate the volume?
	bcc trkvolpit_pitch
	ldrb r1, [r7, #0x12]	@ vol, 0-127
	ldrb r2, [r7, #0x13]	@ volX, the fade: 64 = full
	ldrb r4, [r7, #0x18]	@ r4 = modT: the LFO target
	muls r1, r2
	lsrs r2, r1, #5	@ r2 = x = vol x volX / 32
	cmp r4, #1
	bne trkvolpit_pan
	movs r3, #0x16
	ldrsb r1, [r7, r3]	@ modT 1 (volume): x + modM
	adds r2, r1, r2
trkvolpit_pan:
	movs r3, #0x14
	ldrsb r1, [r7, r3]	@ pan, -64..63
	lsls r1, r1, #1
	movs r3, #0x15
	ldrsb r3, [r7, r3]	@ panX: drum pan (ply_note)
	adds r1, r1, r3	@ r1 = y = 2 x pan + panX
	cmp r4, #2
	bne trkvolpit_pan_clamp
	movs r3, #0x16
	ldrsb r3, [r7, r3]	@ modT 2 (pan): y + modM
	adds r1, r3, r1
trkvolpit_pan_clamp:	@ limit y to -128..127:
	movs r3, #0x80
	cmn r1, r3
	bge trkvolpit_pan_max
	negs r1, r3
	b trkvolpit_right
trkvolpit_pan_max:
	cmp r1, #0x7F
	ble trkvolpit_right
	movs r1, #0x7F
trkvolpit_right:
	adds r3, r1, #7
	adds r3, #0x79	@ y + 128
	muls r3, r2
	lsrs r3, r3, #8
	lsls r3, r3, #0x18
	lsrs r3, r3, #0x18	@ cut to 8 bits, so the 0xFF limit below never applies
	cmp r3, #0xFF
	bls trkvolpit_store_right
	movs r3, #0xFF
trkvolpit_store_right:
	strb r3, [r7, #0x10]	@ volMR, right = (y + 128) x x / 256
	movs r3, #0x7F
	subs r1, r3, r1
	muls r1, r2
	lsrs r1, r1, #8
	lsls r1, r1, #0x18
	lsrs r1, r1, #0x18	@ cut to 8 bits (as above)
	cmp r1, #0xFF
	bls trkvolpit_store_left
	movs r1, #0xFF
trkvolpit_store_left:
	strb r1, [r7, #0x11]	@ volML, left = (127 - y) x x / 256
trkvolpit_pitch:
	lsrs r1, r5, #3	@ carry = bit 2: calculate the pitch?
	bcc trkvolpit_call_ext
	movs r3, #0xE
	ldrsb r1, [r7, r3]	@ bend, -64..63
	ldrb r2, [r7, #0xF]	@ bendRange, in semitones
	muls r1, r2
	lsls r1, r1, #2	@ bend x range x 4
	movs r3, #0xC
	ldrsb r2, [r7, r3]	@ tune, -64..63
	lsls r2, r2, #2	@ x 4
	adds r1, r1, r2
	movs r3, #0xA
	ldrsb r2, [r7, r3]	@ keyShift, in semitones
	lsls r2, r2, #8
	adds r1, r1, r2
	movs r3, #0xB
	ldrsb r2, [r7, r3]	@ keyShiftX, in semitones: 0 unless a game sets it
	lsls r2, r2, #8
	adds r1, r1, r2
	ldrb r2, [r7, #0xD]	@ pitX, in 1/256ths: 0 unless a game sets it
	adds r1, r1, r2
	ldrb r2, [r7, #0x18]
	cmp r2, #0
	bne trkvolpit_store_pitch
	movs r3, #0x16
	ldrsb r2, [r7, r3]	@ modT 0 (pitch): + modM x 16
	lsls r2, r2, #4
	adds r1, r2, r1
trkvolpit_store_pitch:
	asrs r2, r1, #8
	strb r2, [r7, #8]	@ keyM: whole semitones to add to a key
	strb r1, [r7, #9]	@ pitM: the 1/256ths to add
trkvolpit_call_ext:
	ldr r2, trkvolpit_sound_area_base	@ =SOUND_AREA_PTR - 0x30
	adds r1, r7, #0
	ldr r2, [r2, #0x30]	@ the SoundArea
	ldr r2, [r2, #0x3C]	@ SoundArea.ExtVolPit
	bl call_via_r2	@ call it (call_via_r2 is bx r2): r0 = player, r1 = track
	ldrb r0, [r7, #0]
	movs r3, #5
	bics r0, r3
	strb r0, [r7, #0]	@ clear flags bits 0 and 2: done
	pop {r4, r5, r7}
	pop {r3}
	bx r3
	.balign 4
trkvolpit_sound_area_base:
	.4byte SOUND_AREA_PTR - 0x30	@ [this + 0x30] = SoundArea address
@ SWI 0x1A
@
@ SoundDriverInit SWI 0x1A: initialises the sound driver.
@ Matches MP2000 SoundInit (the part without CGB channels).
@ GBATEK: initialises the sound driver. Call it once, at start-up, with the
@   work area already reserved. It cannot run twice, even on two areas.
@   r0 = the work area (SoundArea).
@ In:  r0 = the work area: 0xFB0 bytes, word-aligned (CpuSet fills words).
@ Does:
@   - DMA1 and DMA2 off.
@   - SOUNDCNT_X = 0x8F (sound on).
@   - SOUNDCNT_H = 0xA90E: PSG at 100%, A and B at 100%, A to the right, B to
@     the left, both on timer 0, both FIFOs reset.
@   - SOUNDBIAS bits 14-15 = 1 (8 bits at 65.536 kHz). The bias level stays.
@   - DMA1: buffer A (area + 0x350) to FIFO A. DMA2: buffer B (area + 0x980) to
@     FIFO B.
@   - SOUND_AREA_PTR = r0.
@   - Clears the whole area. Then maxChans = 8, masterVolume = 15, plynote =
@     ply_note, the four hooks = DummyFunc (does nothing), the jump table =
@     sound_jump_table.
@   - SampleFreqSet(rate 4): 13379 Hz. This starts timer 0 and the DMAs.
@   - Last, ident = "Smsh". From then on, the other SWIs work.
@   It does not access SOUNDCNT_L (the enables and volume of the PSG channels).
@ Out: nothing. Uses the stack word [sp] of the caller (the pushed r3) as the zero
@      value for the CpuSet fill. Takes up to a frame (SampleFreqSet waits).
SoundDriverInit:
	push {r3, r7, lr}
	adds r7, r0, #0	@ r7 = the work area
	ldr r1, init_dma_base	@ =REG_DMA1DAD: base for the DMA registers
	movs r0, #0
	strh r0, [r1, #6]	@ DMA1CNT_H = 0: DMA1 off
	strh r0, [r1, #0x12]	@ DMA2CNT_H = 0: DMA2 off
	ldr r0, init_sound_base	@ =REG_SOUNDCNT_L: base for the sound registers
	movs r2, #0x8F
	strh r2, [r0, #4]	@ SOUNDCNT_X: bit 7, sound on (bits 0-3 are read-only)
	ldr r2, init_soundcnt_h	@ =0x0000A90E
	strh r2, [r0, #2]	@ SOUNDCNT_H: A right, B left, timer 0, FIFOs reset
	ldrb r2, [r0, #9]	@ SOUNDBIAS bits 8-15
	lsls r2, r2, #0x1A
	lsrs r2, r2, #0x1A	@ keep bits 8-13 (the bias level)
	movs r3, #0x40
	orrs r2, r3	@ bits 14-15 = 1: 8 bits at 65.536 kHz
	movs r3, #0x35
	lsls r3, r3, #4	@ r3 = 0x350: offset of buffer A
	strb r2, [r0, #9]
	adds r2, r7, r3
	str r2, [r0, #0x3C]	@ DMA1SAD (0x040000BC) = buffer A
	ldr r0, init_fifo_a	@ =REG_FIFO_A
	movs r3, #0x13
	lsls r3, r3, #7	@ r3 = 0x980 = 0x350 + 0x630: offset of buffer B
	str r0, [r1, #0]	@ DMA1DAD = FIFO A
	adds r0, r7, r3
	str r0, [r1, #8]	@ DMA2SAD = buffer B
	ldr r0, init_fifo_b	@ =REG_FIFO_B
	ldr r2, init_clear_area_cpuset	@ =0x050003EC: a number, CpuSet r2 (see the pool)
	str r0, [r1, #0xC]	@ DMA2DAD = FIFO B
	ldr r0, init_sound_area_base	@ =SOUND_AREA_PTR - 0x30
	str r7, [r0, #0x30]	@ SOUND_AREA_PTR = the work area
	movs r0, #0
	str r0, [sp, #0]	@ zero word for the fill (in the slot of the pushed r3)
	mov r0, sp
	adds r1, r7, #0
	bl CpuSet	@ fill the area with it: 0x3EC words (0xFB0 bytes)
	movs r0, #8
	strb r0, [r7, #6]	@ maxChans = 8
	movs r0, #0xF
	strb r0, [r7, #7]	@ masterVolume = 15
	ldr r0, init_ply_note	@ =ply_note + 1 (Thumb)
	str r0, [r7, #0x38]	@ plynote
	ldr r0, init_dummy_func	@ =DummyFunc + 1: returns immediately
	str r0, [r7, #0x28]	@ CgbSound
	str r0, [r7, #0x2C]	@ CgbOscOff
	str r0, [r7, #0x30]	@ MidiKeyToCgbFreq
	str r0, [r7, #0x3C]	@ ExtVolPit
	ldr r0, init_jump_table	@ =sound_jump_table
	str r0, [r7, #0x34]	@ MPlayJumpTable
	movs r0, #1
	lsls r0, r0, #0x12	@ 0x40000: rate 4 (SoundDriverMode bits 16-19)
	bl SampleFreqSet	@ 13379 Hz. Starts timer 0 and the DMAs.
	ldr r0, init_smsh	@ =SOUND_IDENT
	str r0, [r7, #0]	@ ident = "Smsh": ready
	pop {r3, r7}
	pop {r3}
	bx r3
	.balign 4
init_dma_base:
	.4byte REG_DMA1DAD	@ DMA base: +6 DMA1CNT_H, +8 DMA2SAD, +0xC DMA2DAD, +0x12 _CNT_H
init_sound_base:
	.4byte REG_SOUNDCNT_L	@ sound base: +2 SOUNDCNT_H, +4 _X, +8 SOUNDBIAS, +0x3C DMA1SAD
init_soundcnt_h:
	.4byte 0x0000A90E	@ SOUNDCNT_H: full volumes, A right, B left, timer 0, FIFOs reset
init_fifo_a:
	.4byte REG_FIFO_A	@ DMA1 destination: FIFO A (right side)
init_fifo_b:
	.4byte REG_FIFO_B	@ DMA2 destination: FIFO B (left side)
init_sound_area_base:
	.4byte SOUND_AREA_PTR - 0x30	@ the code sets SOUND_AREA_PTR at + 0x30
init_clear_area_cpuset:
	.4byte 0x050003EC	@ a number: CpuSet r2 0x050003EC, 32-bit fill, 0x3EC words
init_ply_note:
	.4byte ply_note + 1	@ ply_note (Thumb): the SoundArea note handler
init_dummy_func:
	.4byte DummyFunc + 1	@ a function that returns immediately: for the four hooks
init_jump_table:
	.4byte sound_jump_table	@ the command handlers, 0xB1-0xCE, and six helpers
init_smsh:
	.4byte SOUND_IDENT	@ "Smsh": the SoundArea ident after setup
@ DummyFunc: returns immediately (bx lr).
@ SoundDriverInit sets the SoundArea hooks CgbSound, CgbOscOff, MidiKeyToCgbFreq
@ and ExtVolPit to DummyFunc, so the BIOS does nothing for the PSG channels.
@ SoundInit in MP2000 does the same with its DummyFunc.
DummyFunc:
	bx lr
@ SampleFreqSet: sets the sample rate. Matches MP2000 SampleFreqSet.
@ Called by SoundDriverInit and SoundDriverMode. Also in sound_jump_table
@ (slot 30).
@ In:  r0 = a SoundDriverMode value: bits 16-19 = the rate, 1-12. The rate is
@      not checked: 0 would read the halfword before the table, 13-15 past it.
@ Does: sets these SoundArea fields:
@        freq (+0x08)                = the rate
@        pcmSamplesPerVBlank (+0x10) = sound_pcm_samples_per_vblank[rate - 1]
@        pcmDmaPeriod (+0x0B)        = 0x630 / samples: whole frames in half
@                                      the buffer
@        pcmFreq (+0x14)             = (597275 x samples + 5000) / 10000:
@                                      samples x 59.7275 (frames per second),
@                                      rounded. 13379 Hz at rate 4 (224 samples).
@        divFreq (+0x18)             = (2^24 / pcmFreq + 1) / 2, about
@                                      2^23 / pcmFreq
@      Then it stops timer 0 and sets its reload = 65536 - 280896 / samples. A
@      frame is 280896 cycles, so the timer overflows once per sample.
@      It turns on the sound DMAs (SoundDriverVSyncOn). Then it waits for the
@      start of line 159, the last visible line, and starts timer 0
@      (TM0CNT_H = 0x80: on, every cycle). A start at that point keeps the
@      samples in step with the frames.
@ Out: nothing. Takes up to a frame. Clobbers r0-r3.
SampleFreqSet:
	push {r4, r7, lr}
	ldr r1, sfs_sound_area_base	@ =SOUND_AREA_PTR - 0x30
	movs r3, #0xF
	lsls r3, r3, #0x10
	ands r0, r3	@ bits 16-19
	ldr r7, [r1, #0x30]	@ r7 = the SoundArea
	lsrs r0, r0, #0x10
	strb r0, [r7, #8]	@ freq = the rate, 1-12
	ldr r1, sfs_samples_table	@ =sound_pcm_samples_per_vblank
	lsls r0, r0, #1
	adds r0, r0, r1
	subs r0, #0x20
	ldrh r0, [r0, #0x1E]	@ table[rate - 1] (-0x20 + 0x1E = -2 bytes)
	movs r1, #0x63
	lsls r1, r1, #4	@ r1 = 0x630: half the PCM buffer
	adds r4, r0, #0	@ r4 = samples per frame
	str r0, [r7, #0x10]	@ pcmSamplesPerVBlank
	bl thumb_DivArm	@ r0 = r1 / r0
	strb r0, [r7, #0xB]	@ pcmDmaPeriod = 0x630 / samples
	ldr r0, sfs_frame_hz_x10000	@ =0x00091D1B: 597275
	ldr r3, sfs_rounding_5000	@ =0x00001388: 5000
	muls r0, r4
	adds r1, r0, r3	@ 597275 x samples + 5000
	lsls r0, r3, #1	@ / 10000
	bl thumb_DivArm
	movs r1, #1
	lsls r1, r1, #0x18	@ 2^24
	str r0, [r7, #0x14]	@ pcmFreq, in Hz
	bl thumb_DivArm	@ 2^24 / pcmFreq
	adds r0, #1
	asrs r0, r0, #1
	str r0, [r7, #0x18]	@ divFreq = (that + 1) / 2
	ldr r4, sfs_tm0cnt	@ =REG_TM0CNT
	movs r0, #0
	strh r0, [r4, #2]	@ TM0CNT_H = 0: timer 0 off
	ldr r0, [r7, #0x10]
	ldr r1, sfs_cycles_per_frame	@ =0x00044940: 280896
	bl thumb_DivArm	@ 280896 / samples: cycles per sample
	movs r1, #1
	lsls r1, r1, #0x10
	subs r0, r1, r0
	strh r0, [r4, #0]	@ TM0CNT_L: reload 0x10000 - that
	bl SoundDriverVSyncOn	@ turn on the sound DMAs
	movs r0, #1
	lsls r0, r0, #0x1A	@ r0 = 0x04000000, the I/O base
sfs_wait_not_159:
	ldrb r1, [r0, #6]	@ VCOUNT
	cmp r1, #0x9F
	beq sfs_wait_not_159	@ wait while VCOUNT is 159,
sfs_wait_159:
	ldrb r1, [r0, #6]
	cmp r1, #0x9F
	bne sfs_wait_159	@ then until it is 159 again: the start of the line
	movs r0, #0x80
	strh r0, [r4, #2]	@ TM0CNT_H = 0x80: timer 0 on, every cycle
	pop {r4, r7}
	pop {r3}
	bx r3
	.balign 4
sfs_sound_area_base:
	.4byte SOUND_AREA_PTR - 0x30	@ [this + 0x30] = SoundArea address
sfs_samples_table:
	.4byte sound_pcm_samples_per_vblank	@ samples per frame for rates 1-12, halfwords
sfs_frame_hz_x10000:
	.4byte 0x00091D1B	@ 597275: frames per second (59.7275 Hz) x 10000
sfs_rounding_5000:
	.4byte 0x00001388	@ 5000, to round the / 10000. Doubled, it is the 10000.
sfs_tm0cnt:
	.4byte REG_TM0CNT	@ timer 0: its overflows clock both FIFOs (SOUNDCNT_H)
sfs_cycles_per_frame:
	.4byte 0x00044940	@ 280896: CPU cycles in a frame (228 lines x 1232)
@ SWI 0x1B
@
@ SoundDriverMode SWI 0x1B: sets the sound driver mode.
@ Matches MP2000 m4aSoundMode.
@ GBATEK, r0:
@   bits 0-6    reverb (0-127, default 0; ignored if bit 7 is 0)
@   bits 8-11   PCM channels (1-12, default 8)
@   bits 12-15  master volume (1-15, default 15)
@   bits 16-19  sample rate (1-12 = 5734, 7884, 10512, 13379, 15768, 18157,
@               21024, 26758, 31536, 36314, 40137, 42048 Hz; default 4 = 13379)
@   bits 20-23  D/A bits (8-11 = 9-6 bits; default 9 = 8 bits)
@   bits 24-31  unused
@ Checked against the code:
@   - A field that is 0 does not change the setting.
@   - The SWI sets reverb to bits 0-6 when bits 0-7 are not all 0. Bit 7 is not
@     necessary, and bit 7 alone sets reverb 0 (off).
@   - A new channel count also stops all 12 PCM channels (flags = 0).
@   - The SWI masks the D/A field with 0xB. Bits 0-1 of the result become
@     SOUNDBIAS bits 14-15 (8 -> 0: 9 bits at 32.768 kHz ... 11 -> 3: 6 bits
@     at 262.144 kHz).
@   - A new rate turns off the sound DMAs (SoundDriverVSyncOff, which clears the
@     PCM buffer). Then the SWI calls SampleFreqSet, which turns them on again.
@ Does: nothing unless the SoundArea ident is "Smsh".
@ Out: nothing. Clobbers r0-r3. The intro uses 0x00940A00: 10 channels, rate 4,
@   8-bit D/A.
SoundDriverMode:
	push {r4, r5, r7, lr}
	ldr r1, mode_sound_area_base	@ =SOUND_AREA_PTR - 0x30
	ldr r5, mode_smsh	@ =SOUND_IDENT
	ldr r7, [r1, #0x30]	@ r7 = the SoundArea
	ldr r1, [r7, #0]
	cmp r1, r5
	bne mode_return	@ not set up, or busy: return
	adds r1, #1
	str r1, [r7, #0]	@ lock
	lsls r1, r0, #0x18
	lsrs r1, r1, #0x18	@ bits 0-7
	beq mode_channels
	lsls r1, r1, #0x19
	lsrs r1, r1, #0x19
	strb r1, [r7, #5]	@ reverb = bits 0-6
mode_channels:
	movs r1, #0xF
	lsls r1, r1, #8
	ands r1, r0	@ bits 8-11
	beq mode_volume
	lsrs r1, r1, #8
	strb r1, [r7, #6]	@ maxChans
	movs r1, #0xC	@ and turn off all 12 channels:
	movs r3, #0
	adds r2, r7, #7
	adds r2, #0x49	@ r2 = area + 0x50, channel 0
mode_channel_off_loop:
	strb r3, [r2, #0]	@ statusFlags = 0
	adds r2, #0x40
	subs r1, #1
	bne mode_channel_off_loop
mode_volume:
	movs r1, #0xF
	lsls r1, r1, #0xC
	ands r1, r0	@ bits 12-15
	beq mode_da_bits
	lsrs r1, r1, #0xC
	strb r1, [r7, #7]	@ masterVolume
mode_da_bits:
	movs r1, #0xB
	lsls r1, r1, #0x14
	ands r1, r0	@ bits 20-23, but not 22
	beq mode_rate
	movs r3, #3
	lsls r3, r3, #0x14
	ldr r2, mode_sound_base	@ =REG_SOUNDCNT_L: SOUNDBIAS is +8
	ands r1, r3	@ bits 20-21
	ldrb r3, [r2, #9]	@ SOUNDBIAS bits 8-15
	lsrs r1, r1, #0xE	@ to bits 6-7 of that byte
	lsls r3, r3, #0x1A
	lsrs r3, r3, #0x1A	@ keep bits 8-13 (the bias level)
	orrs r1, r3
	strb r1, [r2, #9]	@ SOUNDBIAS bits 14-15: the resolution
mode_rate:
	movs r4, #0xF
	lsls r4, r4, #0x10
	ands r4, r0	@ bits 16-19
	beq mode_unlock
	bl SoundDriverVSyncOff	@ DMAs off, buffer cleared (it accepts "Smsh" + 1)
	adds r0, r4, #0
	bl SampleFreqSet	@ new rate. DMAs and timer 0 on again.
mode_unlock:
	str r5, [r7, #0]	@ unlock
mode_return:
	pop {r4, r5, r7}
	pop {r3}
	bx r3
	.balign 4
mode_sound_area_base:
	.4byte SOUND_AREA_PTR - 0x30	@ [this + 0x30] = SoundArea address
mode_smsh:
	.4byte SOUND_IDENT	@ "Smsh": the SoundArea ident when idle
mode_sound_base:
	.4byte REG_SOUNDCNT_L	@ sound base: the SOUNDBIAS high byte is at +9
@ SWI 0x1E
@
@ SoundChannelClear SWI 0x1E: stops all direct sound (PCM) channels.
@ Matches MP2000 SoundClear, with a slip.
@ GBATEK: clears all direct sound channels and stops the sound. It may not work
@   after a library that extends the driver is linked in.
@ Does: nothing unless the SoundArea ident is "Smsh". Else it sets statusFlags
@      = 0 in all 12 PCM channels, so they stop at once.
@      Then, only if the SoundArea has CGB channels (+0x1C; the BIOS leaves it
@      0), it calls CgbOscOff(1), (2), (3) and (4). After the loop, it clears
@      one byte, at cgbChans + 0x100. SoundClear in the m4a library instead
@      clears the flags of each CGB channel inside the loop. That looks like a
@      bug here (not run).
@      The tracks still list the stopped channels. MPlayMain unlinks them on its
@      next tick.
@ Out: nothing. Clobbers r0-r3.
SoundChannelClear:
	push {r4, r5, r6, r7, lr}
	ldr r0, clear_sound_area_base	@ =SOUND_AREA_PTR - 0x30
	ldr r6, clear_smsh	@ =SOUND_IDENT
	ldr r7, [r0, #0x30]	@ r7 = the SoundArea
	ldr r0, [r7, #0]
	cmp r0, r6
	bne clear_return	@ not set up, or busy: return
	adds r0, #1
	str r0, [r7, #0]	@ lock
	adds r0, r7, #7
	movs r1, #0xC
	adds r0, #0x49	@ r0 = area + 0x50, channel 0
clear_channel_loop:	@ 12 channels:
	movs r2, #0
	strb r2, [r0, #0]	@ statusFlags = 0 (off)
	adds r0, #0x40
	subs r1, #1
	cmp r1, #0
	bgt clear_channel_loop
	ldr r5, [r7, #0x1C]	@ cgbChans
	cmp r5, #0
	beq clear_unlock	@ none (as in the BIOS)
	movs r4, #1	@ CGB channels 1-4:
clear_cgb_loop:
	lsls r0, r4, #0x18
	lsrs r0, r0, #0x18
	ldr r1, [r7, #0x2C]	@ CgbOscOff
	bl call_via_r1	@ call it (call_via_r1 is bx r1): r0 = the channel
	adds r4, #1
	adds r5, #0x40
	cmp r4, #4
	ble clear_cgb_loop
	movs r2, #0
	strb r2, [r5, #0]	@ once, after the loop: cgbChans + 0x100
clear_unlock:
	str r6, [r7, #0]	@ unlock
clear_return:
	pop {r4, r5, r6, r7}
	pop {r3}
	bx r3
	.balign 4, 0
	.balign 4
clear_sound_area_base:
	.4byte SOUND_AREA_PTR - 0x30	@ [this + 0x30] = SoundArea address
clear_smsh:
	.4byte SOUND_IDENT	@ "Smsh": the SoundArea ident when idle
@ SWI 0x28
@
@ SoundDriverVSyncOff SWI 0x28: stops the sound DMAs and clears the PCM buffer.
@ Probably an earlier form of m4aSoundVSyncOff in MP2000. That version also
@ clears the DMA repeat bits and locks with + 10.
@ GBATEK: stops the sound DMA. Use it when VBlank interrupts stop and
@   SoundDriverVSync cannot be called every frame. Else the DMA continues past
@   the buffer and causes noise.
@ Does: only if the SoundArea ident is "Smsh" or "Smsh" + 1 (so that
@      SoundDriverMode can call it while it holds the lock):
@        DMA1CNT_H = DMA2CNT_H = 0 (both off), pcmDmaCounter = 0, and clears
@        the PCM buffer (both halves, 0xC60 bytes).
@      Timer 0 continues to run. The SWI restores the ident to its old value.
@ Out: nothing. Uses the stack word [sp] of the caller (the pushed r3) as the zero
@      value for the CpuSet fill. Clobbers r0-r3.
SoundDriverVSyncOff:
	push {r3, r7, lr}
	ldr r0, vsyncoff_sound_area_base	@ =SOUND_AREA_PTR - 0x30
	ldr r3, vsyncoff_smsh	@ =SOUND_IDENT
	ldr r7, [r0, #0x30]	@ r7 = the SoundArea
	ldr r0, [r7, #0]
	cmp r0, r3
	bcc vsyncoff_return	@ below "Smsh": return
	adds r3, #1
	cmp r0, r3
	bhi vsyncoff_return	@ above "Smsh" + 1: return
	adds r0, #1
	str r0, [r7, #0]	@ lock
	movs r0, #0
	ldr r1, vsyncoff_dma_base	@ =REG_DMA1DAD: base for the DMA registers
	movs r3, #0x35
	strh r0, [r1, #6]	@ DMA1CNT_H = 0: off
	strh r0, [r1, #0x12]	@ DMA2CNT_H = 0: off
	strb r0, [r7, #4]	@ pcmDmaCounter = 0: the next SoundDriverVSync restarts
	lsls r3, r3, #4	@ 0x350
	adds r1, r7, r3	@ r1 = the PCM buffer
	str r0, [sp, #0]	@ zero word for the fill
	mov r0, sp
	ldr r2, vsyncoff_clear_pcm_cpuset	@ =0x05000318: a number, CpuSet r2 (see the pool)
	bl CpuSet	@ fill 0x318 words: both halves
	ldr r0, [r7, #0]
	subs r0, #1
	str r0, [r7, #0]	@ unlock: restore the old ident
vsyncoff_return:
	pop {r3, r7}
	pop {r3}
	bx r3
	.balign 4, 0
	.balign 4
vsyncoff_sound_area_base:
	.4byte SOUND_AREA_PTR - 0x30	@ [this + 0x30] = SoundArea address
vsyncoff_smsh:
	.4byte SOUND_IDENT	@ "Smsh": SoundArea ident when idle (+ 1 also accepted)
vsyncoff_dma_base:
	.4byte REG_DMA1DAD	@ DMA1 destination. DMA1CNT_H: +6, DMA2CNT_H: +0x12.
vsyncoff_clear_pcm_cpuset:
	.4byte 0x05000318	@ a number: CpuSet r2 0x05000318, 32-bit fill, 0x318 words
@ SWI 0x29
@
@ SoundDriverVSyncOn SWI 0x29: restarts the sound DMAs.
@ The DMA part of m4aSoundVSyncOn in MP2000, which also resets the frame count
@ and the lock: probably an earlier form.
@ GBATEK: restarts the sound DMA stopped by SoundDriverVSyncOff. After it, a
@   VBlank must occur within 2/60 s, and SoundDriverVSync must be called.
@ Does: DMA1CNT_H = DMA2CNT_H = 0xB600: on, sound FIFO timing ("special"),
@      32-bit, repeat, source incrementing. When a DMA turns on, it reloads its
@      source, so both DMAs start at the top of their half of the PCM buffer.
@      It does not read or change the ident. SampleFreqSet also calls it.
@ Out: nothing. Clobbers r0, r1.
SoundDriverVSyncOn:
	movs r1, #0x5B
	ldr r0, vsyncon_dma_base	@ =REG_DMA1DAD: base for the DMA registers
	lsls r1, r1, #9	@ 0xB600
	strh r1, [r0, #6]	@ DMA1CNT_H
	strh r1, [r0, #0x12]	@ DMA2CNT_H
	bx lr
	.balign 4
vsyncon_dma_base:
	.4byte REG_DMA1DAD	@ DMA1 destination. DMA1CNT_H: +6, DMA2CNT_H: +0x12.
@ SWI 0x1F
@
@ MidiKey2Freq SWI 0x1F: calculates the channel frequency for a MIDI key.
@ Matches MP2000 MidiKeyToFreq.
@ GBATEK: the value for the frequency of a channel that plays wave data at a
@   MIDI key, with a fine adjustment (256 = a semitone). r0 = the WaveData,
@   r1 = the key, r2 = the fine adjustment. Returns r0.
@ In:  r0 = the WaveData (the SWI reads only wave.freq, +4), r1 = key 0-178
@      (above 178: uses 178 with fine 255), r2 = fine, 0-255.
@ Out: r0 = the frequency in Hz: the value for channel +0x20.
@ How: each key has a byte in sound_scale_table. The high nibble is an octave
@      shift s, and the low nibble is a semitone n:
@        f(key) = sound_freq_table[n] >> s = 2^31 x 2^(n/12) >> s
@               = 2^(17 + key/12)
@      The result is wave.freq x g / 2^32, where
@        g = f(key) + (f(key + 1) - f(key)) x fine / 256
@      (a linear interpolation between the two keys). thumb_umul_high (intro.s:
@      umull, the high word) does both multiplications. MP2000 calls it
@      umul3232H32.
@      Thus the result is wave.freq x 2^((key - 180) / 12). With the GBATEK
@      wave.freq = sample rate x 2^((180 - the recorded key) / 12), the
@      recorded key plays at the sample rate.
@      The SWI finds sound_freq_table at sound_scale_table + 0xB4. The two
@      tables must stay together, in that order (data.s).
@ GBATEK: the SWI reads wave.freq without the BIOS read protection, so it can
@   read any BIOS word. This is the known way to dump the BIOS.
@ Clobbers r1-r3.
MidiKey2Freq:
	push {r4, r5, r6, r7, lr}
	lsls r2, r2, #0x18	@ fine x 2^24: fine / 256 as a fraction of 2^32
	adds r7, r0, #0	@ r7 = the WaveData
	cmp r1, #0xB2
	ble midikey_lookup
	ldr r2, midikey_fine_max	@ =0xFF000000: fine 255
	movs r1, #0xB2	@ key 178
midikey_lookup:
	ldr r0, midikey_scale_table	@ =sound_scale_table
	ldrb r3, [r0, r1]	@ byte for the key
	lsls r4, r3, #0x1C
	lsrs r4, r4, #0x1C	@ low nibble: the semitone
	lsls r4, r4, #2
	adds r5, r0, #7
	adds r5, #0xAD	@ r5 = sound_scale_table + 0xB4 = sound_freq_table
	ldr r4, [r5, r4]
	lsrs r6, r3, #4	@ high nibble: the octave shift
	lsrs r4, r6	@ r4 = f(key)
	adds r0, r0, r1
	ldrb r0, [r0, #1]	@ byte for the next key
	lsls r1, r0, #0x1C
	lsrs r1, r1, #0x1C
	lsls r1, r1, #2
	ldr r1, [r5, r1]
	lsrs r0, r0, #4
	lsrs r1, r0	@ r1 = f(key + 1)
	subs r0, r1, r4
	adds r1, r2, #0
	bl thumb_umul_high	@ (f(key + 1) - f(key)) x fine / 256
	adds r1, r0, r4	@ + f(key)
	ldr r0, [r7, #4]	@ wave.freq
	bl thumb_umul_high	@ x that / 2^32
	pop {r4, r5, r6, r7}
	pop {r3}
	bx r3
	.balign 4
midikey_fine_max:
	.4byte 0xFF000000	@ fine 255 (x 2^24), for a key above 178
midikey_scale_table:
	.4byte sound_scale_table	@ a byte per key 0-179; sound_freq_table at +0xB4
