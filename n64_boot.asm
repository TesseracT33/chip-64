arch n64.cpu
endian msb

boot:
	// load the entrypoint from the header
	lui     s0, $A400
	lw      s0, 8(s0)

	// copy N64 ROM from offset $1000 to RDRAM at offset entrypoint
	lui     t0, PI_BASE
	ori     t1, zero, 3
	sw      t1, PI_STATUS(t0)       // reset DMA controller and clear previous interrupt, if any
	li      t2, $ffffff
	and     t2, t2, s0
	sw      t2, PI_DRAM_ADDR(t0)
	ori     t2, zero, $1000         // offset rom header + boot code
	sw      t2, PI_CART_ADDR(t0)
	li      t2, N64_ROM_SIZE - 1
	sw      t2, PI_WR_LEN(t0)
await_pi_dma:
	lw      t2, PI_STATUS(t0)
	andi    t2, t2, 8
	beql    t2, zero, await_pi_dma
	nop
	sw      t1, PI_STATUS(t0)

	// jump to entrypoint
	jr      s0
	nop

align($1000)