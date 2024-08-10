## Bootcode
This project uses libdragon's IPL3, specifically, "ipl3_compat.z64" from here: https://github.com/DragonMinded/libdragon/tree/preview/boot/bin. Its header has been stripped and in its place is src/n64_header.asm (for specifying the entrypoint). The header checksums are unused.

## Building
	1) git clone https://github.com/TesseracT33/chip-64
	2) Download/build `bass` from https://github.com/ARM9/bass
	3) Overwrite the contents of `game.ch8` with the chip-8 game that should be included with the emulator. The sample included is `Pong (1 player).ch8`
	4) Run `./bass src/chip8.asm` or `.\bass.exe src\chip8.asm`, or run `make` if bass is in the PATH

## Useful test roms
	* https://github.com/Timendus/chip8-test-suite/