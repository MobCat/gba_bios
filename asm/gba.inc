@ gba.inc: names for the hardware around the BIOS: its memory, its I/O
@ registers, and the RAM that the BIOS keeps for itself. Only .equ definitions:
@ this file assembles to nothing. The names are from GBATEK, except in the IWRAM
@ section, which uses the names of this project.

@ ---------------------------------------------------------------------------
@ Memory
@ ---------------------------------------------------------------------------
	.equ EWRAM,             0x02000000      @ 256 KiB, on the board
	.equ IWRAM,             0x03000000      @ 32 KiB, in the CPU
	.equ IO,                0x04000000
	.equ PLTT,              0x05000000      @ palettes: 256 BG colours, then 256 OBJ
	.equ OBJ_PLTT,          0x05000200
	.equ VRAM,              0x06000000
	.equ OBJ_VRAM,          0x06010000      @ sprite tiles, in the tile modes
	.equ OAM,               0x07000000      @ attributes of 128 sprites, and the affine parameters
	.equ ROM,               0x08000000      @ the cartridge: the header is the first 0xC0 bytes

@ ---------------------------------------------------------------------------
@ The RAM that the BIOS uses (GBATEK, "BIOS RAM Usage"): the top of IWRAM.
@ The BIOS also gets to it through the mirror at 0x03FFFFxx. Thus the IRQ
@ handler finds INTR_VECTOR at 0x04000000 - 4.
@ ---------------------------------------------------------------------------
	.equ STACK_USR,         0x03007F00      @ System/User stack top. 0x03000000-0x03007EFF is for the game
	.equ STACK_IRQ,         0x03007FA0      @ IRQ stack top
	.equ STACK_SVC,         0x03007FE0      @ Supervisor stack top
	.equ STACK_EXC,         0x03007FF0      @ stack top of the exception handler
	.equ SOUND_AREA_PTR,    0x03007FF0      @ word: the sound work area (SoundDriverInit)
	.equ INTRO_FLAG,        0x03007FF7      @ byte: reserved, intro/Nintendo logo related
	.equ INTR_CHECK,        0x03007FF8      @ hword: IRQ flags for IntrWait, set by the game IRQ handler
	.equ SOFT_RESET_FLAG,   0x03007FFA      @ byte: SoftReset starts at 0x02000000 if set, else 0x08000000
	.equ MULTIBOOT_FLAG,    0x03007FFB      @ byte: reserved, intro/MultiBoot slave related
	.equ INTR_VECTOR,       0x03007FFC      @ word: the game IRQ handler (ARM code)
	.equ BIOS_RAM,          0x03007E00      @ 0x200 bytes: reset_stacks zeroes them, RegisterRamReset never does
	.equ BIOS_RAM_MIRROR,   0x03FFFFF0      @ 0x03007FF0 (STACK_EXC) in the IWRAM mirror: base of the intro flags

@ ---------------------------------------------------------------------------
@ IWRAM that the BIOS uses while it boots. This is game memory:
@ RegisterRamReset clears it before the game gets it. Found by reading the
@ code (not in the GBATEK list).
@ ---------------------------------------------------------------------------
	.equ MB_SLAVE,          0x0300000C      @ the slave work area for MultiBoot, to 0x03000063 (multiboot.s)
	.equ HEADER_COPY_BASE,  0x03000064      @ HEADER_COPY - 0x24: the intro and the slave add 0x24 to this base
	.equ HEADER_COPY,       0x03000088      @ header bytes 0x04-0xDF, copied by copy_cart_header
	.equ WORK_BUF_A,        0x03000564      @ 4 KiB where the intro decompresses the art and the logo
	.equ LOGO_BITS,         0x03000588      @ WORK_BUF_A + 0x24: the header logo bytes, after logo_tree
	.equ WORK_BUF_B,        0x03001564      @ the other 4 KiB decode buffer
	.equ LETTER_TIMERS,     0x03003564      @ 7 words: frames since each letter started
	.equ LETTER_STATES,     0x03003580      @ 7 x 16 bytes: X, Y and depth of each letter
	.equ LETTER_AFFINE,     0x030035F0      @ 7 x 20 bytes: a BgAffineSet source entry for each letter
	.equ INTRO_PLAYER0,     0x030036EC      @ music player 0: song_intro, song_intro_end
	.equ INTRO_PLAYER0_TRACKS, 0x0300372C   @ its 6 tracks, 0x50 bytes each
	.equ INTRO_PLAYER1,     0x0300390C      @ music player 1: the Select+Start, button and MultiBoot songs
	.equ INTRO_PLAYER1_TRACKS, 0x0300394C   @ its 6 tracks
	.equ INTRO_SOUND_AREA,  0x03003B2C      @ the sound work area, 0xFB0 bytes (sound.s)

	.equ SOUND_IDENT,       0x68736D53      @ "Smsh": ID word of the sound work area when set up and idle

@ ---------------------------------------------------------------------------
@ I/O registers
@ ---------------------------------------------------------------------------
	.equ REG_DISPCNT,       0x04000000
	.equ REG_DISPSTAT,      0x04000004
	.equ REG_VCOUNT,        0x04000006
	.equ REG_BG0CNT,        0x04000008
	.equ REG_BG1CNT,        0x0400000A
	.equ REG_BG2CNT,        0x0400000C
	.equ REG_BG3CNT,        0x0400000E
	.equ REG_BG0HOFS,       0x04000010
	.equ REG_BG0VOFS,       0x04000012
	.equ REG_BG1HOFS,       0x04000014
	.equ REG_BG1VOFS,       0x04000016
	.equ REG_BG2HOFS,       0x04000018
	.equ REG_BG2VOFS,       0x0400001A
	.equ REG_BG3HOFS,       0x0400001C
	.equ REG_BG3VOFS,       0x0400001E
	.equ REG_BG2PA,         0x04000020
	.equ REG_BG2PB,         0x04000022
	.equ REG_BG2PC,         0x04000024
	.equ REG_BG2PD,         0x04000026
	.equ REG_BG2X,          0x04000028
	.equ REG_BG2Y,          0x0400002C
	.equ REG_BG3PA,         0x04000030
	.equ REG_BG3PB,         0x04000032
	.equ REG_BG3PC,         0x04000034
	.equ REG_BG3PD,         0x04000036
	.equ REG_BG3X,          0x04000038
	.equ REG_BG3Y,          0x0400003C
	.equ REG_WIN0H,         0x04000040
	.equ REG_WIN1H,         0x04000042
	.equ REG_WIN0V,         0x04000044
	.equ REG_WIN1V,         0x04000046
	.equ REG_WININ,         0x04000048
	.equ REG_WINOUT,        0x0400004A
	.equ REG_MOSAIC,        0x0400004C
	.equ REG_BLDCNT,        0x04000050
	.equ REG_BLDALPHA,      0x04000052
	.equ REG_BLDY,          0x04000054

	.equ REG_SOUND1CNT_L,   0x04000060
	.equ REG_SOUND1CNT_H,   0x04000062
	.equ REG_SOUND1CNT_X,   0x04000064
	.equ REG_SOUND2CNT_L,   0x04000068
	.equ REG_SOUND2CNT_H,   0x0400006C
	.equ REG_SOUND3CNT_L,   0x04000070
	.equ REG_SOUND3CNT_H,   0x04000072
	.equ REG_SOUND3CNT_X,   0x04000074
	.equ REG_SOUND4CNT_L,   0x04000078
	.equ REG_SOUND4CNT_H,   0x0400007C
	.equ REG_SOUNDCNT_L,    0x04000080
	.equ REG_SOUNDCNT_H,    0x04000082
	.equ REG_SOUNDCNT_X,    0x04000084
	.equ REG_SOUNDBIAS,     0x04000088
	.equ REG_WAVE_RAM,      0x04000090
	.equ REG_FIFO_A,        0x040000A0
	.equ REG_FIFO_B,        0x040000A4

	.equ REG_DMA0SAD,       0x040000B0
	.equ REG_DMA0DAD,       0x040000B4
	.equ REG_DMA0CNT,       0x040000B8
	.equ REG_DMA1SAD,       0x040000BC
	.equ REG_DMA1DAD,       0x040000C0
	.equ REG_DMA1CNT,       0x040000C4
	.equ REG_DMA1CNT_H,     0x040000C6
	.equ REG_DMA2SAD,       0x040000C8
	.equ REG_DMA2DAD,       0x040000CC
	.equ REG_DMA2CNT,       0x040000D0
	.equ REG_DMA2CNT_H,     0x040000D2
	.equ REG_DMA3SAD,       0x040000D4
	.equ REG_DMA3DAD,       0x040000D8
	.equ REG_DMA3CNT,       0x040000DC

	.equ REG_TM0CNT,        0x04000100
	.equ REG_TM1CNT,        0x04000104
	.equ REG_TM2CNT,        0x04000108
	.equ REG_TM3CNT,        0x0400010C

	.equ REG_SIODATA32,     0x04000120      @ also SIOMULTI0-1
	.equ REG_SIOMULTI2,     0x04000124
	.equ REG_SIOMULTI3,     0x04000126
	.equ REG_SIOCNT,        0x04000128
	.equ REG_SIOMLT_SEND,   0x0400012A      @ also SIODATA8
	.equ REG_KEYINPUT,      0x04000130      @ buttons, 0 = pressed: A B Select Start Right Left Up Down R L
	.equ REG_KEYCNT,        0x04000132
	.equ REG_RCNT,          0x04000134
	.equ REG_JOYCNT,        0x04000140
	.equ REG_JOY_RECV,      0x04000150
	.equ REG_JOY_TRANS,     0x04000154
	.equ REG_JOYSTAT,       0x04000158

	.equ REG_IE,            0x04000200
	.equ REG_IF,            0x04000202
	.equ REG_WAITCNT,       0x04000204
	.equ REG_IME,           0x04000208
	.equ REG_POSTFLG,       0x04000300      @ 1 after boot. A reset with POSTFLG = 1 goes to the debug vector (GBATEK)
	.equ REG_HALTCNT,       0x04000301
