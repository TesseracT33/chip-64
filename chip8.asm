arch n64.cpu
endian msb
output "chip64.z64", create

// Execution starts in PIF ROM. Consequently, the first $1000 bytes of the cartridge have been copied to SP DMEM ($A4000000),
// and execution continues at $A4000040. The $40 bytes skipped constitute the ROM header. The further $fc0 bytes is the boot code,
// part of the N64 ROM. The boot code will perform a DMA of length $100000 bytes from $10001000 (N64 ROM offset $1000) to the address
// specified in the header -- the word at byte offset 8. It will also write some code to the beginning of RDRAM before doing the DMA, 
// so the entry point should not be $80000000. $80001000 seems to work well, also offsetting exactly the size of the header + boot code.  
// After the DMA, the PC is set to this address.

constant N64_ROM_SIZE = $100000
fill N64_ROM_SIZE + $1000       // set rom size. minimum size (?) since the boot code will do a PI DMA of this size
origin $0                       // rom location
base $80000000                  // signed displacement against origin, used when computing the pc value for labels

include "n64.inc"
include "util.inc"

include "n64_header.asm"
include "n64_boot.asm"

constant pc = fp
constant index = k0
constant v = k1
constant ch8_mem = gp
constant ch8_sp = s7

constant CH8_HEIGHT = 32
constant CH8_WIDTH = 64
constant CH8_FRAMEBUFFER_SIZE = CH8_WIDTH * CH8_HEIGHT
constant CH8_INSTRS_PER_VSYNC = 10
constant CH8_MEM_SIZE = $1000
constant CH8_ROM_START_ADDR = $200
constant FONTSET_SIZE = $50
constant MAX_CH8_ROM_SIZE = CH8_MEM_SIZE - CH8_ROM_START_ADDR
constant N64_BPP = 2
constant N64_HEIGHT = 480
constant N64_STACK_SIZE = 10 * 1024
constant N64_WIDTH = 640
constant RDRAM_FRAMEBUFFER_ADDR = (RDRAM_ROM_ADDR + N64_ROM_SIZE + N64_STACK_SIZE) | $A0000000
constant RDRAM_STACK_ADDR = (RDRAM_ROM_ADDR + N64_ROM_SIZE + N64_STACK_SIZE - 8) | $80000000
constant RDRAM_ROM_ADDR = 0
constant RENDER_SCALE = 10
constant VI_V_SYNC_LINE = 512

constant N64_RENDER_OFFSET_Y = (N64_HEIGHT - CH8_HEIGHT * RENDER_SCALE) / 2

assert(CH8_WIDTH * RENDER_SCALE == N64_WIDTH)
assert(CH8_HEIGHT * RENDER_SCALE + 2 * N64_RENDER_OFFSET_Y == N64_HEIGHT)

start:
	li      sp, RDRAM_STACK_ADDR
	jal     init_n64
	nop
	jal     init_chip8
	nop
	jal     run
	nop
main_end:
	j       main_end
	nop

init_n64:  // void()
	// init MI
	lui     t0, MI_BASE
	ori     t1, zero, $388                 // Enable PI, SI, VI interrupts
	sw      t1, MI_MASK(t0)

	// init VI
	lui     t0, VI_BASE
	ori     t1, zero, $3302                // 5/5/5/3 colour mode; disable AA and resampling; set PIXEL_ADVANCE %0011
	sw      t1, VI_CTRL(t0)
	li      t1, RDRAM_FRAMEBUFFER_ADDR
	sw      t1, VI_ORIGIN(t0)
	ori     t1, zero, N64_WIDTH
	sw      t1, VI_WIDTH(t0)
	ori     t1, zero, VI_V_SYNC_LINE
	sw      t1, VI_V_INTR(t0)
	li      t1, $3e52239                   // NTSC standard?
	sw      t1, VI_BURST(t0)
	ori     t1, zero, $20d                 // NTSC, non-interlaced
	sw      t1, VI_V_SYNC(t0)
	li      t1, $c15                       // NTSC standard?
	sw      t1, VI_H_SYNC(t0)
	li      t1, $c150c15                   // NTSC standard?
	sw      t1, VI_H_SYNC_LEAP(t0)
	li      t1, $6c02ec
	sw      t1, VI_H_VIDEO(t0)
	li      t1, $2501ff
	sw      t1, VI_V_VIDEO(t0)
	li      t1, $e0204
	sw      t1, VI_V_BURST(t0)
	ori     t1, zero, $100*N64_WIDTH/160
	sw      t1, VI_X_SCALE(t0)
	ori     t1, zero, $100*N64_HEIGHT/60
	sw      t1, VI_Y_SCALE(t0)

	// install exception handler at $8000'0180
	la      t0, exception_handler_180
	li      t1, $80000180
	addi    t2, t0, exception_handler_180_end - exception_handler_180
install_exception_handler_loop:
	lw      t3, 0(t0)
	sw      t3, 0(t1)
	addi    t0, t0, 4
	bnel    t0, t2, install_exception_handler_loop
	addi    t1, t1, 4

	// enable interrupts
	ori     t0, zero, $1401
	mtc0    t0, CP0_STATUS                 // Set ie+im2+im4 (enable MI and 'reset' interrupts)

	jr      ra
	nop

exception_handler_180:  // void()
	addiu	sp, sp, -144  // TODO: also save 'at'?
	sd		v0, 0(sp)
	sd		v1, 8(sp)
	sd		a0, 16(sp)
	sd		a1, 24(sp)
	sd		a2, 32(sp)
	sd		a3, 40(sp)
	sd		t0, 48(sp)
	sd		t1, 56(sp)
	sd		t2, 64(sp)
	sd		t3, 72(sp)
	sd		t4, 80(sp)
	sd		t5, 88(sp)
	sd		t6, 96(sp)
	sd		t7, 104(sp)
	sd		t8, 112(sp)
	sd		t9, 120(sp)
	mflo	t0
	mfhi	t1
	sd		t0, 128(sp)
	sd	    t1, 136(sp)
	mfc0    t0, CP0_CAUSE
	andi    t1, t0, $7c                    // extract exc_code
	beq     t1, zero, handle_interrupt_exception
	nop                                    // TODO: handle remaining exceptions
	j		exception_handler_180_exit
	nop
handle_interrupt_exception:
	addiu   sp, sp, -8
	sd      ra, 0(sp)
	andi    t1, t0, $400                   // read ip2
	addiu   t1, t1, -$400
	bgezall t1, handle_mi_interrupt
	nop
	andi    t1, t0, $1000                  // read ip4
	addiu   t1, t1, -$1000
	bgezall t1, handle_system_reset_interrupt
	nop
	ld      ra, 0(sp)
	j		exception_handler_180_exit
	addiu   sp, sp, 8
handle_mi_interrupt:
	addiu   sp, sp, -8
	sd      ra, 0(sp)
	lui     t0, MI_BASE
	lw      t0, MI_INTERRUPT(t0)
	andi    t1, t0, 8                      // VI interrupt flag
	addiu   t1, t1, -8
	bgezall t1, handle_vi_interrupt
	nop                                    // TODO: handle remaining interrupts
	ld      ra, 0(sp)
	jr      ra
	addiu   sp, sp, 8
handle_system_reset_interrupt: // TODO
	jr      ra
	nop
handle_vi_interrupt:
	addiu   sp, sp, -8
	sd      ra, 0(sp)
	la      t0, got_v_sync
	ori     t1, zero, 1
	sb      t1, 0(t0)
	lui     t0, VI_BASE
	ori     t1, zero, VI_V_SYNC_LINE
	sw      t1, VI_V_CURRENT(t0)
	jal     render
	nop
	ld      ra, 0(sp)
	j       poll_input
	addiu   sp, sp, 8
exception_handler_180_exit:
	ld		t0, 128(sp)
	ld	    t1, 136(sp)
	mtlo	t0
	mthi	t1
	ld		v0, 0(sp)
	ld		v1, 8(sp)
	ld		a0, 16(sp)
	ld		a1, 24(sp)
	ld		a2, 32(sp)
	ld		a3, 40(sp)
	ld		t0, 48(sp)
	ld		t1, 56(sp)
	ld		t2, 64(sp)
	ld		t3, 72(sp)
	ld		t4, 80(sp)
	ld		t5, 88(sp)
	ld		t6, 96(sp)
	ld		t7, 104(sp)
	ld		t8, 112(sp)
	ld		t9, 120(sp)
	addiu	sp, sp, 144
	eret
exception_handler_180_end:

init_chip8:  // void()
	la      ch8_mem, ch8_memory
	
	// clear memory
	move    t0, ch8_mem
	addiu   t1, t0, CH8_MEM_SIZE
clear_ch8_memory_loop:
	sd      zero, 0(t0)
	addiu   t0, t0, 8
	bnel    t0, t1, clear_ch8_memory_loop
	nop

	// load fontset
	assert(FONTSET_SIZE % 8 == 0)
	move    t0, ch8_mem
	la      t1, fontset
	addiu   t2, t0, FONTSET_SIZE
load_fontset_loop:
	ld      t3, 0(t1)
	sd      t3, 0(t0)
	addiu   t0, t0, 8
	bnel    t0, t2, load_fontset_loop
	addiu   t1, t1, 8

	// load rom
	addiu   t0, ch8_mem, CH8_ROM_START_ADDR
	la      t1, ch8_rom
	addiu   t2, t0, CH8_ROM_SIZE
load_rom_loop:
	lb      t3, 0(t1)
	sb      t3, 0(t0)
	addiu   t0, t0, 1
	bnel    t0, t2, load_rom_loop
	addiu   t1, t1, 1

	// init chip8 registers
	ori     pc, zero, CH8_ROM_START_ADDR
	move    index, zero
	move    ch8_sp, zero
	ori     t0, zero, 60
	la      t1, delay_timer
	sb      t0, 0(t1)
	la      t1, sound_timer
	sb      t0, 0(t1)
	la      t0, stack
	sd      zero, 0(t0)
	sd      zero, 8(t0)
	sd      zero, 16(t0)
	sd      zero, 24(t0)
	la      t0, key
	sd      zero, 0(t0)
	sd      zero, 8(t0)
	la      v, v_data
	sd      zero, 0(v)
	sd      zero, 8(v)
	la      t0, needs_render
	lb      zero, 0(t0)

	j       clear_framebuffer
	nop

clear_framebuffer:  // void()
	la      t0, ch8_framebuffer
	addiu   t1, t0, CH8_FRAMEBUFFER_SIZE-8
clear_framebuffer_loop:
	sd      zero, 0(t0)
	bnel    t0, t1, clear_framebuffer_loop
	addiu   t0, t0, 8
	la      t0, needs_render
	ori		t1, zero, 1
	jr      ra
	lb      t1, 0(t0)

poll_input:  // void()
	// write to start of PIF RAM bytes 0-2, 7
	// byte 0: command length (1)
	// byte 1: result length (4)
	// byte 2: command (1; Controller State)
	// byte 7: signal end of commands ($fe)
	lui     t0, $bfc0
	li      t1, $01040100
	sw      t1, $7c0(t0)
	ori     t1, zero, $fe
	sw      t1, $7c4(t0)

	// write 1 to the PIF RAM control byte (offset $3f), triggering the joybus protocol
	ori     t1, zero, 1
	sw      t1, $7fc(t0)

	// TODO: how long to wait before reading result?

	// read the result (bytes 3-6), being the controller state. best to stick to aligned word reads here (?)
	// byte 3: A B Z S dU dD dL dR
	// byte 4: RST - LT RT cU cD cL cR
	// byte 5: x-axis
	// byte 6: y-axis
	lw      t1, $7c0(t0)
	lw      t2, $7c4(t0)
	la      t3, key
	andi    t4, t1, 1
	sb      t4, 0(t3)   // dR
	srl     t1, t1, 1
	andi    t4, t1, 1
	sb      t4, 1(t3)   // dL
	srl     t1, t1, 1
	andi    t4, t1, 1
	sb      t4, 2(t3)   // dD
	srl     t1, t1, 2
	andi    t4, t1, 1
	sb      t4, 3(t3)   // dU
	srl     t1, t1, 1
	andi    t4, t1, 1
	sb      t4, 4(t3)   // S
	srl     t1, t1, 1
	andi    t4, t1, 1
	sb      t4, 5(t3)   // Z
	srl     t1, t1, 1
	andi    t4, t1, 1
	sb      t4, 6(t3)   // B
	srl     t1, t1, 1
	andi    t4, t1, 1
	sb      t4, 7(t3)   // A
	srl     t2, t2, 24
	andi    t4, t2, 1
	sb      t4, 8(t3)   // cR
	srl     t2, t2, 1
	andi    t4, t2, 1
	sb      t4, 9(t3)   // cL
	srl     t2, t2, 1
	andi    t4, t2, 1
	sb      t4, 10(t3)   // cD
	srl     t2, t2, 1
	andi    t4, t2, 1
	sb      t4, 11(t3)   // cU
	srl     t2, t2, 1
	andi    t4, t2, 1
	sb      t4, 12(t3)   // RT
	srl     t2, t2, 1
	andi    t4, t2, 1
	sb      t4, 13(t3)   // LT
	jr      ra
	nop

await_input:  // byte() -- returns the index of the next key pressed
	jr      ra // TODO
	nop

render:  // void()
	la      t0, needs_render
	lb      t1, 0(t0)
	bnel    t1, zero, render_start
	sb      zero, 0(t0)
	jr      ra
render_start:
	la      t0, ch8_framebuffer
	addiu   t1, t0, CH8_FRAMEBUFFER_SIZE
	li      t2, RDRAM_FRAMEBUFFER_ADDR + N64_RENDER_OFFSET_Y * N64_WIDTH * N64_BPP
render_loop:
	lb      t3, 0(t0)  // src either 0 or $ff; sign-extend to 0 or $ffff... for 5/5/5/3
	lb      t4, 1(t0)  // two ch8 pixels at a time, for more efficient storing
	move    t5, t2
	addiu   t6, t2, N64_WIDTH * N64_BPP * (RENDER_SCALE - 1)
render_loop_n64_y:
	sd      t3, 0(t5)
	sd      t3, 8(t5)
	sw      t3, 16(t5) // 20 bytes for 10 5/5/5/3 pixels
	sw      t4, 20(t5)
	sd      t4, 24(t5)
	sd      t4, 32(t5)
	bnel    t5, t6, render_loop_n64_y    // render the current ch8 pixels vertically repeatedly
	addiu   t5, t5, N64_WIDTH * N64_BPP
	addiu   t0, t0, 2                            // advance two ch8 pixels
	andi    t7, t0, CH8_WIDTH - 1
	beql    t7, zero, new_ch8_y_line
	addiu   t2, t2, N64_WIDTH * N64_BPP * (RENDER_SCALE - 1)
new_ch8_y_line:
	bnel    t0, t1, render_loop
	addiu   t2, t2, 2 * N64_BPP * RENDER_SCALE   // advance two ch8 pixels
	jr      ra
	nop

run:  // void()
	addiu    sp, sp, -16
	sd       ra, 0(sp)
	sd       s0, 8(sp)
run_loop:
	li       s0, CH8_INSTRS_PER_VSYNC
step_cycle_loop:
	jal      step_cycle
	addiu    s0, s0, -1
	bnel     s0, zero, step_cycle_loop
	nop
update_delay_timer:
	la       t0, delay_timer
	lbu      t1, 0(t0)
	beq      t1, zero, update_sound_timer
	addiu    t1, t1, -1
	sb       t1, 0(t0)
update_sound_timer:
	la       t0, sound_timer
	lbu      t1, 0(t0)
	beq      t1, zero, await_v_sync
	addiu    t1, t1, -1
	addiu    t2, t1, -1
	bltzal   t2, play_audio
	sb       t1, 0(t0)
await_v_sync:
	la       t0, got_v_sync
	lb       t1, 0(t0)
	beq      t1, zero, await_v_sync
	nop
	sb       zero, 0(t0)
check_stop_run:
	la       t0, do_run
	lb       t0, 0(t0)
	bnel     t0, zero, run_loop
	nop
stop_run:
	ld       ra, 0(sp)
	ld       s0, 8(sp)
	jr       ra
	addiu    sp, sp, 16

step_cycle:  // void()
	andi    t0, pc, 1
	beq     t0, zero, fetch_instr_even_pc
	addu    t0, ch8_mem, pc
	lbu     t1, 0(t0)
	sll     t1, t1, 8
	addiu   pc, pc, 1
	andi    pc, pc, $fff
	addu    t0, ch8_mem, pc
	lbu     a0, 0(t0)
	or      a0, a0, t1
	j       decode_and_exec_instr
	addiu   pc, pc, 1
fetch_instr_even_pc:
	lhu     a0, 0(t0)
	addiu   pc, pc, 2
decode_and_exec_instr:
	srl     t0, a0, 10
	andi    t0, t0, $3c
	la      t1, instr_jump_table
	addu    t1, t1, t0
	lw      t1, 0(t1)
	jr      t1
	andi    pc, pc, $fff

opcode_0nnn:  // void(hword opcode)
	// 00E0; CLS -- Clear the display
	ori     t0, zero, $e0
	beq     t0, a0, clear_framebuffer
	
	// opcode != $00EE => panic
	ori     t0, zero, $ee
	bne     t0, a0, panic

	// 00EE; RET -- Return from subroutine
	la      t0, stack
	addu    t0, t0, ch8_sp
	lhu     pc, 0(t0)
	addiu   ch8_sp, ch8_sp, -2
	jr      ra
	andi    ch8_sp, ch8_sp, $1f

// JP addr -- Jump to location nnn
opcode_1nnn:  // void(hword opcode)
	jr      ra
	andi    pc, a0, $fff

// CALL addr -- Call subroutine at nnn
opcode_2nnn:  // void(hword opcode)
	addiu   ch8_sp, ch8_sp, 2
	andi    ch8_sp, ch8_sp, $1f
	la      t0, stack
	addu    t0, t0, ch8_sp
	sh      pc, 0(t0)
	jr      ra
	andi    pc, a0, $fff

// SE Vx, byte -- Skip next instruction if Vx == nn
opcode_3xnn:  // void(hword opcode)
	srl     t0, a0, 8
	andi    t0, t0, $f
	addu    t0, t0, v
	lbu     t0, 0(t0)
	andi    t1, a0, $ff
	beql    t0, t1, opcode_3xnn_end
	addiu	pc, pc, 2
opcode_3xnn_end:
	jr      ra
	andi	pc, pc, $fff

// SNE Vx, byte -- Skip next instruction if Vx != nn
opcode_4xnn:  // void(hword opcode)
	srl     t0, a0, 8
	andi    t0, t0, $f
	addu    t0, t0, v
	lbu     t0, 0(t0)
	andi    t1, a0, $ff
	bnel    t0, t1, opcode_4xnn_end
	addiu	pc, pc, 2
opcode_4xnn_end:
	jr      ra
	andi	pc, pc, $fff

// SE Vx, Vy -- Skip next instruction if Vx == Vy.
opcode_5xy0:  // void(hword opcode)
	// Get Vx
	srl     t0, a0, 8
	andi    t0, t0, $f
	addu    t0, t0, v
	lb      t0, 0(t0)

	// Get Vy
	srl     t1, a0, 4
	andi    t1, t1, $f
	addu    t1, t1, v
	lb      t1, 0(t1)

	beql    t0, t1, opcode_5xy0_end
	addiu	pc, pc, 2
opcode_5xy0_end:
	jr      ra
	andi	pc, pc, $fff

// LD Vx, byte -- Set Vx = nn
opcode_6xnn:  // void(hword opcode)
	srl     t0, a0, 8
	andi    t0, t0, $f
	addu    t0, t0, v
	jr      ra
	sb      a0, 0(t0)

// ADD Vx, byte -- Set Vx = Vx + nn
opcode_7xnn:  // void(hword opcode)
	srl     t0, a0, 8
	andi    t0, t0, $f
	addu    t0, t0, v
	lb      t1, 0(t0)
	addu    t1, t1, a0
	jr      ra
	sb      t1, 0(t0)

opcode_8xyn:  // void(hword opcode)
	move    t0, a0
	// Get &Vx
	srl     a0, a0, 8
	andi    a0, a0, $f
	addu    a0, a0, v

	// Get &Vy
	srl     a1, t0, 4
	andi    a1, a1, $f
	addu    a1, a1, v

	la      t1, instr_jump_table_8000
	andi    t2, t0, $f
	sll     t2, t2, 2
	addu    t1, t1, t2
	lw      t1, 0(t1)
	jr      t1
	nop

// LD Vx, Vy -- Set Vx = Vy
opcode_8xy0:  // void(word &Vx, word &Vy)
	lb      t0, 0(a1)
	jr      ra
	sb      t0, 0(a0)

// OR Vx, Vy -- Set Vx = Vx OR Vy
opcode_8xy1:  // void(word &Vx, word &Vy)
	lb      t0, 0(a0)
	lb      t1, 0(a1)
	or      t0, t0, t1
	jr      ra
	sb      t0, 0(a0)

// AND Vx, Vy -- Set Vx = Vx AND Vy
opcode_8xy2:  // void(word &Vx, word &Vy)
	lb      t0, 0(a0)
	lb      t1, 0(a1)
	and     t0, t0, t1
	jr      ra
	sb      t0, 0(a0)

// XOR Vx, Vy -- Set Vx = Vx XOR Vy
opcode_8xy3:  // void(word &Vx, word &Vy)
	lb      t0, 0(a0)
	lb      t1, 0(a1)
	xor     t0, t0, t1
	jr      ra
	sb      t0, 0(a0)

// ADD Vx, Vy -- Set Vx = Vx + Vy, and set VF = carry
opcode_8xy4:  // void(word &Vx, word &Vy)
	lbu     t0, 0(a0)
	lbu     t1, 0(a1)
	addu    t0, t0, t1
	sb      t0, 0(a0)
	srl     t0, t0, 8
	jr      ra
	sb      t0, $f(v)

// SUB Vx, Vy -- Set Vx = Vx - Vy, and set VF = NOT borrow
opcode_8xy5:  // void(word &Vx, word &Vy)
	lbu     t0, 0(a0)
	lbu     t1, 0(a1)
	subu    t0, t0, t1
	sb      t0, 0(a0)
	addiu   t1, zero, -1
	slt     t1, t1, t0
	jr      ra
	sb      t1, $f(v)

// SHR Vx {, Vy} -- Set VF to the LSB of Vy, and set Vx = Vy SHR 1
opcode_8xy6:  // void(word &Vx, word &Vy)
	lbu     t0, 0(a1)
	andi    t1, t0, 1
	sb      t1, $f(v)
	srl     t0, t0, 1
	jr      ra
	sb      t0, 0(a0)

// SUBN Vx, Vy -- Set Vx = Vy - Vx, and set VF = NOT borrow
opcode_8xy7:  // void(word &Vx, word &Vy)
	lbu     t0, 0(a0)
	lbu     t1, 0(a1)
	subu    t0, t1, t0
	sb      t0, 0(a0)
	addiu   t1, zero, -1
	slt     t1, t1, t0
	jr      ra
	sb      t1, $f(v)

// SHL Vx {, Vy} -- Set VF to the MSB of Vy, and set Vx = Vy SHL 1. 
opcode_8xyE:  // void(word &Vx, word &Vy)
	lbu     t0, 0(a1)
	srl     t1, t0, 7
	sb      t1, $f(v)
	sll     t0, t0, 1
	jr      ra
	sb      t0, 0(a0)

// Skip the next instruction if Vx != Vy
opcode_9xy0:  // void(hword opcode)
	srl     t0, a0, 8
	andi    t0, t0, $f
	addu    t0, t0, v
	lb      t0, 0(t0)
	srl     t1, a0, 4
	andi    t1, t1, $f
	addu    t1, t1, v
	lb      t1, 0(t1)
	bnel    t0, t1, opcode_9xy0_end
	addiu	pc, pc, 2
opcode_9xy0_end:
	jr      ra
	andi	pc, pc, $fff

// Set I = nnn
opcode_Annn:  // void(hword opcode)
	jr      ra
	andi    index, a0, $fff

// Jump to nnn + V0
opcode_Bnnn:  // void(hword opcode)
	lbu     t0, 0(v)
	addu    pc, a0, t0
	jr      ra
	andi    pc, pc, $fff

// RND Vx, byte -- Set Vx = random byte AND nn
opcode_Cxnn:  // void(hword opcode)
	mfc0    t0, CP0_RANDOM
	sll     t0, t0, 3
	mfc0    t1, CP0_COUNT
	andi    t1, t1, 7
	or      t0, t0, t1
	and     t0, t0, a0
	srl     t1, a0, 8
	andi    t1, t1, $f
	addu    t1, t1, v
	jr      ra
	sb      t0, 0(t1)

// DRW Vx, Vy, n -- Draw sprite of height n (n bytes) and width 8
// starting at memory location I at coordinates (Vx, Vy), and set VF = collision
// I is not changed.
opcode_Dxyn:  // void(hword opcode)
	andi    t0, a0, $f             // height
	beq     t0, zero, draw_end_no_render
	move    a3, zero               // collision
	srl     t1, a0, 8
	andi    t1, t1, $f
	addu    t1, t1, v
	lb      t1, 0(t1)			   // Vx
	andi    t1, t1, CH8_WIDTH-1    // x
	srl     t2, a0, 4
	andi    t2, t2, $f
	addu    t2, t2, v
	lb      t2, 0(t2)              // Vy
	andi    t2, t2, CH8_HEIGHT-1   // y
	move	t3, zero               // yline (0..n)
	la      a0, ch8_framebuffer
	ori     a1, zero, $80
	ori		a2, zero, 8
draw_loop_begin:
	addu	t4, index, t3          // index + yline
	andi	t4, t4, $fff
	addu    t4, t4, ch8_mem
	lb      t4, 0(t4)              // x-strip = memory[I + yline]
	sll     t5, t2, 6              // y * 64
	move	t6, t1                 // x
	move    t7, zero               // xline (0..8)
draw_strip_begin:
	srlv    t8, a1, t7
	and     t8, t8, t4             // x-strip & (0x80 >> xline)
	beq     t8, zero, draw_pixel_end
	addiu   t7, t7, 1
	addu    t8, a0, t5             // gfx + y * 64
	addu	t8, t8, t6             // gfx + y * 64 + x
	lb      t9, 0(t8)              // gfx[y * 64 + x]
	bnel    t9, zero, draw_pixel
	ori     a3, a3, 1              // set collision
draw_pixel:
	xori    t9, t9, $ff
	sb      t9, 0(t8)
draw_pixel_end:
	addiu   t6, t6, 1
	bnel    t7, a2, draw_strip_begin
	andi	t6, t6, CH8_WIDTH-1
draw_strip_end:
	addiu   t2, t2, 1
	addiu	t3, t3, 1
	bnel    t3, t0, draw_loop_begin
	andi    t2, t2, CH8_HEIGHT-1
draw_end:
	la      t0, needs_render
	ori     t1, zero, 1
	sb      t1, 0(t0)
draw_end_no_render:
	jr      ra
	sb      a3, $f(v)

opcode_Exnn:  // void(hword opcode)
	andi    t0, a0, $ff
	srl     a0, a0, 8
	andi    a0, a0, $f
	addu    a0, a0, v
	lb      a0, 0(a0)
	andi    a0, a0, $f
	la      t1, key
	addu    a0, a0, t1
	lbu     a0, 0(a0)

	ori     t1, zero, $9e
	beq     t0, t1, opcode_Ex9E
	ori     t1, zero, $a1
	beql    t0, t1, opcode_ExA1
	nop
	j       panic
	nop

// Skip the next instruction if key[Vx] != 0
opcode_Ex9E:  // void(byte key[Vx])
	slt     t0, zero, a0
	sll     t0, t0, 1
	addu    pc, pc, t0
	jr      ra
	andi    pc, pc, $fff

// Skip the next instruction if key[Vx] == 0
opcode_ExA1:  // void(byte key[Vx])
	slti    t0, a0, 1
	sll     t0, t0, 1
	addu    pc, pc, t0
	jr      ra
	andi    pc, pc, $fff

opcode_Fxnn:  // void(hword opcode)
	andi    t0, a0, $ff
	srl     a0, a0, 8
	andi    a0, a0, $f
	ori     t1, zero, 7
	beq     t0, t1, opcode_Fx07
	ori     t1, zero, $a
	beq     t0, t1, opcode_Fx0A
	ori     t1, zero, $15
	beq     t0, t1, opcode_Fx15
	ori     t1, zero, $18
	beq     t0, t1, opcode_Fx18
	ori     t1, zero, $1e
	beq     t0, t1, opcode_Fx1E
	ori     t1, zero, $29
	beq     t0, t1, opcode_Fx29
	ori     t1, zero, $33
	beq     t0, t1, opcode_Fx33
	ori     t1, zero, $55
	beq     t0, t1, opcode_Fx55
	ori     t1, zero, $65
	beql    t0, t1, opcode_Fx65
	nop
	j       panic
	nop

// LD Vx, DT -- Set Vx = delay timer.
opcode_Fx07:  // void(byte x)
	addu    a0, a0, v
	la      t0, delay_timer
	lb      t0, 0(t0)
	jr      ra
	sb      t0, 0(a0)

// LD Vx, K --  Wait for a key press, store the value of the key in Vx
opcode_Fx0A:  // void(byte x)
	addiu   sp, sp, -16
	sd      ra, 0(sp)
	sd      s0, 8(sp)
	jal     await_input
	move    s0, a0
	addu    s0, s0, v
	sb      v0, 0(s0)
	ld      ra, 0(sp)
	ld      s0, 8(sp)
	jr      ra
	addiu   sp, sp, 16

// LD DT, Vx -- Set delay timer = Vx
opcode_Fx15:  // void(byte x)
	addu    a0, a0, v
	lb      a0, 0(a0)
	la      t0, delay_timer
	jr      ra
	sb      a0, 0(t0)

// LD ST, Vx -- Set sound timer = Vx
opcode_Fx18:  // void(byte x)
	addu    a0, a0, v
	lb      a0, 0(a0)
	la      t0, sound_timer
	jr      ra
	sb      a0, 0(t0)

// ADD I, Vx -- Set I = I + Vx
opcode_Fx1E:  // void(byte x)
	addu    a0, a0, v
	lbu     a0, 0(a0)
	addu    index, index, a0
	jr      ra
	andi    index, index, $fff

// LD F, Vx -- Set I = location of sprite for digit Vx, i.e., set I = Vx * 5
opcode_Fx29:  // void(byte x)
	addu    a0, a0, v
	lbu     a0, 0(a0)
	sll     index, a0, 2
	jr      ra
	addu    index, index, a0

// LD B, Vx --  Store BCD representation of Vx in memory locations I, I+1, and I+2
opcode_Fx33:  // void(byte x)
	addu    a0, a0, v
	lbu     a0, 0(a0)
	ori     t0, zero, 10
	div     a0, t0
	mflo    t1                    // Vx / 10
	mfhi    t2                    // Vx % 10
	div     t1, t0
	mflo    t0                    // Vx / 100
	addu    t1, ch8_mem, index
	addiu   t3, index, -$ffe
	bgez    t3, index_wrap
	sb      t0, 0(t1)
	mfhi    t0                    // (Vx / 10) % 10
	sb      t0, 1(t1)
	sb      t2, 2(t1)
	addiu   index, index, 3
	jr      ra
	andi    index, index, $fff
index_wrap:
	addiu   index, index, 1
	andi    index, index, $fff
	mfhi    t0                    // (Vx / 10) % 10
	addu    t1, ch8_mem, index
	sb      t0, 0(t1)
	addiu   index, index, 1
	andi    index, index, $fff
	addu    t1, ch8_mem, index
	sb      t2, 0(t1)
	addiu   index, index, 1
	jr      ra
	andi    index, index, $fff

// LD [I], Vx -- Store registers V0 through Vx in memory starting at location I
opcode_Fx55:  // void(byte x)
	move    t0, zero
opcode_Fx55_loop_start:
	addu    t1, v, t0
	lb      t1, 0(t1)
	addu    t2, ch8_mem, index
	sb      t1, 0(t2)
	addiu   index, index, 1
	andi    index, index, $fff
	bnel    t0, a0, opcode_Fx55_loop_start
	addiu   t0, t0, 1
	jr      ra
	nop

// LD Vx, [I] -- Read registers V0 through Vx from memory starting at location I
opcode_Fx65:  // void(byte x)
	move    t0, zero
opcode_Fx65_loop_start:
	addu    t1, ch8_mem, index
	lb      t1, 0(t1)
	addu    t2, v, t0
	sb      t1, 0(t2)
	addiu   index, index, 1
	andi    index, index, $fff
	bnel    t0, a0, opcode_Fx65_loop_start
	addiu   t0, t0, 1
	jr      ra
	nop

panic:  // void()
	break
	jr      ra
	nop

play_audio:  // TODO
	jr      ra
	nop

do_run:
	db 1

got_v_sync:
	db 0

align(8)
ch8_memory:
	data_array(CH8_MEM_SIZE)

align(64)
ch8_framebuffer:
	data_array(CH8_FRAMEBUFFER_SIZE)

align(8)
stack:
	dd 0, 0, 0, 0

align(8)
v_data:
	dd 0, 0

align(8)
key:
	dd 0, 0

delay_timer:
	db 60

sound_timer:
	db 60

needs_render:
	db 0

align(8)
fontset:
	dd $f0909090f0206020
	dd $2070f010f080f0f0
	dd $10f010f09090f010
	dd $10f080f010f0f080
	dd $f090f0f010204040
	dd $f090f090f0f090f0
	dd $10f0f090f09090e0
	dd $90e090e0f0808080
	dd $f0e0909090e0f080
	dd $f080f0f080f08080

align(4)
instr_jump_table:
	dw opcode_0nnn
	dw opcode_1nnn
	dw opcode_2nnn
	dw opcode_3xnn
	dw opcode_4xnn
	dw opcode_5xy0
	dw opcode_6xnn
	dw opcode_7xnn
	dw opcode_8xyn
	dw opcode_9xy0
	dw opcode_Annn
	dw opcode_Bnnn
	dw opcode_Cxnn
	dw opcode_Dxyn
	dw opcode_Exnn
	dw opcode_Fxnn

align(4)
instr_jump_table_8000:
	dw opcode_8xy0
	dw opcode_8xy1
	dw opcode_8xy2
	dw opcode_8xy3
	dw opcode_8xy4
	dw opcode_8xy5
	dw opcode_8xy6
	dw opcode_8xy7
	dw panic
	dw panic
	dw panic
	dw panic
	dw panic
	dw panic
	dw opcode_8xyE
	dw panic

define ch8_rom_file = "game.ch8"
assert(file.exists({ch8_rom_file}))
constant CH8_ROM_SIZE = file.size({ch8_rom_file})
assert(CH8_ROM_SIZE > 0 && CH8_ROM_SIZE <= MAX_CH8_ROM_SIZE)
align(8)
ch8_rom:
	insert {ch8_rom_file}
