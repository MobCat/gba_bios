@ vectors.s 0x0000-0x0283: the exception vectors, and the code that every reset,
@ exception, SWI and IRQ goes through. All ARM, except clear_bios_ram.
@
@ Entry points
@   reset      reset_handler. On a first boot (POSTFLG = 0), it falls into HardReset:
@              reset_stacks, INTR_VECTOR = boot_irq, then boot_intro (intro.s).
@              boot_intro returns into SoftReset, which jumps to the cartridge.
@              If POSTFLG is already 1 (a jump to 0 after boot), it goes to
@              exception_handler.
@   undefined, prefetch abort, data abort, the reserved vector, and FIQ
@              exception_handler: goes to the cartridge debugger if the header
@              enables it (0xA5 at 0x9C), else returns immediately. FIQ has no
@              branch: the handler starts at the FIQ vector, 0x1C.
@   SWI        swi_handler: the SWI number is an index into swi_table. The function runs
@              in System mode on the stack of the caller. It returns through swi_return.
@   IRQ        irq_handler: calls the ARM handler of the game at INTR_VECTOR and returns
@              through irq_return.
@   Also in this file: enter_cgb_mode (the switch to Game Boy Color mode, which falls
@   into Halt), the SWIs Halt, Stop and CustomHalt, the stack tops and the SWI table.
@
@ RAM: the stacks:
@     System/User  sp = STACK_USR (0x03007F00)
@     IRQ          sp = STACK_IRQ (0x03007FA0)
@     Supervisor   sp = STACK_SVC (0x03007FE0)
@     exception    sp = STACK_EXC (0x03007FF0), in any mode that takes the exception
@   reset_stacks zeroes 0x03007E00-0x03007FFF. This area holds INTR_VECTOR, INTR_CHECK,
@   SOFT_RESET_FLAG and SOUND_AREA_PTR. SoftReset reads SOFT_RESET_FLAG. HardReset
@   writes INTR_VECTOR, and irq_handler reads it.
@   The code gets to these addresses through the IWRAM mirror. IWRAM repeats every
@   32 KiB up to 0x03FFFFFF, so 0x03FFFFxx is 0x03007Fxx. Thus one register that holds
@   0x04000000 is the I/O base and also, with a negative offset, the top of IWRAM.
@ I/O: POSTFLG (read), IME (HardReset clears it), DISPCNT (enter_cgb_mode),
@   HALTCNT (Halt, Stop, CustomHalt).
@ ROM: header bytes 0x9C and 0xB4, and the debugger entries at 0x09FE2000 and
@   0x09FFC000 (exception_handler).
@
@ Why 0x0000-0x0283 must not change (README.md)
@   Only code that runs in the BIOS can read the BIOS. A read from other code returns
@   the last opcode that the BIOS fetched (GBATEK, "Reading from BIOS Memory"). Because
@   of the ARM pipeline, that is the word 8 bytes after the last BIOS instruction
@   executed. Thus a game can see four values, and test ROMs check them (bios.gba by
@   jsmolka checks all four; see also docs/gba-core.md in DinoRec):
@     0xE129F000  at 0x00E4 in reset_stacks: msr CPSR_fc, r0. After startup and
@                 SoftReset, whose last instruction is the bx lr at 0x00DC.
@     0xE25EF004  at 0x013C in irq_return: subs pc, lr, #4. While the game IRQ
@                 handler runs, entered by the ldr pc at 0x0134.
@     0xE55EC002  at 0x0144 in swi_handler: ldrb ip, [lr, #-2]. After an IRQ,
@                 left by the subs pc at 0x013C.
@     0xE3A02004  at 0x0190 in enter_cgb_mode: mov r2, #4. After any SWI, left
@                 by the movs pc at 0x0188 in swi_return.
@   Each value needs its opcode, and the exit 8 bytes before it, to stay at the same
@   address. Thus no code up to 0x0190 can grow, shrink or move.
@   After 0x0190, no code is read from outside, but the end of the SWI table is
@   important. swi_handler does not check the number, so SWI 0x2B-0xFF read the words
@   after the table (from 0x0274) as addresses and jump there (GBATEK: they "jump to
@   garbage addresses"). These words are dacs_1mbit_entry, dacs_8mbit_entry,
@   boot_entry_pointer, bios_ram_clear_offset, then the code of system.s. SWI 0xF7-0xFF
@   read the start of header.s (0x05A4-0x05C7).
@   If the end of the table moves, or anything in 0x0274-0x05C7 changes, these SWIs
@   jump to different addresses.

	.arm
	.balign 4
@ _start: the vector table. Each exception enters ARM state at its vector, in its
@ own mode, with IRQs masked (FIQ is also masked for reset and FIQ). Seven branches.
@ The eighth vector, FIQ at 0x1C, is the first instruction of exception_handler.
_start:
	b reset_handler	@ 0x00 reset: Supervisor mode
	b exception_handler	@ 0x04 undefined instruction: Undefined mode
	b swi_handler	@ 0x08 SWI: Supervisor mode
	b exception_handler	@ 0x0C prefetch abort: Abort mode
	b exception_handler	@ 0x10 data abort: Abort mode
	b exception_handler	@ 0x14 reserved (no exception uses it on the ARM7TDMI)
	b irq_handler	@ 0x18 IRQ: IRQ mode
	.balign 4
@ undefined, aborts and FIQ: to the cartridge debugger if enabled, else return
@
@ exception_handler: the undefined-instruction, abort and FIQ handler (it starts at
@ the FIQ vector). reset_handler also goes here on a reset after boot.
@ In:  the mode of the exception (Undefined, Abort or FIQ), and its registers as the
@      exception left them. From reset_handler: the mode of the code that jumped to 0.
@      System and User mode have no SPSR, so the ARM architecture leaves undefined what
@      mrs/msr SPSR and the final subs pc do there (not followed). The sp that is set
@      is the System/User sp.
@ Does: sets the sp of that mode to STACK_EXC, and saves r12, lr, SPSR and CPSR below
@      it, in 0x03007FE0-0x03007FEF (GBATEK: the "Debug Exception Stack", 4 words).
@      If header byte 0x9C is 0xA5 (GBATEK: bits 2 and 7, debugging enabled), calls the
@      cartridge debug handler in ARM state: 0x09FE2000 if header byte 0xB4 has bit 7
@      set, else 0x09FFC000. (GBATEK: 1 Mbit or 8 Mbit of DACS, the Nintendo debugger
@      memory. Normal cartridges have nothing there.) The debug handler starts with
@      r12 = 0x08000000, sp = 0x03007FE0 and lr = exception_return. The other registers
@      are as the exception left them.
@ Out: exception_return: returns to lr - 4 with CPSR = the saved SPSR. By the ARM7TDMI
@      lr rules (not run here), lr - 4 is:
@        FIQ                        the next instruction
@        prefetch abort             the aborted instruction
@        data abort                 the instruction after the aborted one
@        ARM undefined instruction  the undefined instruction, so it traps again
exception_handler:
	ldr sp, stack_tops + 12	@ =STACK_EXC
	push {ip, lr}
	mrs ip, SPSR
	mrs lr, CPSR
	push {ip, lr}	@ 0x03007FE0: SPSR, CPSR, r12, lr
	mov ip, #0x8000000	@ the cartridge header
	ldrb lr, [ip, #0x9C]
	cmp lr, #0xA5	@ debugging enabled?
	bne exception_return	@ no: return immediately
	ldrbeq lr, [ip, #0xB4]
	andseq lr, lr, #0x80	@ Z set if bit 7 of header byte 0xB4 is clear
	adr lr, exception_return	@ the debug handler returns here
	ldrne pc, dacs_1mbit_entry	@ =0x09FE2000 (bit 7 set)
	ldreq pc, dacs_8mbit_entry	@ =0x09FFC000 (bit 7 clear)
	.balign 4
@ exception_return: the exit of exception_handler, and the return address of the debug
@ handler. Restores SPSR, r12 and lr from the four saved words and returns to lr - 4.
exception_return:
	@ sp = 0x03007FE0 again, where the four words are. This is the value of STACK_SVC
	ldr sp, stack_tops + 8	@ =STACK_SVC
	pop {ip, lr}	@ ip = the saved SPSR, lr = the saved CPSR (not used)
	msr SPSR_fc, ip	@ restore SPSR, also if the debugger changed it
	pop {ip, lr}	@ r12 and lr of the exception
	subs pc, lr, #4	@ return, CPSR = SPSR
	.balign 4
@ reset_handler: the reset vector (power-on, and any jump to 0).
@ POSTFLG (0x04000300) is 0 at power-on. boot_intro sets it to 1 (GBATEK: "First Boot
@ Flag").
@   0: a first boot. Falls into HardReset.
@   1: the BIOS booted before, so this is a jump to 0. Masks IRQ and FIQ in the current
@      mode and goes to exception_handler. That goes to the cartridge debugger if the
@      header enables one (GBATEK: a debugger can then do a reduced boot), else returns
@      to lr - 4.
reset_handler:
	cmp lr, #0
	moveq lr, #4	@ lr 0 -> 4: then lr - 4 is 0, not 0xFFFFFFFC (why: inferred)
	mov ip, #0x4000000
	ldrb ip, [ip, #0x300]	@ POSTFLG
	teq ip, #1
	mrseq ip, CPSR	@ booted before: set I and F (0xC0) in the current mode
	orreq ip, ip, #0xC0
	msreq CPSR_fc, ip
	beq exception_handler	@ then handle it as an exception
	.balign 4
@ SWI 0x26
@
@ HardReset SWI 0x26 (undocumented): a full reboot with the intro, about 2 seconds
@ (GBATEK). Also the first-boot path: reset_handler falls through into it.
@ Does: sets System mode with IRQ and FIQ masked, and IME = 0. Calls reset_stacks (sets
@      the stacks, zeroes 0x03007E00-0x03007FFF). Sets INTR_VECTOR = boot_irq. Then
@      jumps to boot_intro in Thumb with lr = SoftReset, so the cartridge starts when
@      the intro returns. Never returns. As a SWI, it discards what swi_handler saved
@      on the SVC stack.
HardReset:
	mov r0, #0xDF	@ System mode, IRQ and FIQ masked
	msr CPSR_fc, r0
	mov r4, #0x4000000	@ r4 = 0x04000000: the I/O base, also an input to reset_stacks
	strb r4, [r4, #0x208]	@ IME = 0 (the low byte of 0x04000000)
	bl reset_stacks	@ returns in System mode: IRQs unmasked in CPSR, but IME = 0
	adr r0, boot_irq
	str r0, [sp, #0xFC]	@ sp = STACK_USR (0x03007F00); +0xFC = INTR_VECTOR
	ldr r0, boot_entry_pointer	@ =boot_intro + 1
	adr lr, SoftReset	@ boot_intro returns into SoftReset
	bx r0	@ to boot_intro, Thumb
	.balign 4
@ SWI 0x00
@
@ SoftReset SWI 0x00: resets the stacks and jumps to the cartridge or to EWRAM.
@ boot_intro also returns here, through the lr that HardReset sets.
@ In:  SOFT_RESET_FLAG (0x03007FFA), read before it is cleared: 0 = start the
@      cartridge at 0x08000000, other values = 0x02000000, EWRAM (GBATEK).
@ Does: reset_stacks: sets the SVC and IRQ sp, zeroes their lr and SPSR, sets the
@      System sp, zeroes 0x03007E00-0x03007FFF. Then sets r0-r12 = 0, and System mode
@      with IRQ and FIQ unmasked in CPSR (IME does not change). Then bx lr to the
@      entry, ARM state. Never returns. As a SWI, it discards what swi_handler saved
@      on the SVC stack. GBATEK gives the same description.
SoftReset:
	mov r4, #0x4000000	@ 0x04000000: the I/O base, and the top of the IWRAM mirror
	ldrb r2, [r4, #-6]	@ 0x03FFFFFA = SOFT_RESET_FLAG
	bl reset_stacks
	cmp r2, #0
	@ r0-r12 = 0: the 13 words below 0x04000000 (0x03FFFFCC-0x03FFFFFF) are now zero
	ldmdb r4, {r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, sl, fp, ip}
	movne lr, #0x2000000	@ flag set: EWRAM
	moveq lr, #0x8000000	@ flag clear: the cartridge
	mov r0, #0x1F	@ System mode, IRQ and FIQ unmasked
	msr CPSR_fc, r0
	mov r0, #0
	bx lr	@ at 0x00DC: it fetches 0x00E4, which BIOS reads return after this
	.balign 4
@ sets the SVC, IRQ and System stacks, and clears 0x03007E00-0x03007FFF
@
@ reset_stacks: called with bl by HardReset and SoftReset.
@ In:  r4 = 0x04000000 (the base for clear_bios_ram). System mode: the return uses the
@      System lr, because the function zeroes the Supervisor and IRQ lr.
@ Out: System mode, IRQ unmasked and FIQ masked in CPSR (0x5F), sp = STACK_USR.
@      Supervisor: sp = STACK_SVC, lr = 0, SPSR = 0. IRQ: sp = STACK_IRQ, lr = 0,
@      SPSR = 0. 0x03007E00-0x03007FFF = 0. r0 = 0, r1 = 0.
reset_stacks:
	mov r0, #0xD3	@ Supervisor mode, IRQ and FIQ masked
	msr CPSR_fc, r0	@ 0x00E4: 0xE129F000, read from outside after startup and SoftReset
	ldr sp, stack_tops + 8	@ =STACK_SVC
	mov lr, #0
	msr SPSR_fc, lr
	mov r0, #0xD2	@ IRQ mode, IRQ and FIQ masked
	msr CPSR_fc, r0
	ldr sp, stack_tops + 4	@ =STACK_IRQ
	mov lr, #0
	msr SPSR_fc, lr
	mov r0, #0x5F	@ System mode, IRQ unmasked, FIQ masked
	msr CPSR_fc, r0
	ldr sp, stack_tops	@ =STACK_USR
	adr r0, clear_bios_ram + 1	@ continue in Thumb
	bx r0
@ clear_bios_ram: the Thumb tail of reset_stacks. Zeroes the 0x200 bytes at
@ 0x03007E00-0x03007FFF through the mirror (0x04000000 - 0x200 to 0x04000000 - 4),
@ then bx lr to the caller of reset_stacks. Needs r4 = 0x04000000.
clear_bios_ram:
	.thumb
	movs r0, #0
	ldr r1, bios_ram_clear_offset	@ =0xFFFFFE00 (-0x200): the offset from 0x04000000
clear_bios_ram_loop:
	str r0, [r4, r1]	@ 0x03FFFE00 + i = 0x03007E00 + i
	.inst.n 0x1D09	@ adds r1, r1, #4
	blt clear_bios_ram_loop	@ until the offset reaches 0
	bx lr
	.arm
	.balign 4
@ pushes r0-r3, r12, lr and calls [0x03007FFC]
@
@ irq_handler: the handler for every IRQ. IRQ mode, IRQs masked, on the IRQ stack
@ (6 words each time).
@ Calls the routine at INTR_VECTOR (0x03007FFC) with lr = irq_return. Then restores
@ r0-r3, r12 and lr, and returns to the interrupted code (GBATEK lists this code as it
@ is). The routine must be ARM code (ldr pc does not change state on the ARM7TDMI).
@ It must acknowledge IF itself, and it returns with bx lr. During the intro, the
@ routine is boot_irq, set by HardReset.
irq_handler:
	push {r0, r1, r2, r3, ip, lr}
	mov r0, #0x4000000
	adr lr, irq_return
	ldr pc, [r0, #-4]	@ 0x03FFFFFC: INTR_VECTOR, through the mirror
	.balign 4
@ irq_return: the return address (lr) of the game IRQ handler. Restores what
@ irq_handler saved and exits the IRQ.
irq_return:
	pop {r0, r1, r2, r3, ip, lr}
	subs pc, lr, #4	@ return, CPSR = SPSR (0x013C: 0xE25EF004, read during an IRQ)
	.balign 4
@ swi_handler: the handler for every SWI. Supervisor mode, IRQs masked, lr = the
@ address after the SWI instruction, SPSR = the CPSR of the caller.
@ The SWI number is the byte at lr - 2. For a Thumb swi, that is the full comment field
@ (0xDFnn). For an ARM swi, it is bits 16-23 of the comment field, so ARM code writes
@ SWI n << 16 (GBATEK). The number is not range-checked: see the top of this file.
@ The handler saves r11, r12, lr and SPSR on the Supervisor stack (4 words, GBATEK).
@ Then it goes to System mode with only the I bit of the caller (FIQ unmasked), and
@ saves r2 and the System lr on the System stack. Thus a SWI function:
@   - runs in System mode on the stack of the caller
@   - can be interrupted if the caller had IRQs enabled
@   - can change r2, r11, r12 and lr: all four are restored
@   - returns its results in r0, r1 and r3
@   - keeps r4-r10 itself
@ The function is called with bx (bit 0 of the entry selects Thumb) and lr = swi_return.
@ A SWI from inside a SWI or an IRQ handler uses 4 more words of the 64-byte
@ Supervisor stack each time (GBATEK).
swi_handler:
	push {fp, ip, lr}	@ Supervisor stack: r11, r12, the return address
	ldrb ip, [lr, #-2]	@ the SWI number (0x0144: 0xE55EC002, read after an IRQ)
	adr fp, swi_table
	ldr ip, [fp, ip, lsl #2]	@ ip = swi_table[n], unchecked
	mrs fp, SPSR	@ the CPSR of the caller
	stmfd sp!, {fp}	@ save it too
	and fp, fp, #0x80	@ keep only its IRQ-disable bit
	orr fp, fp, #0x1F	@ System mode, FIQ unmasked, ARM
	msr CPSR_fc, fp
	push {r2, lr}	@ System stack: r2 and the System/User lr of the caller
	adr lr, swi_return
	bx ip	@ to the function, ARM or Thumb by bit 0
	.balign 4
@ swi_return: the return address of every SWI function. Undoes swi_handler and returns
@ to the caller in its own mode and state. r0, r1 and r3 are the function results.
swi_return:
	pop {r2, lr}	@ restore r2 and the lr of the caller
	mov ip, #0xD3	@ Supervisor mode, IRQ and FIQ masked
	msr CPSR_fc, ip
	ldmfd sp!, {fp}
	msr SPSR_fc, fp	@ the CPSR of the caller
	pop {fp, ip, lr}
	movs pc, lr	@ return after the SWI, CPSR = SPSR (at 0x0188: fetches 0x0190)
	.balign 4
@ DISPCNT bit 3, then halt: the switch to Game Boy Color mode
@
@ enter_cgb_mode: the last step of start_cgb_cartridge (system.s), through
@ thumb_enter_cgb_mode (data.s). Sets DISPCNT = 0x0408:
@   bit 3   CGB mode (GBATEK: only BIOS opcodes can set it)
@   bit 10  BG2 on
@ (The GBATEK CGB-mode summary says bit 14 for BG2. Its DISPCNT table, and this code,
@ say bit 10.) Then it falls into Halt. GBATEK: the HALTCNT write applies the switch,
@ and the ARM probably stops permanently. Not expected to return: a literal pool
@ follows the bl of its caller.
enter_cgb_mode:
	mov ip, #0x4000000
	mov r2, #4	@ 0x0190: 0xE3A02004, read from outside after any SWI
	strb r2, [ip, #1]	@ DISPCNT high byte = 0x04: BG2 on
	mov r2, #8
	strb r2, [ip]	@ DISPCNT low byte = 0x08: CGB mode (BG mode 0, forced blank off)
	.balign 4
@ SWI 0x02
@
@ Halt SWI 0x02: HALTCNT = 0x00. The CPU waits until (IE AND IF) is not zero, for all
@ values of IME and the CPSR I bit (GBATEK). Through the SWI, all registers are kept.
@ When called directly (thumb_Halt), r2 and ip change.
Halt:
	mov r2, #0	@ 0x00: halt
	b CustomHalt
	.balign 4
@ SWI 0x03
@
@ Stop SWI 0x03: HALTCNT = 0x80. Very low power: the clocks, sound, video, DMA and
@ timers stop. Only a keypad, Game Pak or SIO interrupt enabled in IE ends it
@ (GBATEK: turn the display off first). Falls into CustomHalt.
Stop:
	mov r2, #0x80	@ 0x80: stop
	.balign 4
@ SWI 0x27
@
@ CustomHalt SWI 0x27 (undocumented): HALTCNT = the low byte of r2 (GBATEK: 0x00 halt,
@ 0x80 stop, other values unknown). Returns when the CPU wakes. Also the tail of Halt
@ and Stop. ip changes.
CustomHalt:
	mov ip, #0x4000000
	strb r2, [ip, #0x301]	@ HALTCNT
	bx lr
	.balign 4
@ the stack tops: System, IRQ, Supervisor and the exception handler
@
@ stack_tops: the initial sp of each mode, read by ldr with an offset.
stack_tops:
	.4byte STACK_USR	@ +0  0x03007F00: System/User (reset_stacks)
	.4byte STACK_IRQ	@ +4  0x03007FA0: IRQ (reset_stacks)
	.4byte STACK_SVC	@ +8  0x03007FE0: Supervisor (reset_stacks), also exception_return
	.4byte STACK_EXC	@ +12 0x03007FF0: any mode that exception_handler runs in
	.balign 4
@ swi_table: the SWI functions by number: 43 entries, 0x00-0x2A, read by swi_handler.
@ + 1 marks Thumb code. The names are from GBATEK, but GBATEK calls 0x20-0x24
@ SoundWhatever0-4: this file uses the names from the MP2000 music player.
@ Nothing stops a number after 0x2A: SWI 0x2B-0x2E jump to the four words after the
@ table, and the others jump into system.s and header.s (see the top of this file).
swi_table:
	.4byte SoftReset	@ 0x00 ARM
	.4byte RegisterRamReset + 1	@ 0x01 Thumb
	.4byte Halt	@ 0x02 ARM
	.4byte Stop	@ 0x03 ARM
	.4byte IntrWait	@ 0x04 ARM
	.4byte VBlankIntrWait	@ 0x05 ARM
	.4byte Div	@ 0x06 ARM
	.4byte DivArm	@ 0x07 ARM
	.4byte Sqrt	@ 0x08 ARM
	.4byte ArcTan	@ 0x09 ARM
	.4byte ArcTan2 + 1	@ 0x0A Thumb
	.4byte CpuSet + 1	@ 0x0B Thumb
	.4byte CpuFastSet	@ 0x0C ARM
	.4byte GetBiosChecksum	@ 0x0D ARM
	.4byte BgAffineSet	@ 0x0E ARM
	.4byte ObjAffineSet	@ 0x0F ARM
	.4byte BitUnPack	@ 0x10 ARM
	.4byte LZ77UnCompWram	@ 0x11 ARM
	.4byte LZ77UnCompVram	@ 0x12 ARM
	.4byte HuffUnComp	@ 0x13 ARM
	.4byte RLUnCompWram + 1	@ 0x14 Thumb
	.4byte RLUnCompVram + 1	@ 0x15 Thumb
	.4byte Diff8bitUnFilterWram + 1	@ 0x16 Thumb
	.4byte Diff8bitUnFilterVram + 1	@ 0x17 Thumb
	.4byte Diff16bitUnFilter + 1	@ 0x18 Thumb
	.4byte SoundBias + 1	@ 0x19 Thumb
	.4byte SoundDriverInit + 1	@ 0x1A Thumb
	.4byte SoundDriverMode + 1	@ 0x1B Thumb
	.4byte SoundDriverMain + 1	@ 0x1C Thumb
	.4byte SoundDriverVSync + 1	@ 0x1D Thumb
	.4byte SoundChannelClear + 1	@ 0x1E Thumb
	.4byte MidiKey2Freq + 1	@ 0x1F Thumb
	.4byte MusicPlayerOpen + 1	@ 0x20 Thumb (GBATEK: SoundWhatever0)
	.4byte MusicPlayerStart + 1	@ 0x21 Thumb (SoundWhatever1)
	.4byte MusicPlayerStop + 1	@ 0x22 Thumb (SoundWhatever2)
	.4byte MusicPlayerContinue + 1	@ 0x23 Thumb (SoundWhatever3)
	.4byte MusicPlayerFadeOut + 1	@ 0x24 Thumb (SoundWhatever4)
	.4byte MultiBoot + 1	@ 0x25 Thumb
	.4byte HardReset	@ 0x26 ARM
	.4byte CustomHalt	@ 0x27 ARM
	.4byte SoundDriverVSyncOff + 1	@ 0x28 Thumb
	.4byte SoundDriverVSyncOn + 1	@ 0x29 Thumb
	.4byte SoundGetJumpList + 1	@ 0x2A Thumb
	.balign 4
@ where exception_handler goes when the header has 0xA5 at 0x9C
@
@ The literals after the table. Each one is also the jump address of an undefined SWI:
@   SWI 0x2B  dacs_1mbit_entry
@   SWI 0x2C  dacs_8mbit_entry
@   SWI 0x2D  boot_entry_pointer
@   SWI 0x2E  bios_ram_clear_offset
dacs_1mbit_entry:
	@ the cartridge debugger entry if header byte 0xB4 has bit 7 set (GBATEK: 1 Mbit DACS)
	.4byte 0x09FE2000
dacs_8mbit_entry:
	@ the cartridge debugger entry if bit 7 is clear (GBATEK: 8 Mbit DACS)
	.4byte 0x09FFC000
boot_entry_pointer:
	@ HardReset: the jump into the intro, Thumb (+ 1). SWI 0x2D would run the intro as a
	@ SWI function (read from the code, not run)
	.4byte boot_intro + 1
bios_ram_clear_offset:
	@ -0x200: the first offset of clear_bios_ram from 0x04000000. Through the mirror,
	@ the clear starts at 0x03007E00. SWI 0x2E jumps to 0xFFFFFE00
	.4byte 0xFFFFFE00
