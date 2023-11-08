arch n64.cpu
endian msb
output "chip8.z64", create
fill 1052672 // Set ROM Size

constant zero = 0
constant at = 1
constant v0 = 2
constant v1 = 3
constant a0 = 4
constant a1 = 5
constant a2 = 6
constant a3 = 7
constant t0 = 8
constant t1 = 9
constant t2 = 10
constant t3 = 11
constant t4 = 12
constant t5 = 13
constant t6 = 14
constant t7 = 15
constant s0 = 16
constant s1 = 17
constant s2 = 18
constant s3 = 19
constant s4 = 20
constant s5 = 21
constant s6 = 22
constant s7 = 23
constant t8 = 24
constant t9 = 25
constant k0 = 26
constant k1 = 27
constant gp = 28
constant sp = 29
constant fp = 30
constant ra = 31

constant pc = fp
constant ch8_sp = t9
constant index = k0
constant v = k1
constant ch8_mem = gp

constant CP0_RANDOM = 1
constant CP0_COUNT = 9
constant CP0_STATUS = 12

constant MI_MASK = $a430000c
constant VI_BASE = $a4400000
constant VI_CTRL_OFFSET = 0
constant VI_ORIGIN_OFFSET = 4
constant VI_WIDTH_OFFSET  = 8
constant VI_ORIGIN = VI_BASE + VI_ORIGIN_OFFSET

constant CH8_FRAMEBUFFER_SIZE = 32*64
constant N64_FRAMEBUFFER_START = 0
constant ROM_START_INDEX = $200
constant FONTSET_SIZE = $50
constant CYCLES_PER_UPDATE = 100

main:
	jal init_host
	nop
	jal init_guest
	nop
	jal run
	nop
main_end:
	j main_end
	nop

init_host:  // void()
	la t0, VI_BASE
	ori t1, zero, $3303                // 8/8/8/8 colour mode; disable AA and resampling; set PIXEL_ADVANCE %0011
	sw t1, VI_CTRL_OFFSET(t0)
	la t1, N64_FRAMEBUFFER_START
	sw t1, VI_ORIGIN_OFFSET(t0)
	ori t1, zero, 320
	sw t1, VI_WIDTH_OFFSET(t0)

	la t0, MI_MASK
	ori t1, zero, $388                 // Enable PI, SI, VI interrupts
	sw t1, 0(t0)

	jr ra
	nop

init_guest:  // void()
	move	t0, ch8_mem

	// load fontset
	la t1, fontset
	addiu t2, t1, FONTSET_SIZE
fontset_loop_begin:
	ld t3, 0(t1)
	addiu t1, t1, 8
	sd t3, 0(t0)
	bne t1, t2, fontset_loop_begin
	addiu t0, t0, 8

	// load rom
	addiu t0, t0, ROM_START_INDEX
	ori t1, zero, $1000

	ori pc, zero, $200
	move index, zero
	move ch8_sp, zero
	
	ori t0, zero, 60
	la t1, delay_timer
	sb t0, 0(t1)
	la t1, sound_timer
	sb t0, 0(t1)

	// clear stack
	la t0, stack
	sd zero, 0(t0)
	sd zero, 8(t0)

	// clear key
	la t0, key
	sd zero, 0(t0)
	sd zero, 8(t0)

	// clear v
	sd zero, 0(v)
	sd zero, 8(v)

	j clear_display
	nop

clear_display:  // void()
	la t0, VI_ORIGIN
	addiu t1, t0, CH8_FRAMEBUFFER_SIZE
	move t2, zero
clear_display_loop:
	sd t2, 0(t0)
	addiu t0, t0, 8
	bnel t0, t1, clear_display_loop
	nop
	jr ra
	nop

inc_pc:  // void()
	addiu    pc, pc, 2
	jr       ra
	andi     pc, pc, $fff

run:  // void()
	addiu    sp, sp, -16
	sd       ra, 0(sp)
	sd       s0, 8(sp)
run_loop:
	li       s0, CYCLES_PER_UPDATE
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
	beq      t1, zero, render_and_poll_input
	addiu    t1, t1, -1
	beq      t1, zero, play_audio
	sb       t1, 0(t0)
render_and_poll_input:
	jal      render
	nop
	jal      poll_input
	nop

	la       t0, do_run
	lb       t0, 0(t0)
	bnel     t0, zero, run_loop
	nop
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
	jr      t1
	andi    pc, pc, $fff

opcode_0nnn:  // void(hword opcode)
	// 00E0; CLS -- Clear the display
	ori     t0, zero, $e0
	beq     t0, a0, clear_display
	
	// opcode != $00EE => panic
	ori     t0, zero, $ee
	bne     t0, a0, panic

	// 00EE; RET -- Return from subroutine
	la      t0, stack
	addu    t0, t0, ch8_sp
	lbu     pc, 0(t0)
	addiu   ch8_sp, ch8_sp, -1
	jr      ra
	andi    ch8_sp, ch8_sp, $f

// JP addr -- Jump to location nnn
opcode_1nnn:  // void(hword opcode)
	jr      ra
	andi    pc, a0, $fff

// CALL addr -- Call subroutine at nnn
opcode_2nnn:  // void(hword opcode)
	addiu   ch8_sp, ch8_sp, 1
	andi    ch8_sp, ch8_sp, $f
	sb      pc, 0(ch8_sp)
	jr      ra
	andi    pc, a0, $fff

// SE Vx, byte -- Skip next instruction if Vx == nn
opcode_3xnn:  // void(hword opcode)
	srl    t0, a0, 8
	andi   t0, t0, $f
	addu   t0, t0, v
	lbu    t0, 0(t0)
	andi   t1, a0, $ff
	beql   t0, t1, inc_pc
	nop
	jr     ra
	nop

// SNE Vx, byte -- Skip next instruction if Vx != nn
opcode_4xnn:  // void(hword opcode)
	srl    t0, a0, 8
	andi   t0, t0, $f
	addu   t0, t0, v
	lbu    t0, 0(t0)
	andi   t1, a0, $ff
	bnel   t0, t1, inc_pc
	nop
	jr     ra
	nop

// SE Vx, Vy -- Skip next instruction if Vx == Vy.
opcode_5xy0:  // void(hword opcode)
	// Get Vx
	srl    t0, a0, 8
	andi   t0, t0, $f
	addu   t0, t0, v
	lbu    t0, 0(t0)

	// Get Vy
	srl    t1, a0, 4
	andi   t1, t1, $f
	addu   t1, t1, v
	lbu    t1, 0(t1)

	beql   t0, t1, inc_pc
	nop
	jr     ra
	nop

// LD Vx, byte -- Set Vx = nn
opcode_6xnn:  // void(hword opcode)
	srl    t0, a0, 8
	andi   t0, t0, $f
	addu   t0, t0, v
	jr     ra
	sb     a0, 0(t0)

// ADD Vx, byte -- Set Vx = Vx + nn
opcode_7xnn:  // void(hword opcode)
	srl    t0, a0, 8
	andi   t0, t0, $f
	addu   t0, t0, v
	lb     t1, 0(t0)
	addu   t1, t1, a0
	jr     ra
	sb     t1, 0(t0)

opcode_8xyn:  // void(hword opcode)
	move    t0, a0
	// Get Vx
	srl     a0, t0, 8
	andi    a0, a0, $f
	addu    a0, a0, v

	// Get Vy
	srl     a1, t0, 4
	andi    a1, a1, $f

	la      t1, instr_jump_table_8000
	andi    t2, t0, $f
	sll     t2, t2, 2
	addu    t1, t1, t2
	jr      t1
	addu    a1, a1, v

// LD Vx, Vy -- Set Vx = Vy
opcode_8xy0:  // void(word &Vx, word &Vy)
	lb     t0, 0(a1)
	jr     ra
	sb     t0, 0(a0)

// OR Vx, Vy -- Set Vx = Vx OR Vy
opcode_8xy1:  // void(word &Vx, word &Vy)
	lb     t0, 0(a0)
	lb     t1, 0(a1)
	or     t0, t0, t1
	jr     ra
	sb     t0, 0(a0)

// AND Vx, Vy -- Set Vx = Vx AND Vy
opcode_8xy2:  // void(word &Vx, word &Vy)
	lb     t0, 0(a0)
	lb     t1, 0(a1)
	and    t0, t0, t1
	jr     ra
	sb     t0, 0(a0)

// XOR Vx, Vy -- Set Vx = Vx XOR Vy
opcode_8xy3:  // void(word &Vx, word &Vy)
	lb     t0, 0(a0)
	lb     t1, 0(a1)
	xor    t0, t0, t1
	jr     ra
	sb     t0, 0(a0)

// ADD Vx, Vy -- Set Vx = Vx + Vy, and set VF = carry
opcode_8xy4:  // void(word &Vx, word &Vy)
	lbu    t0, 0(a0)
	lbu    t1, 0(a1)
	addu   t0, t0, t1
	sb     t0, 0(a0)
	srl    t0, t0, 8
	jr     ra
	sb     t0, $f(v)

// SUB Vx, Vy -- Set Vx = Vx - Vy, and set VF = NOT borrow
opcode_8xy5:  // void(word &Vx, word &Vy)
	lbu    t0, 0(a0)
	lbu    t1, 0(a1)
	subu   t0, t0, t1
	sb     t0, 0(a0)
	addiu  t1, zero, -1
	slt    t1, t1, t0
	jr     ra
	sb     t1, $f(v)

// SHR Vx {, Vy} -- Set VF to the LSB of Vy, and set Vx = Vy SHR 1
opcode_8xy6:  // void(word &Vx, word &Vy)
	lbu    t0, 0(a1)
	andi   t1, t0, 1
	sb     t1, $f(v)
	srl    t0, t0, 1
	jr     ra
	sb     t0, 0(a0)

// SUBN Vx, Vy -- Set Vx = Vy - Vx, and set VF = NOT borrow
opcode_8xy7:  // void(word &Vx, word &Vy)
	lbu    t0, 0(a0)
	lbu    t1, 0(a1)
	subu   t0, t1, t0
	sb     t0, 0(a0)
	addiu  t1, zero, -1
	slt    t1, t1, t0
	jr     ra
	sb     t1, $f(v)

// SHL Vx {, Vy} -- Set VF to the MSB of Vy, and set Vx = Vy SHL 1. 
opcode_8xyE:  // void(word &Vx, word &Vy)
	lbu    t0, 0(a1)
	srl    t1, t0, 7
	sb     t1, $f(v)
	sll    t0, t0, 1
	jr     ra
	sb     t0, 0(a0)

// Skip the next instruction if Vx != Vy
opcode_9xy0:  // void(hword opcode)
	// Get Vx, Vy
	srl t0, a0, 8
	andi t0, t0, $f
	addu t0, t0, v
	lbu t0, 0(t0)
	srl t1, a0, 4
	andi t1, t1, $f
	addu t1, t1, v
	lbu t1, 0(t1)

	bnel t0, t1, inc_pc
	nop
	jr ra
	nop

// Set I = nnn
opcode_Annn:  // void(hword opcode)
	jr ra
	andi index, a0, $fff

// Jump to nnn + V0
opcode_Bnnn:  // void(hword opcode)
	lbu     t0, 0(v)
	addu    pc, a0, t0
	jr      ra
	andi    pc, pc, $fff

// RND Vx, byte -- Set Vx = random byte AND nn
opcode_Cxnn:  // void(hword opcode)
	mfc0    t0, CP0_RANDOM
	nop
	sll     t0, t0, 3
	mfc0    t1, CP0_COUNT
	nop
	andi    t1, t1, 7
	or      t0, t0, t1
	and     t0, t0, a0
	srl     t1, a0, 8
	andi    t1, t1, $f
	addu    t1, t1, v
	jr      ra
	sb      t0, 0(t1)

opcode_Dxyn:  // void(hword opcode)
	srl    t0, a0, 8
	andi   t0, t0, $f
	addu   t0, t0, v
	lbu    t0, 0(t0)
	andi   t0, t0, 63 // vx
	srl    t1, a0, 4
	andi   t1, t1, $f
	addu   t1, t1, v
	lbu    t1, 0(t1)
	andi   t1, t1, 31  // y
	la     a0, ch8_framebuffer
	ori    a1, zero, $80
	sb     zero, $f(v)
	andi   t2, a0, $f // height
	addu   t2, t2, t1 // ymax
	slti   t3, t2, 33
	bnel   t3, zero, calc_width
	ori    t2, zero, 32
calc_width:
	ori    t3, zero, 64
	subu   t3, t3, t0
	slti   t4, t3, 8
	bnel   t4, zero, draw_loop_begin
	ori    t3, zero, 8 // sprite width
draw_loop_begin:
	addiu  t4, ch8_mem, index
	addiu  index, index, 1
	lbu    t4, 0(t4)  // x-strip
	sll    t5, t1, 6
	addu   t5, t5, t0 // framebuffer pos
	move   t6, zero   // xline
draw_strip_begin:
	srlv   t7, a1, t6
	and    t7, t7, t4
	beq    t7, zero, draw_pixel_end
	addu   t7, a0, t5
	lbu    t8, 0(t7)
	beq    t8, zero, draw_pixel
	ori    t9, zero, 1
	sb     t9, $f(v)
draw_pixel:
	xori   t8, t8, $ff
	sb     t8, 0(t7)
draw_pixel_end:
	addiu  t6, t6, 1
	bnel   t6, t3, draw_strip_begin
	addiu  t5, t5, 1
draw_strip_end:
	addiu  t1, t1, 1
	bne    t1, t2, draw_loop_begin
	andi   index, index, $fff
	jr     ra
	nop

opcode_Exnn:  // void(hword opcode)
	andi    t0, a0, $ff
	srl     a0, a0, 8
	andi    a0, a0, $f
	addu    a0, a0, v
	lbu     a0, 0(a0)
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
	lbu     a0, 0(a0)
	la      t0, delay_timer
	jr      ra
	sb      a0, 0(t0)

// LD ST, Vx -- Set sound timer = Vx
opcode_Fx18:  // void(byte x)
	addu    a0, a0, v
	lbu     a0, 0(a0)
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
	addu    index, index, a0
	jr      ra
	andi    index, index, $fff

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
	bne     t0, a0, opcode_Fx55_loop_start
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
	bne     t0, a0, opcode_Fx65_loop_start
	addiu   t0, t0, 1
	jr      ra
	nop

play_audio:  // TODO
	jr ra
	nop

// byte 0: command length (1)
// byte 1: result length (4)
// byte 2: command (1)
// bytes 3-6: result (joypad status)
poll_input:  // void()
	// write to start of PIF RAM bytes 0-2
	lui t0, $bfc0
	lui t1, $0104
	ori t1, zero, $0100
	sw t1, $7c0(t0)

	// write 1 to the PIF RAM control byte, triggering the joybus protocol
	ori t1, zero, 1
	sw t1, $7fc(t0)

	// read the result (bytes 3-6). best to stick to aligned word reads here
	lw t1, $7c0(t0)
	lw t2, $7c4(t0)

	// TODO: use the input
	jr ra
	nop

await_input:  byte() -- returns the index of the next key pressed
	jr ra
	nop

render:  // void()
	la     t0, ch8_framebuffer
	addiu  t1, t0, CH8_FRAMEBUFFER_SIZE
	li     t2, N64_FRAMEBUFFER_START
render_loop:
	lb     t3, 0(t0)  // src either 0 or $ff; sign-extend to 0 or $ffff'ffff for 8/8/8/8
	sw     t3, 0(t2)
	addiu  t0, t0, 1
	bne    t0, t1, render_loop
	addiu  t2, t2, 4
	jr     ra
	nop

panic: // TODO
	jr ra
	nop

do_run:
	db 1

addr_memory:
	dw $80000000

stack:
	dd 0, 0

v_data:
	dd 0, 0

key:
	dd 0, 0

delay_timer:
	db 60

sound_timer:
	db 60

ch8_framebuffer:
	db 0

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