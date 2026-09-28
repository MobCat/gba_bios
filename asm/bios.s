@ The GBA BIOS source
@ main include
	.syntax unified
	.cpu arm7tdmi
	.section .text
	.include "asm/gba.inc"
	.include "asm/vectors.s"
	.include "asm/system.s"
	.include "asm/header.s"
	.include "asm/memory.s"
	.include "asm/affine.s"
	.include "asm/decompress.s"
	.include "asm/sound.s"
	.include "asm/intro.s"
	.include "asm/sound_driver.s"
	.include "asm/multiboot.s"
	.include "asm/data.s"
