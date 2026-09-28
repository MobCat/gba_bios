@ multiboot.s 0x28CE-0x30AF: MultiBoot, both ends of it. One GBA (the master) sends a
@ program over the link cable to other GBAs (the slaves) that have no cartridge, or that
@ have Select and Start held.
@ All of it comes from the code and GBATEK ("BIOS Multi Boot", "SIO ... Mode", "GBA
@ Cartridge Header"). None of it has been run: there is no link cable to run it with.
@
@ THE MASTER: MultiBoot, SWI 0x25. The sending game does the first part of the protocol
@ itself (GBATEK: the SWI "covers only 45%"): it finds the slaves and sends them the
@ 0xC0-byte header, the palette and the handshake. The SWI sends the rest: the length,
@ the program (encrypted one word at a time) and a CRC. It returns 0 if every slave
@ echoed every unit and agreed on the CRC, else 1. It is one loop that polls SIOCNT.
@
@ THE SLAVE: the intro. boot_intro (intro.s) calls intro_link_poll once per frame, during
@ the animation and during the wait after it. The serial IRQ goes (boot_irq, system.s)
@ to boot_serial_irq, which jumps to the current receive state. The work is split:
@   intro_link_poll (each frame)   selects a link mode and sets up the port, enables the
@                                  serial IRQ, times out, decrypts the received data,
@                                  calculates the CRC (JOY Bus: also compares it),
@                                  checks the header, and shows the received logo.
@                                  At the end it returns non-zero: boot_intro stores
@                                  that in SOFT_RESET_FLAG, and SoftReset starts
@                                  0x02000000.
@   the receive states (each IRQ)  reply to the master and store what it sends in EWRAM.
@ The slave keeps all its data in a work area at 0x0300000C (see below): r7 in
@ intro_link_poll and the functions it calls, r3 in the states.
@
@ LINK MODES. The slave cannot know which mode the master uses. Until a transfer starts,
@ intro_link_poll tries each mode for some frames, in the order 1, 2, 0, 1, ...:
@   0  JOY Bus    RCNT = 0xC000. A GameCube is the master (GBATEK: a GBA cannot be one).
@                 The JOY Bus commands move the data, not SIOCNT. 7 frames.
@   1  Multiplay  SIOCNT = 0x6003: 16-bit multi-player, 115200 bps, IRQ. Up to 3 slaves.
@                 SIOCNT bits 4-5 give the number of this slave. 31 frames.
@   2  Normal     SIOCNT = 0x5088: 32-bit normal, external clock, IRQ. One slave. 7 frames.
@ A 62xx from the master (JOY Bus: the reset command) resets the frame count, so the
@ slave stays in the mode while the master talks to it. After a transfer starts
@ (+0D = 3), the slave never changes the mode again.
@
@ THE PROTOCOL, multiplay and normal (GBATEK "Multiboot Transfer Protocol"; the code at
@ both ends agrees with it). Each transfer carries 16 bits from the master and 16 bits
@ back from each slave. The reply on a line arrives in the same transfer as the master
@ value, so the slave writes it after the line before.
@ In normal mode, the master value is the low half of SIODATA32 and the reply is the
@ high half (for the program, the master value is all 32 bits).
@ x = the bit of this slave (2, 4, 8); y = the slave mask of the master;
@ pp = palette_data; cc = the random client_data of a slave; hh = handshake_data;
@ rr = the random byte of a slave; uu = the new cc that the slave makes after the
@ last 63pp (+17).
@   master       slave        what
@   6200         FFFF, 0000   FFFF until the slave is in this mode, then 0000
@   6200         720x         the slave has seen a 62xx (GBATEK: the master sends 15)
@   610y         720x         the header comes next
@   header       NN0x         0x60 halfwords, to 0x02000000 up; NN = 0x60 down to 0x01
@   6200         000x         the header is complete
@   620y         720x
@   63pp         720x..73cc   the palette; repeated until every slave replies 73cc
@   64hh         73uu         hh = 0x11 + cc1 + cc2 + cc3 (low byte)
@   (the MultiBoot SWI starts at the next row)
@   llll         73rr         llll = length / 4 - 0x34
@   program      nnnn         encrypted, to 0x020000C0 up; nnnn = the low half of the
@                             address where the unit goes
@   0065         nnnn, 0074.. 0074 while the slave is still decrypting and checking
@   0065         0075         ready
@   0066         0075
@   CRC          CRC          the master and each slave must send the same CRC
@
@ THE ENCRYPTION AND THE CRC (GBATEK pseudo code; the same at both ends):
@   m starts as dword(pp, cc1, cc2, cc3). Then, for each 32-bit word of the program:
@     m    = m * mul + 1
@     sent = word ^ m ^ -(its address, 0x020000C0 up) ^ k
@     crc: 32 steps of { bit = (crc ^ word) & 1; crc >>= 1; word >>= 1; if bit: crc ^= x }
@   Then 32 more steps over f = dword(hh, rr1, rr2, rr3). For a missing slave, cc and rr
@   are 0xFF. The CRC is over the plain words. The header is not encrypted and is not in
@   the CRC.
@   mode       CRC start   x        mul                k
@   normal     0xC387      0xC37B   0x6F646573 "sedo"  0x43202F2F "// C"
@   multiplay  0xFFF8      0xA517   0x6F646573 "sedo"  0x6465646F "oded"
@   JOY Bus    0x15A0      0xA1C1   0x6177614B "Kawa"  0x20796220 " by "
@   (JOY Bus: m starts as the random word of the slave instead. The five words,
@   stored as bytes, spell "// Coded by Kawasedo". multiboot_key is "Kawasedo".)
@
@ HANDING OVER. When all of the program is in and decrypted (JOY Bus: and its CRC
@ matched), mb_slave_set_entry:
@   - writes an ARM branch over the entry of the header at 0x02000000: b 0x020000C0
@     (JOY Bus: b 0x020000E0)
@   - writes the boot mode at 0x020000C4 (1 JOY Bus, 2 normal, 3 multiplay)
@   - writes the slave number at 0x020000C5, except in JOY Bus (GBATEK "GBA Cartridge
@     Header")
@   - checks the received header with check_cart_header, as for a cartridge.
@ Multiplay and normal then still exchange the CRC with the master (mb_slave_wait_ready
@ and after). When the transfer is done and the received logo has been on screen for
@ 120 frames (mb_slave_logo), intro_link_poll returns 5. boot_intro stores that in
@ SOFT_RESET_FLAG, calls RegisterRamReset(0xDE) (everything except EWRAM and the SIO
@ registers) and returns to SoftReset. SoftReset jumps to 0x02000000 in ARM state,
@ System mode.
@
@ THE SLAVE WORK AREA, 0x0300000C-0x03000063. It is in the game area of IWRAM. Only
@ the intro uses it, and RegisterRamReset at the start of boot_intro zeroes it. The BIOS
@ copy of the cartridge header follows at 0x03000088.
@   +00 word   a random word, made every frame from +4C. Bits 5-7 = 101. Bit 15 is set
@              when the intro is over and waiting (MULTIBOOT_FLAG = 1) or when the
@              header copy is blank. Byte 1 is the cc that the slave sends, byte 2 its
@              rr. JOY Bus: sent to the master whole (^ "sedo").
@   +04 word   m, the key: dword(pp, cc1, cc2, cc3). JOY Bus: the random word.
@   +08 word   JOY Bus: the decoded length word. Its byte 2 (+0A) is the palette byte in
@              every mode: bit 7 set = show the received logo, and boot.
@   +0C byte   frames left in this link mode
@   +0D byte   3 when a transfer has started: the mode is then fixed
@   +0E byte   the link mode: 0 JOY Bus, 1 multiplay, 2 normal
@   +0F byte   the phase (see below)
@   +10 byte   y, the slave mask of the master (from its 62yy)
@   +11 byte   0xFF when mb_slave_check_crc has matched the CRC. intro_link_poll then
@              sets it to 4.
@   +12 byte   frames left for the received logo before the boot, from 120
@   +13 byte   5 when +12 is 0: the result of mb_slave_logo
@   +14 byte   the phase of the palette fade
@   +15 byte   x, the bit of this slave: 1 << its number
@   +16 byte   the slave number: 1-3 in multiplay, 1 in normal
@   +17 byte   the cc that this slave sent last
@   +18 word   pp, cc1, cc2, cc3: the start value of m
@   +1C word   f = hh, rr1, rr2, rr3: the last word of the CRC
@   +20 hword  the CRC so far. The mode setup sets its start value.
@   +22 hword  the CRC before the last word (JOY Bus compares the last word with it)
@   +24 hword  frames to song_multiboot: counts down from 60; the song starts at 57
@   +30 word   frames left without a serial IRQ before the timeout (11 at each IRQ)
@   +34 word   the receive state: where boot_serial_irq jumps
@   +38 word   where the next received unit goes, 0x02000000 up
@   +3C word   the end of the current part: 0x020000C0 (the header), then the program end
@   +40 word   JOY Bus: the program end, from the length word
@   +44 word   decrypted up to this address, 0x020000C0 up
@   +48 word   header halfwords still to come
@   +4C word   the random seed: * 0x6177614B ("Kawa") + 1 each frame. It starts at 0 at
@              every boot, so the only random part is the frame in which the master starts.
@   +50 word   mb_decrypt: the count of words to decrypt
@   +54 word   mb_decrypt: k
@ The phase (+0F) selects the work of intro_link_poll:
@   0  set up the port for the mode (and reset the pointers)                  -> 1
@   1  enable the serial IRQ; set the first receive state                     -> 2
@   2  the receive states reply to the master; no work each frame
@   3  a transfer is running (a state set it): time out, decrypt, check       -> 4
@   4  received and checked: the logo, then the boot
@ An error anywhere sets phase 0, and the mode starts again from the beginning.
@
@ THE RECEIVE STATES. On each serial IRQ, boot_serial_irq jumps to [+34] with r0 = that
@ address, r1 = the received value, r2 = REG_SIODATA32, r3 = 0x0300000C.
@ A state writes its reply and stores the address of the next state in +34 (with adr, so
@ each state is word aligned). A state that stores r0 stays the current state.
@ An unexpected value goes to mb_slave_reset: phase 0, state mb_slave_idle.
@ Multiplay and normal (r1 = the master value, 16 bits):
@   state                 r1    action                             next state
@   mb_slave_wait_62      62yy  its number, x and y; reply 720x    -> mb_slave_wait_61
@                         else  ignored                            -> the same
@   mb_slave_wait_61      62yy  reply 720x                         -> the same
@                         610y  phase 3; reply 600x                -> mb_slave_recv_header
@   mb_slave_recv_header        each halfword to +38; reply NN0x   -> the same
@                               after the 0x60th: reply 000x       -> mb_slave_wait_63
@   mb_slave_wait_63      62yy  y; reply 720x                      -> the same
@                         61yy  the header again from the start    -> mb_slave_recv_header
@                         63pp  pp and cc1-cc3; reply 73cc         -> mb_slave_wait_64
@   mb_slave_wait_64      63pp  pp and cc1-cc3 again; reply 73cc   -> the same
@                         64hh  hh; reply 73rr                     -> mb_slave_recv_length
@   mb_slave_recv_length  llll  rr1-rr3 and the end; reply 00C0    -> mb_slave_recv_program
@   mb_slave_recv_program       unit to +38; reply +38 (low half)  -> the same
@                               after the last unit                -> mb_slave_wait_ready
@   mb_slave_wait_ready   0065  still decrypting: reply 0074       -> the same
@                         0065  decrypted and checked: reply 0075  -> mb_slave_wait_66
@   mb_slave_wait_66      0065  reply 0075                         -> the same
@                         0066  reply the CRC of this slave        -> mb_slave_check_crc
@   mb_slave_check_crc    CRC   CRC and hh must match; +11 = 0xFF  -> mb_slave_idle
@ JOY Bus (r1 = the JOYCNT flags: 1 reset command, 2 received, 4 sent):
@   mb_joy_wait_reset     1     JOY_TRANS = random word ^ "sedo";  -> mb_joy_wait_read
@                               JOYSTAT = 0x10
@   mb_joy_wait_read      4     the master has read it: phase 3    -> mb_joy_recv_length
@   mb_joy_recv_length    2     the length word from JOY_RECV;     -> mb_joy_recv_program
@                               JOYSTAT = 0x20
@   mb_joy_recv_program   2     word to +38; toggle JOYSTAT bit 4  -> the same
@                         2     after the last: a reply word in    -> mb_slave_idle
@                               JOY_TRANS; JOYSTAT = 0
@ mb_slave_idle is `bx lr`: the state when there is nothing to do (before the first
@ state, after an error, and after the last state).
@
@ I/O. The code accesses most serial registers from REG_SIODATA32 (0x04000120):
@   +00 SIODATA32 (normal) / SIOMULTI0-1 (multiplay)   +04 SIOMULTI2   +06 SIOMULTI3
@   +08 SIOCNT   +0A SIOMLT_SEND   +10 KEYINPUT   +14 RCNT   +20 JOYCNT
@   +30 JOY_RECV   +34 JOY_TRANS   +38 JOYSTAT
@ The master writes SIODATA32, SIOMLT_SEND and SIOCNT, and reads the four DMAxCNT_H.
@ The slave writes most of the serial registers above (intro_link_poll lists them),
@ and IE, IF, IME.
@ RAM: the master writes only its MultiBootParam. The slave writes its work area, EWRAM
@ from 0x02000000, the logo in VRAM and OBJ palette (functions in header.s) and
@ INTRO_FLAG (decode_cart_logo).
@
@ HELPERS in sound_driver.s, just before this file:
@   mb_crc_word          the CRC, 32 steps
@   mb_decrypt           decrypts the received words and adds them to the CRC
@   mb_master_send_wait  sends r0, then waits
@   mb_master_wait       waits for the SIOCNT start bit to clear

@ MultiBoot SWI 0x25: the master end of the transfer (the protocol is in the header).
@ In:  r0 -> MultiBootParam (GBATEK: 0x4C bytes; the BIOS uses 0x44). The fields that
@            the caller fills in (GBATEK names), as the code reads them:
@              +14 byte     handshake_data hh: normal mode only. Multiplay takes hh from
@                           SIOMULTI0: the last 64hh that the game sent.
@              +19 3 bytes  client_data cc1-cc3
@              +1C byte     palette_data pp
@              +1E byte     client_bit: bits 1-3 = slaves 1-3 found (normal: bit 1 only)
@              +20 word     boot_srcp: the program from its byte 0xC0, e.g. 0x080000C0
@              +24 word     boot_endp: the end of the program
@      r1    the transfer mode (GBATEK: undocumented):
@              0  normal, 32 bits, 256 kHz
@              1  multiplay, 16 bits, 115200 bps
@              2  normal, 32 bits, 2 MHz
@            Above 2 fails. The compare is signed: a negative r1 takes the
@            normal-mode path, and its low bits are ORed into SIOCNT (+3A).
@            The SIO must already be in that mode: the game set it up in its own part.
@ Out: r0 = 0 if every slave echoed every unit and sent back the master CRC, else 1.
@ Fails at once, before it sends anything, if:
@      - r0 or r0 + 0xFF is below 0x02000000 (strictly: has bits 25-27 clear;
@        cpuset_check_range)
@      - r0 is not in 0x02000000-0x027FFFFF or 0x03000000-0x037FFFFF (bits 28-31 are
@        not tested)
@      - the length, (boot_endp - boot_srcp) & 0x3FFF8, is 0, or boot_srcp or its end
@        is below 0x02000000 (the same test)
@      - a DMA channel is enabled
@      - a slave in client_bit did not last reply 73xx.
@ The SWI uses the other fields of the struct as scratch:
@              +00  m
@              +04  f
@              +08  the slave mask (bit 0 = slave 1)
@              +0C  the length, then the end
@              +10  the pointer
@              +38  the CRC
@              +3A  the SIOCNT value that starts a normal-mode transfer (0 = multiplay)
@              +3C  the high half of the word being sent (multiplay)
@              +3E  x
@              +40  k
@ On return, +00-13 and +38-43 are all set to the result, 0 or 1. This also occurs
@      when the struct address was refused, so the SWI writes to a bad r0 anyway.
@ Runs with IRQ and FIQ off in System mode (multiboot_set_cpsr). swi_return (vectors.s)
@      restores the CPSR of the caller. Waits 1/16 s before the length, then as long as
@      the transfer takes. There is no IRQ and no timeout (the master drives the clock,
@      so each of its transfers ends).
@ Not checked: the GBATEK limits "multiple of 10h, minimum 100h, max 3FF40h". A length
@      below 0xD0 makes llll negative, and the slave refuses it (mb_slave_recv_length).
MultiBoot:
	.thumb
	push {r1, r3, r4, r5, r6, r7, lr}
	movs r3, #0xDF	@ CPSR: System mode, IRQ and FIQ off
	adr r2, multiboot_set_cpsr
	bl mb_bx_r2	@ bx r2: to ARM for the msr, then back
	adds r7, r0, #0	@ r7 = MultiBootParam, for the rest of the SWI
	movs r4, #0xFF
	bl cpuset_check_range	@ r0 to r0 + 0xFF: eq = in the BIOS
	beq mb_fail_far
	lsrs r4, r7, #0x14
	movs r3, #0xE8
	ands r3, r4	@ address bits 23, 25, 26, 27...
	cmp r3, #0x20	@ ...must be 0, 1, 0, 0: EWRAM or IWRAM
	bne mb_fail_far
	movs r4, #0	@ multiplay: +3A = 0
	cmp r1, #1
	beq mb_set_siocnt
	cmp r1, #2
	bgt mb_fail_far	@ mode above 2: fail
	ldr r4, mb_normal_siocnt_crc	@ =0xC3871089. Low half 0x1089: SIOCNT for a normal transfer
	orrs r4, r1	@ mode 2 sets bit 1: the 2 MHz clock (0x108B)
mb_set_siocnt:
	strh r4, [r7, #0x3A]	@ +3A = SIOCNT to start a normal transfer (0 = multiplay)
	ldr r0, [r7, #0x20]	@ boot_srcp
	str r0, [r7, #0x10]	@ +10 = the pointer
	ldr r4, [r7, #0x24]
	subs r4, r4, r0	@ boot_endp - boot_srcp
	ldr r3, mb_length_mask	@ =0x0003FFF8: the length mask (a multiple of 8, below 256 KiB)
	ands r4, r3
	str r4, [r7, #0xC]	@ +0C = the length
	bl cpuset_check_range	@ boot_srcp and the length: eq = length 0, or in the BIOS
	beq mb_fail_far
	ldr r4, mb_dma_regs	@ =REG_DMA0SAD: the base for the four DMAxCNT_H
	ldrh r0, [r4, #0xA]	@ DMA0CNT_H
	ldrh r2, [r4, #0x16]	@ DMA1CNT_H
	orrs r0, r2
	ldrh r2, [r4, #0x22]	@ DMA2CNT_H
	orrs r0, r2
	ldrh r2, [r4, #0x2E]	@ DMA3CNT_H
	orrs r0, r2
	lsrs r0, r0, #0x10	@ carry = bit 15 (enable) of any of them
	bcs mb_fail_far	@ a DMA is running: fail
	ldr r6, mb_sio_base	@ =REG_SIODATA32. r6 = the SIO base, for the rest of the SWI
	ldrb r0, [r7, #0x1E]	@ client_bit
	lsls r0, r0, #0x1C
	lsrs r0, r0, #0x1D	@ bits 1-3 to bits 0-2: the slave mask
	ldrh r1, [r6, #0]	@ SIOMULTI0: the last value that the master sent, 64hh
	ldrh r2, [r7, #0x3A]
	cmp r2, #0
	beq mb_set_mask	@ multiplay: keep the three bits, and hh from SIOMULTI0
	lsls r0, r0, #0x1F
	lsrs r0, r0, #0x1F	@ normal: slave 1 only
	ldrb r1, [r7, #0x14]	@ normal: hh is handshake_data
mb_set_mask:
	strb r0, [r7, #8]	@ +08 = the slave mask
	strb r1, [r7, #4]	@ +04 byte 0 = hh: the first byte of f
	ldr r3, mb_normal_siocnt_crc	@ =0xC3871089
	lsrs r3, r3, #0x10	@ 0xC387: the normal-mode CRC start
	ldr r1, mb_crc_x_normal	@ =0x0000C37B: normal-mode x of the CRC
	cmp r2, #0
	ldr r4, mb_key_k_normal	@ =0x43202F2F: normal-mode k, "// C"
	bne mb_set_crc_key
	ldr r1, mb_crc_x_multi	@ =0x0000A517: multiplay x
	ldr r3, mb_length_mask	@ =0x0003FFF8. Multiplay CRC start (as a halfword: 0xFFF8)
	ldr r4, mb_key_k_multi	@ =0x6465646F: multiplay k, "oded"
mb_set_crc_key:
	strh r1, [r7, #0x3E]	@ +3E = x
	strh r3, [r7, #0x38]	@ +38 = the CRC
	str r4, [r7, #0x40]	@ +40 = k
	ldr r1, [r7, #0x18]
	str r1, [r7, #0]	@ +00 = the word at +18: cc1-cc3 in bytes 1-3...
	ldrb r1, [r7, #0x1C]
	strb r1, [r7, #0]	@ ...and pp in byte 0: m = dword(pp, cc1, cc2, cc3)
	adds r4, r6, #0
mb_check_73_loop:	@ each slave in the mask: its last reply (to 64hh) must be 73xx
	lsrs r0, r0, #1
	bcc mb_check_73_skip
	ldrb r1, [r4, #3]	@ the high byte of its SIOMULTIn (normal: of the SIODATA32 high half)
	cmp r1, #0x73
	bne mb_fail_far
mb_check_73_next:
	.inst.n 0x1CA4	@ adds r4, r4, #2
	b mb_check_73_loop
mb_fail_far:	@ for branches that cannot reach the failure exit (mb_fail)
	b mb_fail
mb_check_73_skip:
	bne mb_check_73_next	@ more slaves in the mask
	ldr r5, [r7, #0xC]
	lsrs r0, r5, #2
	subs r0, #0x34	@ llll = length / 4 - 0x34
	ldr r1, [r7, #0x10]
	adds r1, r1, r5
	str r1, [r7, #0xC]	@ +0C = the end: boot_srcp + length
	ldr r1, mb_length_mask	@ =0x0003FFF8, used as a delay count: 4 cycles each, 1/16 s
mb_delay_loop:	@ GBATEK: "Wait 1/16 seconds at master side"
	.inst.n 0x1E49	@ subs r1, r1, #1
	bne mb_delay_loop
	bl mb_master_send_wait	@ send llll and wait; each slave replies 73rr
	ldrh r1, [r6, #2]	@ SIOMULTI1 / SIODATA32 high: 73rr from slave 1
	strb r1, [r7, #5]	@ rr1: byte 1 of f
	ldrh r1, [r6, #4]	@ SIOMULTI2
	ldrh r2, [r6, #6]	@ SIOMULTI3
	ldrh r3, [r7, #0x3A]
	cmp r3, #0
	beq mb_store_rr
	movs r1, #0xFF	@ normal: no slaves 2 and 3
	movs r2, #0xFF
mb_store_rr:
	strb r1, [r7, #6]	@ rr2
	strb r2, [r7, #7]	@ rr3: +04 = f = dword(hh, rr1, rr2, rr3)
	movs r4, #2	@ r4: 2 = sending the program (then 1, 0: the two 0065s)
	mov ip, r4	@ ip = 2 until the last check, when it is 0 (see mb_echo_skip)
	ldr r3, [r7, #0x10]	@ r3 = the pointer into the program
mb_send_loop:	@ each unit: a word in normal mode, a halfword in multiplay
	ldr r1, [r7, #0x20]
	subs r1, r1, r3
	lsrs r1, r1, #2	@ carry = bit 1 of the offset: the pointer is in the middle of a word
	ldrh r0, [r7, #0x3C]	@ middle of a word (multiplay): send the saved high half
	bcs mb_send_unit
	ldr r2, [r3, #0]	@ the next word of the program
	ldrh r0, [r7, #0x3E]	@ x
	ldrh r5, [r7, #0x38]	@ the CRC
	bl mb_crc_word	@ add the plain word to the CRC (clobbers r1, r2, r6)
	strh r5, [r7, #0x38]
	ldr r1, [r7, #0]
	ldr r0, mb_key_mul	@ =0x6F646573 ("sedo"): the multiplier of the key
	muls r1, r0
	.inst.n 0x1C49	@ adds r1, r1, #1
	str r1, [r7, #0]	@ m = m * 0x6F646573 + 1
	ldr r0, [r3, #0]
	eors r0, r1	@ word ^ m
	ldr r1, [r7, #0x20]
	subs r2, r3, r1	@ the offset from boot_srcp
	ldr r1, mb_program_dest	@ =EWRAM + 0xC0: where the slave puts the program
	adds r2, r2, r1	@ where this word goes in the slave
	negs r1, r2
	ldr r2, [r7, #0x40]
	eors r1, r2
	eors r0, r1	@ ^ -(that address) ^ k: the word to send
	lsrs r2, r0, #0x10
	strh r2, [r7, #0x3C]	@ +3C = its high half, for the next unit in multiplay
	ldr r6, mb_sio_base	@ =REG_SIODATA32 again: mb_crc_word used r6
mb_send_unit:	@ r0 = the next value to send
	bl mb_master_wait	@ wait for the last transfer to end
	ldr r1, [r7, #0x20]
	cmp r1, r3
	beq mb_send_next	@ the first unit: the last transfer was llll (already checked)
	mov lr, r4	@ save r4 in lr (lr is on the stack)
	subs r4, r3, r1
	.inst.n 0x1EA4	@ subs r4, r4, #2
	ldrh r1, [r7, #0x3A]
	cmp r1, #0
	beq mb_echo_address
	.inst.n 0x1EA4	@ subs r4, r4, #2
mb_echo_address:
	ldr r1, mb_program_dest	@ =EWRAM + 0xC0: the start of the program in the slave
	adds r4, r4, r1	@ r4 = the address of the unit just sent: each slave must echo it
mb_check_echo:	@ compare the slave replies with the low half of r4 (also the CRC, at the end)
	ldrb r2, [r7, #8]
	adds r5, r6, #0
mb_echo_loop:
	lsrs r2, r2, #1
	bcc mb_echo_skip
	ldrh r1, [r5, #2]	@ SIOMULTIn (normal: the SIODATA32 high half)
	eors r1, r4
	lsls r1, r1, #0x10
	bne mb_fail	@ a slave did not echo it: fail
mb_echo_next:
	.inst.n 0x1CAD	@ adds r5, r5, #2
	b mb_echo_loop
mb_echo_skip:
	bne mb_echo_next	@ more slaves
	mov r4, lr
	cmp r2, ip	@ r2 is 0, so this tests ip = 0: the CRC check...
	bne mb_send_next
	movs r0, #0	@ ...passed: success
	b mb_return
mb_send_next:
	bl mb_master_send	@ send r0
	cmp r4, #0
	beq mb_wait_75	@ the second 0065 is sent: wait for 0075
	.inst.n 0x1C9B	@ adds r3, r3, #2
	ldrh r1, [r7, #0x3A]
	cmp r1, #0
	beq mb_send_check_end
	.inst.n 0x1C9B	@ adds r3, r3, #2
mb_send_check_end:
	cmp r4, #2
	bne mb_send_65
	ldr r1, [r7, #0xC]
	cmp r1, r3
	bne mb_send_loop	@ more of the program
mb_send_65:	@ at the end: send 0065 twice (r4 = 1, then 0) and check the echoes
	movs r0, #0x65
	.inst.n 0x1E64	@ subs r4, r4, #1
	b mb_send_unit
mb_wait_75:	@ wait for 0075 from every slave; r0 = the value just sent, 0x65 or 0x66
	movs r4, #1	@ r4 = 1: all ready so far
	bl mb_master_wait
	ldrb r2, [r7, #8]
	adds r3, r6, #0
mb_wait_75_loop:
	lsrs r2, r2, #1
	bcc mb_wait_75_skip
	ldrh r1, [r3, #2]
	cmp r1, #0x75	@ 0075: ready
	beq mb_wait_75_next
	cmp r0, #0x65
	bne mb_fail	@ after 0066, any value other than 0075: fail
	cmp r1, #0x74	@ 0074: still decrypting
	bne mb_fail
	movs r4, #0	@ not all ready
mb_wait_75_next:
	.inst.n 0x1C9B	@ adds r3, r3, #2
	b mb_wait_75_loop
mb_wait_75_skip:
	bne mb_wait_75_next
	cmp r0, #0x66
	beq mb_send_crc	@ 0066 was sent, and all replied 0075
	cmp r4, #0
	beq mb_wait_75_send	@ not ready: 0065 again
	movs r0, #0x66	@ all ready: 0066
mb_wait_75_send:
	bl mb_master_send
	b mb_wait_75
mb_send_crc:
	cmp r4, #0
	beq mb_fail	@ a guard: r4 cannot be 0 (a reply other than 0075 after 0066 failed above)
	ldrh r0, [r7, #0x3E]	@ x
	ldrh r5, [r7, #0x38]	@ the CRC
	ldr r2, [r7, #4]	@ f
	bl mb_crc_word	@ the last 32 steps of the CRC, over f
	ldr r6, mb_sio_base	@ =REG_SIODATA32 again, after mb_crc_word
	adds r0, r5, #0
	bl mb_master_send_wait	@ send the CRC; the slaves send theirs
	movs r1, #0
	mov ip, r1	@ ip = 0: the check below is the last
	adds r4, r0, #0	@ each reply must be the CRC
	b mb_check_echo
mb_fail:	@ failure
	movs r0, #1
mb_return:	@ r0 = the result: write it over the scratch fields and return it
	str r0, [r7, #0x38]
	str r0, [r7, #0x3C]
	str r0, [r7, #0x40]	@ +38-43
	adds r1, r7, #0
	adds r1, #0x14
mb_clear_loop:
	stmia r7!, {r0}	@ +00-13
	cmp r1, r7
	bne mb_clear_loop
	pop {r1, r3, r4, r5, r6, r7}
	pop {r2}	@ the return address
@ bx r2. The return of MultiBoot (just above) falls through into it.
@ MultiBoot also calls multiboot_set_cpsr (ARM) with `bl mb_bx_r2`, r2 = multiboot_set_cpsr.
mb_bx_r2:
	bx r2
@ The master sends r0 and starts the transfer.
@ It does not wait for the transfer to end (mb_master_wait does that). Steps:
@   1. Wait about 36 us (GBATEK: after each transfer "a 36us delay"; 150 loops of 4
@      cycles).
@   2. Write r0 to SIODATA32 (normal, 32 bits) and SIOMLT_SEND (multiplay, low 16 bits).
@   3. Start the transfer: SIOCNT = +3A, or 0x2083 in multiplay.
@ In:  r0 = the value, r6 = REG_SIODATA32, r7 = MultiBootParam. Clobbers r1.
mb_master_send:
	movs r1, #0x96
mb_master_delay:
	.inst.n 0x1E49	@ subs r1, r1, #1
	bne mb_master_delay
	str r0, [r6, #0]	@ SIODATA32
	strh r0, [r6, #0xA]	@ SIOMLT_SEND
	ldrh r1, [r7, #0x3A]	@ normal: 0x1089 or 0x108B
	cmp r1, #0
	bne mb_master_start
	ldr r1, mb_master_multi_siocnt	@ =0xA1C12083. Low half 0x2083: multiplay, 115200 bps, start
mb_master_start:
	strh r1, [r6, #8]	@ SIOCNT: start
	bx lr
@ The received logo on the slave, and its palette fade.
@ intro_link_poll calls it once per frame in phases 3 and 4.
@ It returns 0 and does nothing until all of these are true:
@   - the intro is over and waiting (MULTIBOOT_FLAG = 1)
@   - the palette byte +0A has bit 7 set
@   - the header is in (+38 is past 0x020000C0, so the first unit of the program is in).
@ Then, the first time (mb_slave_logo_decode): +12 = 120, and decode_cart_logo on the
@ logo of the received header, 0x02000004. Nothing has checked the logo yet (the same as
@ for a cartridge). decode_cart_logo also sets INTRO_FLAG to 0x04, the low byte of r0.
@ intro_link_poll unpacks and places the logo in the next two frames (+12 = 0x77, 0x76),
@ and +24 = 60 starts the count for the song.
@ Every time: fades three OBJ colours (mb_slave_logo_fade) and decrements +12.
@ In:  r7 = 0x0300000C.
@ Out: r0 = 0, or 5 when +12 has run out (and +13 = 5): time to boot.
@ The palette byte (GBATEK: 0x81 + colour*0x10 + direction*8 + speed*2, or 0xF1 +
@ colour*2 for a fixed colour):
@   bits 4-6  the colour, 0-6
@   bit 3     the direction
@   bits 1-2  the speed
@ Bits 4-6 = 7: a fixed colour, in bits 1-3 (7 counts as 0).
mb_slave_logo:
	push {lr}
	ldr r0, mb_multiboot_flag_ptr	@ =MULTIBOOT_FLAG
	ldrb r1, [r0, #0]
	cmp r1, #1	@ 1: boot_intro is after the animation, waiting
	bne mb_slave_logo_none
	ldrb r0, [r7, #0xA]
	lsls r0, r0, #0x19	@ carry = bit 7 of the palette byte
	bcc mb_slave_logo_none
	ldrb r0, [r7, #0x12]
	ldrb r1, [r7, #0x13]
	orrs r0, r1
	bne mb_slave_logo_fade	@ the logo is already shown: fade and count
	ldr r0, [r7, #0x38]
	ldr r1, mb_program_dest	@ =EWRAM + 0xC0: the end of the received header
	subs r1, r1, r0
	bge mb_slave_logo_none	@ the header is not complete yet
	movs r0, #0x78
	strb r0, [r7, #0x12]	@ +12 = 120 frames before the boot
	ldr r0, mb_header_dest	@ =EWRAM: the received header
	b mb_slave_logo_decode	@ decode its logo, then continue at mb_slave_logo_fade
mb_slave_logo_none:
	movs r0, #0
	pop {pc}
mb_slave_logo_fade:	@ the palette fade
	ldr r2, [r7, #8]	@ the palette byte is bits 16-23 of this word
	lsls r1, r2, #0xD
	lsrs r1, r1, #0x1E	@ the speed, 0-3
	ldrb r0, [r7, #0x14]
mb_slave_logo_phase_loop:
	.inst.n 0x1CC0	@ adds r0, r0, #3
	.inst.n 0x1E49	@ subs r1, r1, #1
	bpl mb_slave_logo_phase_loop	@ the phase increases by 3 * (speed + 1) per frame
	strb r0, [r7, #0x14]
	lsrs r0, r0, #2	@ 0-63
	lsls r1, r0, #0x1A	@ its bit 5...
	lsls r2, r2, #0xC	@ ...^ the direction bit...
	eors r1, r2
	asrs r1, r1, #0x1F
	eors r0, r1	@ ...inverts it: up then down
	movs r1, #0x1F
	ands r1, r0	@ r1 = the fade amount, 0-31
	ldr r2, [r7, #8]
	lsls r0, r2, #9
	lsrs r0, r0, #0x1D	@ r0 = bits 4-6: the colour
	cmp r0, #7
	blt mb_slave_logo_colours
	movs r1, #0	@ 7: a fixed palette, no fade...
	lsls r0, r2, #0xC
	lsrs r0, r0, #0x1D	@ ...and the colour from bits 1-3
	cmp r0, #7
	blt mb_slave_logo_colours
	movs r0, #0
mb_slave_logo_colours:
	movs r2, #0x1F	@ OBJ palette entries 0x1F-0x21
	bl intro_fade_colors	@ (r0 = colour, r1 = fade amount, r2 = entry)
	ldrb r0, [r7, #0x12]
	.inst.n 0x1E40	@ subs r0, r0, #1
	blt mb_slave_logo_boot	@ +12 was already 0
	strb r0, [r7, #0x12]
	bne mb_slave_logo_none	@ not yet: return 0
mb_slave_logo_boot:
	movs r0, #5
	strb r0, [r7, #0x13]
	pop {pc}	@ return 5: boot
@ The slave side of MultiBoot, once per frame (see the file header).
@ boot_intro calls it in every frame of the animation (and ignores the result) and of
@ the wait after it (where the result decides).
@ In:  nothing. Inside, r7 = the work area (0x0300000C) and r4 = REG_SIODATA32.
@ Out: r0 = 0, or 5 when a received program is in EWRAM, decrypted and checked, and its
@      logo has been on screen for 120 frames. boot_intro stores r0 in SOFT_RESET_FLAG,
@      and SoftReset starts 0x02000000.
@ Each frame:
@   1. steps the seed
@   2. the logo steps and the song (link_poll_logo_steps)
@   3. the random word (link_poll_random)
@   4. while no transfer has started: counts the frames of the mode, and changes to the
@      next mode when they run out
@   5. the work of the phase.
@ The code is in three parts: here, link_poll_logo_steps (after the states) and
@ link_poll_random.
@ Writes:
@   - the work area
@   - RCNT, SIOCNT, SIOMLT_SEND, SIODATA32, JOYCNT, JOY_TRANS, JOYSTAT (mode setup)
@   - IE, IF and IME (to enable the serial IRQ; IME is off while it writes data that the
@     IRQ also writes)
@   - 0x02000000 and 0x020000C4-C5 (mb_slave_set_entry)
@   - the logo and palette (mb_slave_logo).
intro_link_poll:
	push {r4, r5, r6, r7}
	push {lr}
	ldr r7, mb_slave_area_ptr	@ =MB_SLAVE: the slave work area
	ldr r4, mb_sio_base	@ =REG_SIODATA32. r4 = the SIO base
	ldr r0, [r7, #0x4C]
	ldr r1, mb_seed_mul	@ =0x6177614B ("Kawa"): the seed multiplier
	muls r0, r1
	.inst.n 0x1C40	@ adds r0, r0, #1
	str r0, [r7, #0x4C]	@ seed = seed * 0x6177614B + 1
	b link_poll_logo_steps
link_poll_random:	@ (from link_poll_to_random) the random word, +00
	ldr r0, [r7, #0x4C]
	movs r1, #0xE0
	bics r0, r1
	movs r1, #0xA0
	eors r0, r1	@ bits 5-7 = 101
	movs r3, #0x80
	lsls r3, r3, #8	@ 0x8000
	bics r0, r3
	ldr r1, mb_multiboot_flag_ptr	@ =MULTIBOOT_FLAG
	ldrb r2, [r1, #0]
	cmp r2, #1
	beq link_poll_waiting	@ the intro is over and waiting: bit 15 set
	ldr r1, header_copy_minus_24	@ =HEADER_COPY_BASE. + 0x24 = 0x03000088, the BIOS header copy
	ldr r2, [r1, #0x24]	@ its first word
	.inst.n 0x1C52	@ adds r2, r2, #1
	bne link_poll_store_random	@ not 0xFFFFFFFF: bit 15 clear
link_poll_waiting:	@ 0xFFFFFFFF: intro_load_graphics blanked it because 0xB2 was not 0x96 (no cart)
	orrs r0, r3
link_poll_store_random:
	str r0, [r7, #0]
	ldrb r5, [r7, #0xF]	@ r5 = the phase
	ldrb r6, [r7, #0xE]	@ r6 = the mode
	ldrb r0, [r7, #0xD]
	cmp r0, #0
	bne link_poll_phase	@ a transfer has started: the mode is fixed
	bl mb_ime_off	@ IME off: the IRQ also writes +0C
	ldrb r3, [r7, #0xC]	@ frames left in this mode
	ldrh r0, [r4, #0x10]	@ KEYINPUT: read but not used
	cmp r6, #2
	bne link_poll_count_multi
	.inst.n 0x1E5B	@ subs r3, r3, #1
	bpl link_poll_keep_mode
link_poll_to_joy:	@ no normal frames left (or JOY Bus timed out): JOY Bus, 7 frames
	movs r6, #0
	movs r3, #6
	b link_poll_new_mode
link_poll_count_multi:
	cmp r6, #1
	bne link_poll_count_joy
	.inst.n 0x1E5B	@ subs r3, r3, #1
	bpl link_poll_keep_mode
link_poll_to_normal:	@ no multiplay frames left (or normal timed out): normal, 7 frames
	movs r6, #2
	movs r3, #6
	b link_poll_new_mode
link_poll_count_joy:
	.inst.n 0x1E5B	@ subs r3, r3, #1
	bpl link_poll_keep_mode
link_poll_to_multi:	@ no JOY Bus frames left (or multiplay timed out): multiplay, 31 frames
	movs r6, #1
	movs r3, #0x1E
link_poll_new_mode:	@ a new mode: no state, phase 0
	ldr r1, mb_idle_state_ptr	@ =mb_slave_idle + 1: the idle state
	str r1, [r7, #0x34]
	movs r5, #0
link_poll_keep_mode:
	strb r3, [r7, #0xC]
	bl mb_ime_on	@ IME on
link_poll_phase:	@ the work of the phase
	cmp r5, #0
	bne link_poll_phase1
	str r5, [r7, #0x10]	@ phase 0: +10-13 = 0
	strb r5, [r7, #0xA]	@ the palette byte = 0
	ldr r2, mb_header_dest	@ =EWRAM: where a received header goes
	str r2, [r7, #0x38]
	ldr r2, mb_program_dest	@ =EWRAM + 0xC0: the end of the header, the start of the program
	str r2, [r7, #0x3C]
	str r2, [r7, #0x44]
	movs r2, #1
	strb r2, [r7, #0xF]	@ phase 1 next
	strb r6, [r7, #0xE]
	cmp r6, #0
	bne link_poll_setup_multi
	movs r2, #0xC0
	lsls r2, r2, #8
	strh r2, [r4, #0x14]	@ RCNT = 0xC000: JOY Bus mode
	ldr r1, [r4, #0x30]	@ read JOY_RECV but do not use it (GBATEK: the read clears JOYSTAT bit 3)
	str r5, [r4, #0x34]	@ JOY_TRANS = 0
	strh r5, [r4, #0x38]	@ JOYSTAT = 0
	movs r1, #7
	strh r1, [r4, #0x20]	@ JOYCNT = 7: acknowledge reset, received, sent
	movs r1, #0xAD
	lsls r1, r1, #5	@ 0x15A0: the JOY Bus CRC start
link_poll_set_crc:
	strh r1, [r7, #0x20]	@ +20 = the CRC start for this mode
	b link_poll_return_0
link_poll_setup_multi:
	cmp r6, #1
	bne link_poll_setup_normal
	strh r5, [r4, #0x14]	@ multiplay: RCNT = 0
	ldr r2, mb_multi_siocnt	@ =0x60032003. Low half 0x2003: SIOCNT multiplay, 115200 bps
	ldr r1, mb_length_mask	@ =0x0003FFF8. As a halfword, 0xFFF8: the multiplay CRC start
link_poll_set_siocnt:
	strh r2, [r4, #8]	@ SIOCNT (no IRQ yet)
	strh r5, [r4, #0xA]	@ SIOMLT_SEND = 0: the "0000" reply
	str r5, [r4, #0]	@ SIODATA32 = 0
	b link_poll_set_crc
link_poll_setup_normal:
	strh r5, [r4, #0x14]	@ normal: RCNT = 0
	ldr r2, mb_normal_slave_siocnt	@ =0x10085088
	lsrs r2, r2, #0x10	@ 0x1008: SIOCNT 32-bit normal, external clock, SO high
	ldr r1, mb_normal_siocnt_crc	@ =0xC3871089
	lsrs r1, r1, #0x10	@ 0xC387: the normal-mode CRC start
	b link_poll_set_siocnt
	.arm
	.balign 4
@ msr cpsr_fc, r3; bx lr
@ ARM code for the Thumb code of MultiBoot: sets CPSR = r3 (0xDF: System mode, IRQ and
@ FIQ off), then returns. MultiBoot calls it with `bl mb_bx_r2` (bx r2).
multiboot_set_cpsr:
	msr CPSR_fc, r3
	bx lr
	.balign 4
mb_length_mask:
	.4byte 0x0003FFF8	@ the length mask (a multiple of 8 below 256 KiB). Also the 1/16 s
				@ delay count of MultiBoot, and (as a halfword) the multiplay CRC
				@ start, 0xFFF8
mb_dma_regs:
	.4byte REG_DMA0SAD	@ MultiBoot reads the four DMAxCNT_H from this base: no DMA may run
mb_sio_base:
	.4byte REG_SIODATA32	@ the base for every serial register (see the file header)
mb_idle_state_ptr:
	.4byte mb_slave_idle + 1	@ the idle receive state (mov pc ignores the Thumb bit)
mb_normal_siocnt_crc:
	.4byte 0xC3871089	@ low half 0x1089: SIOCNT for a normal transfer by the master
				@ (32-bit, internal 256 kHz clock, SO high, start). High half
				@ 0xC387: the normal-mode CRC start
header_copy_minus_24:
	.4byte HEADER_COPY_BASE	@ 0x03000088 - 0x24: for the BIOS header copy (copy_cart_header)
link_poll_phase1:	@ phases 1 to 4
	.thumb
	cmp r5, #1
	bne link_poll_phase2
	bl mb_ime_off	@ phase 1: IME off; r3 = REG_IE
	movs r1, #0x80
	strh r1, [r3, #2]	@ IF = serial: acknowledge a pending serial IRQ
	ldrh r2, [r3, #0]
	orrs r2, r1
	strh r2, [r3, #0]	@ IE |= serial
	strh r5, [r3, #8]	@ IME = 1
	cmp r6, #0
	bne link_poll_irq_multi
	movs r1, #0x47
	strh r1, [r4, #0x20]	@ JOYCNT = 0x47: acknowledge all three, IRQ on the reset command
	adr r2, mb_joy_wait_reset	@ the first JOY Bus state
	b link_poll_start_states
link_poll_irq_normal:
	ldr r1, mb_normal_slave_siocnt	@ =0x10085088. Low half 0x5088: SIOCNT normal, with IRQ and start
	b link_poll_set_irq_siocnt
link_poll_irq_multi:
	cmp r6, #1
	bne link_poll_irq_normal
	ldr r1, mb_multi_siocnt	@ =0x60032003
	lsrs r1, r1, #0x10	@ 0x6003: SIOCNT multiplay, 115200 bps, IRQ
link_poll_set_irq_siocnt:
	strh r1, [r4, #8]	@ SIOCNT
	adr r2, mb_slave_wait_62	@ the first multiplay / normal state
link_poll_start_states:
	movs r1, #2
	strb r1, [r7, #0xF]	@ phase 2: the receive states do the work
	str r2, [r7, #0x34]
	b link_poll_return_0
link_poll_phase2:
	cmp r5, #2
	bne link_poll_phase34
	b link_poll_return_0	@ phase 2: nothing to do
link_poll_phase34:	@ phases 3 and 4
	bl mb_slave_logo	@ the logo; r0 = 5 when it is time to boot
	cmp r5, #3
	beq link_poll_phase3
	cmp r0, #0	@ phase 4: return the result of mb_slave_logo
	beq link_poll_return_0
	b link_poll_return
link_poll_phase3:	@ phase 3: a transfer is running
	bl mb_ime_off	@ IME off: the IRQ writes +30; r3 = REG_IE
	ldr r0, [r7, #0x30]
	.inst.n 0x1E40	@ subs r0, r0, #1
	bpl link_poll_keep_timer
	cmp r6, #0	@ +30 expired: about 11 frames with no serial IRQ
	bne link_poll_timed_out
	ldrh r1, [r4, #0x38]	@ JOY Bus: JOYSTAT bits 4-5, which the states set...
	movs r2, #0x30
	ands r1, r2
	beq link_poll_check_done	@ ...are 0 after the last word (mb_joy_recv_program): no IRQ is due, continue
	b link_poll_to_joy	@ else start JOY Bus again
link_poll_timed_out:
	cmp r6, #1
	bne link_poll_to_normal	@ normal again
	b link_poll_to_multi	@ multiplay again
link_poll_keep_timer:
	str r0, [r7, #0x30]
link_poll_check_done:
	movs r0, #1
	strh r0, [r3, #8]	@ IME = 1
	ldrb r0, [r7, #0x11]
	cmp r0, #0
	bne link_poll_done	@ mb_slave_check_crc has matched the CRC: phase 4
	cmp r6, #0
	bne link_poll_decrypt
	ldr r0, mb_master_multi_siocnt	@ =0xA1C12083
	lsrs r0, r0, #0x10	@ JOY Bus: x = 0xA1C1
	ldr r1, multiboot_key	@ =0x6177614B ("Kawa"): the multiplier of the JOY Bus key
	ldr r3, mb_key_k_joy	@ =0x20796220 (" by "): the JOY Bus k
	bl mb_decrypt	@ decrypt the new words, add them to the CRC; r3 = decrypted up to
	str r3, [r7, #0x44]
	ldr r1, [r7, #0x3C]
	cmp r3, r1
	bne link_poll_return_0	@ not all received, or not all decrypted
	ldr r0, [r7, #0x38]	@ +38 must also be at r3. During the header, +3C = +44 = 0x020000C0
	eors r0, r3	@ and +38 is below it. (An IRQ that ends the header between the reads of
	bne link_poll_return_0	@ +3C and +38 would pass this test: a window of 3 instructions.)
	@ r0 = 0 below
	.inst.n 0x1F09	@ subs r1, r1, #4
	ldrh r2, [r1, #0]	@ the low half of the last word: the master CRC
	ldrh r3, [r7, #0x22]	@ our CRC, over all the words before it
	cmp r3, r2
	bne link_poll_refuse
	str r0, [r1, #0]	@ the CRC word = 0
	ldr r1, [r7, #8]	@ the length word
	ldr r2, mb_joy_markers	@ =0x80808080: bit 7 of each byte must be set
	ands r1, r2
	cmp r1, r2
	bne link_poll_refuse
	ldrb r1, [r7, #0xA]
	ldrb r2, [r7, #8]
	adds r1, r1, r2
	ldrb r2, [r7, #9]
	adds r1, r1, r2
	ldrb r2, [r7, #0xB]
	subs r1, r1, r2
	lsls r1, r1, #0x19	@ byte 3 must equal bytes 0 + 1 + 2, in bits 0-6
	bne link_poll_refuse
	ldr r0, mb_joy_entry_branch	@ =0xEA000036: ARM `b 0x020000E0` at 0x02000000, the JOY entry
	movs r1, #1	@ boot mode 1: JOY Bus
	bl mb_slave_set_entry	@ write the entry, check the header
	cmp r0, #0
	beq link_poll_done	@ good: phase 4
link_poll_refuse:	@ refused: phase 0, start the mode again
	movs r0, #0
	strb r0, [r7, #0xF]
	b link_poll_return_0
link_poll_decrypt:	@ phase 3, multiplay and normal
	ldr r2, [r7, #0x3C]
	ldr r3, [r7, #0x44]
	cmp r3, r2
	beq link_poll_return_0	@ all decrypted and checked (or only the header is in)
	ldr r0, mb_crc_x_multi	@ =0x0000A517: multiplay x
	ldr r3, mb_key_k_multi	@ =0x6465646F: multiplay k, "oded"
	cmp r6, #2
	bne link_poll_decrypt_words
	ldr r0, mb_crc_x_normal	@ =0x0000C37B: normal-mode x
	ldr r3, mb_key_k_normal	@ =0x43202F2F: normal-mode k, "// C"
link_poll_decrypt_words:
	ldr r1, mb_key_mul	@ =0x6F646573 ("sedo"): the multiplier of the key
	bl mb_decrypt	@ decrypt up to 0x89 words, add them to the CRC; r3 = decrypted up to
	cmp r2, r3	@ r2 = the end
	bne link_poll_decrypt_save
	ldr r2, [r7, #0x1C]	@ all decrypted: f...
	bl mb_crc_word	@ ...the last 32 steps of the CRC (r5 = the CRC from mb_decrypt)
	strh r5, [r7, #0x20]	@ for mb_slave_wait_66 to send
	ldr r0, mb_entry_branch	@ =0xEA00002E: ARM `b 0x020000C0` at 0x02000000
	movs r1, #4
	ldrb r6, [r7, #0xE]
	subs r1, r1, r6	@ boot mode: 4 - mode = 3 multiplay, 2 normal
	bl mb_slave_set_entry	@ write the entry, check the header
	cmp r0, #0
	bne link_poll_refuse	@ bad header: start again. The replies are then not 0074/0075,
			@ so the master fails.
	ldr r3, [r7, #0x3C]	@ good: +44 = the end, so mb_slave_wait_ready replies 0075
link_poll_decrypt_save:
	str r3, [r7, #0x44]
	b link_poll_return_0
	.balign 4, 0
	.balign 4
mb_crc_x_normal:
	.4byte 0x0000C37B	@ normal mode: x of the CRC
mb_crc_x_multi:
	.4byte 0x0000A517	@ multiplay: x of the CRC
mb_key_k_normal:
	.4byte 0x43202F2F	@ normal mode: k of the key, "// C"
mb_key_k_multi:
	.4byte 0x6465646F	@ multiplay: k of the key, "oded"
mb_key_k_joy:
	.4byte 0x20796220	@ JOY Bus: k of the key, " by "
mb_seed_mul:
	.4byte 0x6177614B	@ "Kawa": the multiplier of the slave random seed (as multiboot_key)
mb_key_mul:
	.4byte 0x6F646573	@ "sedo": the multiplier of the key in multiplay and normal mode
mb_header_dest:
	.4byte EWRAM	@ where a received header goes (and a received program starts)
mb_multi_siocnt:
	.4byte 0x60032003	@ SIOCNT for a multiplay slave: low half 0x2003 (115200 bps),
				@ high half 0x6003 (the same, with the IRQ on)
link_poll_done:	@ received and checked: phase 4 (and +11 = 4)
	movs r0, #4
	strb r0, [r7, #0x11]
	strb r0, [r7, #0xF]
link_poll_return_0:	@ return 0
	movs r0, #0
link_poll_return:	@ return r0
	pop {r3, r4, r5, r6, r7}
	bx r3
@ IME = 0 (mb_ime_off) or 1 (mb_ime_on). Out: r3 = REG_IE, r0 = the value.
@ intro_link_poll (the slave) turns IRQs off while it writes data that boot_serial_irq
@ also writes.
mb_ime_off:
	movs r0, #0
mb_ime_set:
	ldr r3, mb_reg_ie	@ =REG_IE. + 8 = IME
	strh r0, [r3, #8]	@ IME
	bx lr
mb_ime_on:
	movs r0, #1
	b mb_ime_set
@ Sets the slave phase to 0, so intro_link_poll sets up a link mode on its next call.
@ boot_intro calls it once, before the animation. Clobbers r1, r3.
intro_link_reset:
	ldr r3, mb_slave_area_ptr_2	@ =MB_SLAVE: the slave work area
	movs r1, #0
	strb r1, [r3, #0xF]
	bx lr
@ The serial IRQ handler during the intro.
@ boot_irq (system.s) jumps to it in IRQ mode, with IRQs off and IF already
@ acknowledged. lr = irq_return, so the `bx lr` of a state ends the IRQ.
@ It jumps to the receive state at +34 with:
@   r0 = the address of the state (so a state that stores r0 in +34 stays the same)
@   r1 = multiplay and normal: SIOMULTI0 / low half of SIODATA32, the master value;
@        JOY Bus: the JOYCNT flags, acknowledged by this code: 1 reset command,
@        2 received, 4 sent
@   r2 = REG_SIODATA32, r3 = 0x0300000C
@ Multiplay: a transfer with the SIOCNT error bit set resets the slave (mb_slave_reset).
@ JOY Bus: the states expect an IRQ on "received" and "sent" too, but only the
@ reset-command IRQ bit of JOYCNT is set (0x47). GBATEK leaves this open ("UNCLEAR").
boot_serial_irq:
	ldr r2, mb_sio_base_2	@ =REG_SIODATA32
	ldrh r1, [r2, #0]	@ SIOMULTI0 / SIODATA32 low: what the master sent
	ldr r3, mb_slave_area_ptr_2	@ =MB_SLAVE: the slave work area
	ldrb r0, [r3, #0xE]	@ the mode
	cmp r0, #1
	bne serial_irq_joy_check
	ldrh r0, [r2, #8]	@ multiplay: SIOCNT
	lsrs r0, r0, #7	@ carry = bit 6, the error bit
	bcs mb_slave_reset_far	@ an error: reset
serial_irq_dispatch:
	ldr r0, [r3, #0x34]	@ the state
	mov pc, r0	@ (stays Thumb: mov pc ignores bit 0)
serial_irq_joy_check:
	cmp r0, #2
	beq serial_irq_dispatch	@ normal: go directly to the state
	ldrh r1, [r2, #0x20]	@ JOY Bus: JOYCNT
	strh r1, [r2, #0x20]	@ write the flags back to acknowledge them
	movs r0, #7
	ands r1, r0	@ r1 = the flags: 1 reset, 2 received, 4 sent
	b serial_irq_dispatch
	.balign 4
mb_program_dest:
	.4byte EWRAM + 0xC0	@ the end of a received header: where a received program goes
mb_master_multi_siocnt:
	.4byte 0xA1C12083	@ low half 0x2083: SIOCNT for a multiplay transfer by the master
				@ (115200 bps, start). High half 0xA1C1: x of the JOY Bus CRC
mb_multiboot_flag_ptr:
	.4byte MULTIBOOT_FLAG	@ 1 = the intro is over and waiting for MultiBoot (boot_intro)
mb_slave_area_ptr:
	.4byte MB_SLAVE	@ the slave work area (see the file header)
	.balign 4
@ Receive state, multiplay and normal: the first state. Waits for 62yy from the master.
@ Other values are ignored (mb_slave_ignore: the port is re-armed and the state stays).
@ On 62yy:
@   - +16 = the slave number. Normal: 1. Multiplay: SIOCNT bits 4-5; 0 (the parent)
@     resets.
@   - +15 = its bit x.
@   - Then mb_slave_got_62, the same as for every 62yy: y to +10, the frame count of the
@     mode = 11 (so the mode stays), a check of y, and the reply 720x.
@ Next: mb_slave_wait_61.
mb_slave_wait_62:
	lsrs r0, r1, #8
	cmp r0, #0x62
	bne mb_slave_ignore
	ldrb r0, [r3, #0xE]
	cmp r0, #2
	bne mb_slave_multi_id
	movs r0, #1	@ normal: slave 1
	b mb_slave_set_number
mb_slave_multi_id:
	ldrh r0, [r2, #8]	@ multiplay: SIOCNT...
	lsls r0, r0, #0x1A
	lsrs r0, r0, #0x1E	@ ...bits 4-5, the multi-player ID
mb_slave_set_number:
	strb r0, [r3, #0x16]	@ +16 = the slave number
	beq mb_slave_reset_far	@ 0 is the parent: reset
	movs r1, #1
	lsls r1, r0
	strb r1, [r3, #0x15]	@ +15 = x
	ldrh r1, [r2, #0]	@ the 62yy again
	adr r0, mb_slave_wait_61
	str r0, [r3, #0x34]
mb_slave_got_62:	@ a 62yy (also from mb_slave_wait_61, mb_slave_wait_63)
	strb r1, [r3, #0x10]	@ +10 = y
	movs r0, #0xB
	strb r0, [r3, #0xC]	@ 11 more frames in this mode
	movs r0, #0x11
	ands r0, r1
	bne mb_slave_reset_far	@ bits 0 and 4 of y must be clear...
	lsrs r0, r1, #4
	orrs r0, r1
	lsrs r2, r1, #4
	eors r2, r1
	eors r2, r0	@ (a ^ b) ^ (a | b) = a & b...
	lsls r2, r2, #0x1C
	bne mb_slave_reset_far	@ ...and its two nibbles must have no common bit (why: not followed)
	movs r0, #0x72
	lsls r0, r0, #8
	ldrb r1, [r3, #0x15]
	orrs r1, r0	@ reply 720x
	b mb_slave_reply
	.byte 0x00, 0x00	@ padding: adr reaches each state, so the states are word aligned
	.balign 4
@ Receive state, multiplay and normal: 62yy seen, waits for 610y.
@   62yy  again: reply 720x (mb_slave_got_62).
@   610y  the header comes next: phase 3, +0D = 3 (the mode is now fixed),
@         +38 = 0x02000000, 0x60 halfwords to come. Reply 600x.
@         Next: mb_slave_recv_header.
@   else  reset.
@ mb_slave_wait_63 also enters at mb_slave_check_61, for 62yy and 61yy.
mb_slave_wait_61:
	lsrs r0, r1, #8
mb_slave_check_61:
	cmp r0, #0x62
	beq mb_slave_got_62
	cmp r0, #0x61
	bne mb_slave_reset_far
	movs r0, #3
	strb r0, [r3, #0xF]	@ phase 3
	strb r0, [r3, #0xD]	@ a transfer has started
	ldr r2, mb_header_dest_2	@ =EWRAM: where the received header goes
	str r2, [r3, #0x38]
	movs r2, #0x60	@ 0x60 halfwords: the 0xC0-byte header
	adr r0, mb_slave_recv_header
	b mb_slave_reply_count
	.byte 0x00, 0x00	@ padding: word aligned for adr
	.balign 4
@ Receive state, multiplay and normal: the header, 0x60 halfwords to 0x02000000-0x020000BF.
@ Each transfer carries 16 bits, also in normal mode. Each halfword goes to +38 unchanged
@ (it is not encrypted and not checked yet), and +48 counts down. Reply NN0x, where NN =
@ the number still to come (0x5F down to 0x00). After the last one, next:
@ mb_slave_wait_63.
mb_slave_recv_header:
	ldr r2, [r3, #0x38]
	strh r1, [r2, #0]
	.inst.n 0x1C92	@ adds r2, r2, #2
	str r2, [r3, #0x38]
	ldr r2, [r3, #0x48]
	.inst.n 0x1E52	@ subs r2, r2, #1
	bne mb_slave_reply_count	@ more: r0 is still this state
	adr r0, mb_slave_wait_63
mb_slave_reply_count:	@ r2 = halfwords to come; r0 = the next state
	str r2, [r3, #0x48]
	lsls r2, r2, #8
	ldrb r1, [r3, #0x15]
	orrs r1, r2	@ reply NN0x
	b mb_slave_next_state
	.byte 0x00, 0x00	@ padding: word aligned for adr
	.balign 4
@ Receive state, multiplay and normal: the header is in, waits for 63pp.
@   62yy  y; reply 720x (through mb_slave_check_61).
@   61yy  the header again from the start (through mb_slave_check_61).
@   63pp  cc2 and cc3 = 0xFF (normal mode has no other slaves), then mb_slave_got_63:
@         - pp to +0A and +18
@         - cc1-cc3 to +19-1B. Normal: the last cc of this slave (+17). Multiplay: the
@           low bytes of SIOMULTI1-3, which each slave sent in this transfer. The master
@           repeats 63pp until all slaves reply 73cc, so the last 63pp stores the
@           correct values.
@         - +04 = m = that word
@         - a new cc from byte 1 of the random word, kept in +17 and sent as 73cc.
@         Next: mb_slave_wait_64.
mb_slave_wait_63:
	lsrs r0, r1, #8
	cmp r0, #0x63
	bne mb_slave_check_61
	movs r0, #0xFF
	strb r0, [r3, #0x1A]	@ cc2
	strb r0, [r3, #0x1B]	@ cc3
mb_slave_got_63:	@ a 63pp (also from mb_slave_wait_64)
	strb r1, [r3, #0xA]	@ +0A = pp, the palette byte
	strb r1, [r3, #0x18]	@ +18 = pp
	ldrb r0, [r3, #0xE]
	cmp r0, #2
	bne mb_slave_multi_cc
	ldrb r0, [r3, #0x17]	@ normal: cc1 = the cc this slave sent
	strb r0, [r3, #0x19]
	b mb_slave_set_m
mb_slave_multi_cc:
	ldrh r0, [r2, #2]	@ multiplay: low bytes of SIOMULTI1-3 = cc1-cc3
	strb r0, [r3, #0x19]
	ldrh r0, [r2, #4]
	strb r0, [r3, #0x1A]
	ldrh r0, [r2, #6]
	strb r0, [r3, #0x1B]
mb_slave_set_m:
	ldr r0, [r3, #0x18]
	str r0, [r3, #4]	@ m = dword(pp, cc1, cc2, cc3)
	ldrb r2, [r3, #1]	@ byte 1 of the random word: a new cc
	strb r2, [r3, #0x17]
	adr r0, mb_slave_wait_64
mb_slave_reply_73:	@ reply 73xx, xx = r2
	movs r1, #0x73
	lsls r1, r1, #8
	orrs r1, r2
	b mb_slave_next_state
mb_slave_reset_far:	@ for branches that cannot reach mb_slave_reset (the reset)
	b mb_slave_reset
	.balign 4
@ Receive state, multiplay and normal: the palette is sent, waits for 64hh.
@   63pp  the same as in mb_slave_wait_63 (mb_slave_got_63).
@   64hh  hh to +1C (byte 0 of f). Normal mode: the rr of this slave (byte 2 of the
@         random word) to +1D, and 0xFF to +1E-1F. Reply 73rr.
@         Next: mb_slave_recv_length.
@   else  reset.
mb_slave_wait_64:
	lsrs r0, r1, #8
	cmp r0, #0x63
	beq mb_slave_got_63
	cmp r0, #0x64
	bne mb_slave_reset
	strb r1, [r3, #0x1C]	@ +1C = hh
	ldrb r2, [r3, #2]	@ byte 2 of the random word: rr
	ldrb r0, [r3, #0xE]
	cmp r0, #2
	bne mb_slave_reply_73rr
	strb r2, [r3, #0x1D]	@ normal: rr1 is from this slave; no rr2, rr3
	movs r0, #0xFF
	strb r0, [r3, #0x1E]
	strb r0, [r3, #0x1F]
mb_slave_reply_73rr:
	adr r0, mb_slave_recv_length
	b mb_slave_reply_73	@ reply 73rr
mb_slave_ignore:	@ from mb_slave_wait_62, not a 62yy: continue to wait
	b mb_slave_rearm
	.byte 0x00, 0x00	@ padding: word aligned for adr
	.balign 4
@ Receive state, multiplay and normal: the length (the SWI starts here).
@ llll = length / 4 - 0x34.
@ Multiplay: rr1-rr3 from SIOMULTI1-3 to +1D-1F (for normal, mb_slave_wait_64 set them).
@ llll * 4 + 0xC8 (= length - 8) must be a multiple of 8, up to 0x3FFF8. If not: reset.
@ +3C = 0x020000C0 + length: the end of the program.
@ Reply 00C0: the low half of the address of the first unit. Next: mb_slave_recv_program.
mb_slave_recv_length:
	ldrb r0, [r3, #0xE]
	cmp r0, #2
	beq mb_slave_check_length
	ldrh r0, [r2, #2]	@ multiplay: rr1-rr3 as each slave sent them
	strb r0, [r3, #0x1D]
	ldrh r0, [r2, #4]
	strb r0, [r3, #0x1E]
	ldrh r0, [r2, #6]
	strb r0, [r3, #0x1F]
mb_slave_check_length:
	lsls r1, r1, #2
	adds r1, #0xC8	@ length - 8
	ldr r0, mb_length_mask_2	@ =0x0003FFF8: the length mask (a multiple of 8, below 256 KiB)
	ands r0, r1
	eors r1, r0
	bne mb_slave_reset	@ bits outside the mask: reset
	ldr r1, mb_program_dest_2	@ =EWRAM + 0xC0: where the program goes; also the reply 00C0
	adds r2, r1, r0
	adds r2, #8
	str r2, [r3, #0x3C]	@ +3C = the end of the program
	adr r0, mb_slave_recv_program
	b mb_slave_next_state
	.byte 0x00, 0x00	@ padding: word aligned for adr
	.balign 4
@ Receive state, multiplay and normal: the program.
@ Each unit (16 bits in multiplay, all of SIODATA32 in normal mode) goes to +38 still
@ encrypted, and +38 increments. intro_link_poll decrypts the units later, frame by frame.
@ The reply is the low half of the new +38 (the address of the next unit). The master
@ checks it. When +38 reaches +3C, next: mb_slave_wait_ready.
mb_slave_recv_program:
	ldrb r0, [r3, #0xE]
	cmp r0, #2
	ldr r0, [r3, #0x38]
	strh r1, [r0, #0]	@ the low 16 bits
	bne mb_slave_next_unit	@ (the flags are still from the cmp) multiplay: done
	ldr r1, [r2, #0]	@ normal: all 32 bits
	str r1, [r0, #0]
	.inst.n 0x1C80	@ adds r0, r0, #2
mb_slave_next_unit:
	adds r1, r0, #2	@ the new +38, also the reply
	str r1, [r3, #0x38]
	ldr r0, [r3, #0x3C]
	cmp r0, r1
	bne mb_slave_reply	@ more to come
	adr r0, mb_slave_wait_ready
	b mb_slave_next_state
	.byte 0x00, 0x00	@ padding: word aligned for adr
	.balign 4
@ Receive state, multiplay and normal: all of the program is in. The master sends 0065.
@ Reply 0074 while intro_link_poll has not decrypted all of it (+44 is below +3C). This
@ includes the last step of the CRC and the header check. Then reply 0075, and next:
@ mb_slave_wait_66. Any value other than 0065: reset.
mb_slave_wait_ready:
	cmp r1, #0x65
	bne mb_slave_reset
	ldr r1, [r3, #0x44]
	ldr r2, [r3, #0x3C]
	cmp r1, r2
	beq mb_slave_reply_75
	movs r1, #0x74	@ not yet: reply 0074, same state
	b mb_slave_reply
mb_slave_reply_75:	@ ready: reply 0075 (also from mb_slave_wait_66)
	movs r1, #0x75
	adr r0, mb_slave_wait_66
	b mb_slave_next_state
	.byte 0x00, 0x00	@ padding: word aligned for adr
	.balign 4
@ Receive state, multiplay and normal: ready.
@   0065  reply 0075 again.
@   0066  the CRC comes next: reply the CRC of this slave (+20). Next: mb_slave_check_crc.
@   else  reset.
mb_slave_wait_66:
	cmp r1, #0x65
	beq mb_slave_reply_75
	cmp r1, #0x66
	bne mb_slave_reset
	ldrh r1, [r3, #0x20]	@ reply: our CRC
	adr r0, mb_slave_check_crc
	b mb_slave_next_state
	.byte 0x00, 0x00	@ padding: word aligned for adr
	.balign 4
@ Receive state, multiplay and normal: the master CRC. Checks:
@   - it must equal the CRC of this slave (+20)
@   - multiplay: it must equal what every slave in y (+10) sent in this transfer
@   - hh must be 0x11 + cc1 + cc2 + cc3 in its low byte (GBATEK).
@ Then +11 = 0xFF, which intro_link_poll takes as "done" (phase 4). Reply 00FF; next:
@ mb_slave_idle. If a check fails: reset.
mb_slave_check_crc:
	ldrh r0, [r3, #0x20]
	cmp r0, r1
	bne mb_slave_reset	@ not our CRC
	ldrb r1, [r3, #0xE]
	cmp r1, #1
	bne mb_slave_check_hh	@ normal: no other slaves
	ldrb r3, [r3, #0x10]
	lsls r3, r3, #0x1C
	lsrs r3, r3, #0x1D	@ bits 1-3 of y to bits 0-2
mb_slave_crc_loop:
	lsrs r3, r3, #1
	bcc mb_slave_crc_skip
	ldrh r1, [r2, #2]	@ SIOMULTIn: the CRC of that slave
	cmp r0, r1
	bne mb_slave_crc_done	@ differs: (ne) reset below
mb_slave_crc_next:
	.inst.n 0x1C92	@ adds r2, r2, #2
	b mb_slave_crc_loop
mb_slave_crc_skip:
	bne mb_slave_crc_next
mb_slave_crc_done:
	ldr r3, mb_slave_area_ptr_2	@ =MB_SLAVE: restore r3 (ldr does not change the flags)
	bne mb_slave_reset
mb_slave_check_hh:
	ldr r0, [r3, #0x1C]	@ hh in the low byte
	ldrb r1, [r3, #0x19]
	subs r0, r0, r1
	ldrb r1, [r3, #0x1A]
	subs r0, r0, r1
	ldrb r1, [r3, #0x1B]
	subs r0, r0, r1
	subs r0, #0x11
	lsls r0, r0, #0x18	@ hh - cc1 - cc2 - cc3 - 0x11, low byte
	bne mb_slave_reset	@ must be 0
	movs r1, #0xFF
	strb r1, [r3, #0x11]	@ done
	adr r0, mb_slave_idle
mb_slave_next_state:	@ r0 = the next state, r1 = the reply
	str r0, [r3, #0x34]
mb_slave_reply:	@ r1 = the reply
	ldr r2, mb_sio_base_2	@ =REG_SIODATA32
	strh r1, [r2, #0xA]	@ SIOMLT_SEND: the multiplay reply
	strh r1, [r2, #2]	@ high half of SIODATA32: the normal-mode reply
mb_slave_rearm:	@ re-arm and return
	ldrb r0, [r3, #0xE]
	cmp r0, #2
	bne mb_slave_set_timeout
	ldr r2, mb_sio_base_2	@ =REG_SIODATA32
	ldr r0, mb_normal_slave_siocnt	@ =0x10085088. Low half 0x5088: SIOCNT normal, IRQ, start
	strh r0, [r2, #8]	@ normal: set the start bit for the next transfer
mb_slave_set_timeout:
	movs r0, #0xB
	str r0, [r3, #0x30]	@ 11 frames before intro_link_poll times out
	bx lr
mb_slave_reset:	@ reset: phase 0, the idle state, reply 0
	movs r1, #0
	strb r1, [r3, #0xF]
	adr r0, mb_slave_idle
	b mb_slave_next_state
	.balign 4, 0
	.balign 4
mb_normal_slave_siocnt:
	.4byte 0x10085088	@ SIOCNT for a normal-mode slave (32-bit, external clock, SO high):
				@ high half 0x1008 for the setup, low half 0x5088 with IRQ and start
	.balign 4
@ Receive state, JOY Bus: the first state. Waits for the reset command from the master
@ (the JOYCNT flags are exactly 1; any other value resets). Then:
@   - m (+04) = the random word
@   - JOY_TRANS = the random word ^ "sedo", for the master to read (GBATEK: command 0x14
@     reads JOY_TRANS)
@   - the frame count of the mode = 11, so the mode stays
@   - JOYSTAT = 0x10. Bits 4-5 are general-purpose flags that the master reads with each
@     command. It looks like they show the progress of the slave.
@ Next: mb_joy_wait_read.
mb_joy_wait_reset:
	cmp r1, #1
	bne mb_slave_reset
	ldr r0, [r3, #0]	@ the random word
	str r0, [r3, #4]	@ m
	ldr r1, multiboot_key + 4	@ =0x6F646573: "sedo"
	eors r0, r1
	str r0, [r2, #0x34]	@ JOY_TRANS
	movs r0, #0xB
	strb r0, [r3, #0xC]	@ 11 more frames in this mode
	movs r1, #0x10	@ JOYSTAT = 0x10
	adr r0, mb_joy_wait_read
	b mb_joy_set_stat
	.balign 4
@ Receive state, JOY Bus: waits for "sent" (4): the master has read JOY_TRANS.
@ Any other value resets. Then phase 3 and +0D = 3 (the mode is now fixed).
@ Next: mb_joy_recv_length.
mb_joy_wait_read:
	cmp r1, #4
	bne mb_slave_reset
	movs r0, #3
	strb r0, [r3, #0xF]	@ phase 3
	strb r0, [r3, #0xD]	@ a transfer has started
	adr r0, mb_joy_recv_length
	b mb_joy_next_state
	.byte 0x00, 0x00	@ padding: word aligned for adr
	.balign 4
@ Receive state, JOY Bus: the length word, "received" (2), from JOY_RECV.
@ Bit 9 of the word selects the XOR key, "Kawa" or "sedo". Neither key has bit 9 set, so
@ the bit is the same before and after the XOR. The result goes to +08; its byte 2 is
@ the palette byte.
@ The length is (n + 0x3F) * 8, where n = bits 0-6, 8-14 and 16 of the word. Bits 7, 15,
@ 23 and 31 are the marker bits that intro_link_poll checks at the end.
@ A length above 0x3FFF8 becomes 0x4480, and the palette byte loses bit 7, so the
@ transfer is refused at the end.
@ +40 = 0x02000000 + length + 0xC: the end of the program. JOYSTAT = 0x20.
@ Next: mb_joy_recv_program.
mb_joy_recv_length:
	cmp r1, #2
	bne mb_slave_reset
	ldr r0, [r2, #0x30]	@ JOY_RECV
	movs r1, #2
	lsls r1, r1, #8
	ands r1, r0	@ bit 9...
	lsrs r1, r1, #7	@ ...as 0 or 4
	adr r2, multiboot_key
	adds r2, r2, r1
	ldr r1, [r2, #0]	@ "Kawa" or "sedo"
	eors r0, r1
	str r0, [r3, #8]	@ +08 = the length word
	lsrs r1, r0, #8
	movs r2, #0x7F
	ands r1, r2	@ bits 8-14
	lsls r0, r0, #0x10
	bcc mb_joy_length_n
	adds r1, #0x80	@ and bit 16 above them
mb_joy_length_n:
	lsrs r0, r0, #0x10
	ands r0, r2	@ bits 0-6
	lsls r1, r1, #7
	orrs r1, r0	@ n
	adds r1, #0x3F
	lsls r1, r1, #3	@ the length = (n + 0x3F) * 8
	ldr r0, mb_length_mask_2	@ =0x0003FFF8: the length mask (a multiple of 8, below 256 KiB)
	ands r0, r1
	cmp r0, r1
	beq mb_joy_set_end
	ldrb r0, [r3, #0xA]	@ too long: the palette byte loses bit 7...
	lsls r0, r0, #0x19
	lsrs r0, r0, #0x19
	strb r0, [r3, #0xA]
	movs r0, #0x89
	lsls r0, r0, #7	@ ...and the length is 0x4480
mb_joy_set_end:
	adds r0, #0xC
	ldr r1, mb_header_dest_2	@ =EWRAM: the start of a received header and program
	adds r1, r1, r0
	str r1, [r3, #0x40]	@ +40 = the end of the program
	movs r1, #0x20	@ JOYSTAT = 0x20
	adr r0, mb_joy_recv_program
	b mb_joy_set_stat
	.byte 0x00, 0x00	@ padding: word aligned for adr
	.balign 4
@ Receive state, JOY Bus: each word, "received" (2).
@ JOYSTAT bit 4 toggles (probably a signal that the master can see). The word from
@ JOY_RECV goes to +38 unchanged.
@ When +38 reaches +3C:
@   - at 0x020000C0: the header is in, and +3C = the end of the program (+40)
@   - at the end: JOY_TRANS = the word at 0x020001F8 x the word at 0x020001FC (two
@     received words, for the master to read back). Whether intro_link_poll has
@     decrypted them at that time depends on timing (not followed). JOYSTAT = 0.
@     Next: mb_slave_idle.
@ The header is not encrypted. intro_link_poll decrypts the rest.
mb_joy_recv_program:
	cmp r1, #2
	bne mb_slave_reset
	ldrh r0, [r2, #0x38]	@ JOYSTAT
	movs r1, #0x10
	eors r1, r0	@ bit 4 toggled
	ldr r0, [r2, #0x30]	@ JOY_RECV: the word
	strh r1, [r2, #0x38]	@ JOYSTAT
	ldr r1, [r3, #0x38]
	stmia r1!, {r0}
	str r1, [r3, #0x38]
	ldr r0, [r3, #0x3C]
	cmp r0, r1
	bne mb_slave_rearm	@ more to come in this part
	ldr r1, mb_program_dest_2	@ =EWRAM + 0xC0: the end of the header
	cmp r0, r1
	bne mb_joy_all_in	@ this was the end of the program
	ldr r0, [r3, #0x40]	@ the header is in: now receive up to the end of the program
	str r0, [r3, #0x3C]
	b mb_slave_rearm
mb_joy_all_in:	@ all of the program is in
	ldr r0, mb_joy_check_words	@ =EWRAM + 0x1F8: two words of the received program
	ldr r1, [r0, #4]
	ldr r0, [r0, #0]
	muls r0, r1
	str r0, [r2, #0x34]	@ JOY_TRANS = their product
	movs r1, #0	@ JOYSTAT = 0: then the timeout of intro_link_poll stops
	adr r0, mb_slave_idle
mb_joy_set_stat:	@ r1 = JOYSTAT, r0 = the next state
	ldr r2, mb_sio_base_2	@ =REG_SIODATA32
	strh r1, [r2, #0x38]	@ JOYSTAT
mb_joy_next_state:
	str r0, [r3, #0x34]
	b mb_slave_rearm
	.balign 4
@ Receive state: does nothing, and ends the IRQ.
@ It is the state before the first state (a mode change stores it, at
@ link_poll_new_mode), after an error (mb_slave_reset) and after the last state.
mb_slave_idle:
	bx lr
@ Writes the entry of a received program and checks its header.
@ intro_link_poll calls it when all of the program is in and decrypted.
@ In:  r0 = an ARM branch for 0x02000000: 0xEA00002E, b 0x020000C0 (multiplay, normal),
@           or 0xEA000036, b 0x020000E0 (JOY Bus). GBATEK: "the entry is then
@           overwritten and redirected to a separate Multiboot Entry Point".
@      r1 = the boot mode for 0x020000C4 (GBATEK: 1 JOY Bus, 2 normal, 3 multiplay).
@      r7 = 0x0300000C.
@ Writes: 0x02000000 = r0; 0x020000C4 = r1; 0x020000C5 = the slave number (+16),
@      except in JOY Bus (GBATEK: the byte then stays as sent). It writes before the
@      check, so it also writes when the check fails.
@ Out: r0 = the result of check_cart_header on the received header (0x02000004): 0 good,
@      1 bad. It checks the logo and the complement, as for a cartridge.
mb_slave_set_entry:
	push {lr}
	ldr r2, mb_header_dest_2	@ =EWRAM: the entry point of the received header
	str r0, [r2, #0]	@ 0x02000000 = the branch
	ldr r3, mb_program_dest_2	@ =EWRAM + 0xC0: the start of the program
	strb r1, [r3, #4]	@ 0x020000C4 = the boot mode
	cmp r1, #1
	beq mb_entry_check_header
	ldrb r0, [r7, #0x16]
	strb r0, [r3, #5]	@ 0x020000C5 = the slave number
mb_entry_check_header:
	adds r0, r2, #4	@ 0x02000004: the logo of the received header
	bl check_cart_header
	pop {pc}
mb_slave_logo_decode:	@ part of mb_slave_logo: decodes the received logo, the first time. r0 = 0x02000000
	.inst.n 0x1D00	@ adds r0, r0, #4
	bl decode_cart_logo	@ (INTRO_FLAG = 0x04, the low byte of r0)
	ldrh r0, [r7, #0x24]
	cmp r0, #0
	bne mb_slave_logo_to_fade	@ the song count is running: do not change it
	movs r0, #0x3C
	strh r0, [r7, #0x24]	@ +24 = 60
mb_slave_logo_to_fade:
	b mb_slave_logo_fade
link_poll_logo_steps:	@ part of intro_link_poll: the logo steps, then the song
	ldrb r0, [r7, #0x12]
	cmp r0, #0x77
	bne link_poll_logo_place
	bl unpack_cart_logo	@ the frame after decode_cart_logo: unpack it
	b link_poll_song
link_poll_logo_place:
	cmp r0, #0x76
	bne link_poll_song
	bl place_cart_logo	@ the frame after that: put it on screen
link_poll_song:
	ldrh r0, [r7, #0x24]
	cmp r0, #0
	beq link_poll_to_random
	.inst.n 0x1E40	@ subs r0, r0, #1
	strh r0, [r7, #0x24]
	cmp r0, #0x39
	bne link_poll_to_random	@ at 57, three frames after the logo was decoded:
	ldr r0, mb_music_player	@ =INTRO_PLAYER1: the second music player (boot_intro opened it)
	ldr r1, song_multiboot_ptr	@ =song_multiboot
	bl MusicPlayerStart
link_poll_to_random:
	b link_poll_random
	.balign 4, 0
	.balign 4
mb_sio_base_2:
	.4byte REG_SIODATA32	@ the base for every serial register (see the file header)
mb_length_mask_2:
	.4byte 0x0003FFF8	@ the length mask: a multiple of 8, below 256 KiB
	.balign 4
@ "Kawasedo"
@ The code reads it as two words:
@   "Kawa" (0x6177614B): the multiplier of the JOY Bus key
@   "sedo" (0x6F646573): the JOY Bus random word is sent XORed with it
@ mb_joy_recv_length selects one of them to decode the length word.
multiboot_key:
	.byte 0x4B, 0x61, 0x77, 0x61, 0x73, 0x65, 0x64, 0x6F
@ The last literal pool of multiboot.s: ten words for the slave side of MultiBoot.
@ They are loaded with ldr. Users: the receive states (mb_slave_*, mb_joy_*),
@ boot_serial_irq, intro_link_poll, intro_link_reset and mb_ime_off.
@ A Thumb ldr reaches only 1 KiB forward. So the words that end in _2 are second copies
@ of mb_program_dest, mb_header_dest and mb_slave_area_ptr, for code that is too far
@ after the first copies.
mb_reg_ie:
	.4byte REG_IE	@ + 8 = IME: mb_ime_off and mb_ime_on set it; + 2 = IF
mb_program_dest_2:
	.4byte EWRAM + 0xC0	@ the end of a received header: where a received program goes
mb_joy_check_words:
	.4byte EWRAM + 0x1F8	@ JOY Bus: the two received words whose product is sent back
mb_header_dest_2:
	.4byte EWRAM	@ where a received header goes (and its entry, which mb_slave_set_entry replaces)
mb_slave_area_ptr_2:
	.4byte MB_SLAVE	@ the slave work area (see the file header)
mb_joy_markers:
	.4byte 0x80808080	@ JOY Bus: the marker bits of the length word; all must be set
mb_joy_entry_branch:
	.4byte 0xEA000036	@ ARM `b 0x020000E0` placed at 0x02000000: the JOY Bus entry
mb_entry_branch:
	.4byte 0xEA00002E	@ ARM `b 0x020000C0` placed at 0x02000000: multiplay/normal entry
mb_music_player:
	.4byte INTRO_PLAYER1	@ the player of the second MusicPlayerOpen (boot_intro). It also
				@ plays song_hold_select_start and song_wait_button
song_multiboot_ptr:
	.4byte song_multiboot	@ played while the logo of a received program is on screen
