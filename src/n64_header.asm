// N64 rom header (64 bytes); info taken from https://github.com/PeterLemon/N64/blob/master/LIB/N64_HEADER.ASM

// PI_BSB_DOM1
db $80 // Initial PI_BSB_DOM1_LAT_REG Value
db $37 // Initial PI_BSB_DOM1_PGS_REG Value
db $12 // Initial PI_BSB_DOM1_PWD_REG Value
db $40 // Initial PI_BSB_DOM1_PGS_REG Value

// CLOCK RATE
dw $000F // Initial Clock Rate

// VECTOR
dw start // Boot Address Offset
dw $1444 // Release Offset

// COMPLEMENT CHECK & CHECKSUM
dw $DC56E449 // CRC1: COMPLEMENT CHECK
dw $7C5A11F8 // CRC2: CHECKSUM

dd 0 // UNUSED

// PROGRAM TITLE (27 Byte ASCII String, Use Spaces For Unused Bytes)
db "CHIP-64                    "
// "123456789012345678901234567"

// DEVELOPER ID CODE 
db $00 // "N" = Nintendo

// CARTRIDGE ID CODE
db $00

db 0 // UNUSED

// COUNTRY CODE 
db $00 // "D" = Germany, "E" = USA, "J" = Japan, "P" = Europe, "U" = Australia

db 0 // UNUSED