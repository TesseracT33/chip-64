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

constant CP0_RANDOM = 1
constant CP0_COUNT = 9
constant CP0_STATUS = 12
constant CP0_CAUSE = 13

constant MI_BASE = $a430
constant MI_INTERRUPT = $8
constant MI_MASK = $c

constant PI_BASE = $a460
constant PI_DRAM_ADDR = $0
constant PI_CART_ADDR = $4
constant PI_RD_LEN = $8
constant PI_WR_LEN = $c
constant PI_STATUS = $10

constant PIF_BASE = $bfc0
constant PIF_RAM = $7c0

constant SI_BASE = $a480
constant SI_DRAM_ADDR = $0
constant SI_PIF_AD_RD64B = $4
constant SI_PIF_AD_WR64B = $10
constant SI_STATUS = $18

constant VI_BASE = $a440
constant VI_CTRL = $0
constant VI_ORIGIN = $4
constant VI_WIDTH = $8
constant VI_V_INTR = $c
constant VI_V_CURRENT = $10
constant VI_BURST = $14
constant VI_V_SYNC = $18
constant VI_H_SYNC = $1c
constant VI_H_SYNC_LEAP = $20
constant VI_H_VIDEO = $24
constant VI_V_VIDEO = $28
constant VI_V_BURST = $2c
constant VI_X_SCALE = $30
constant VI_Y_SCALE = $34

constant N64_DCACHE_SIZE = 8 * 1024
constant N64_ICACHE_SIZE = 16 * 1024
constant N64_DCACHE_LINE_SIZE = 16
constant N64_ICACHE_LINE_SIZE = 32