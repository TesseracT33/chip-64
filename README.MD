## Building
	1) git clone https://github.com/TesseracT33/chip-64
	2) Download/build `bass` from https://github.com/ARM9/bass
	3) Overwrite the contents of `game.ch8` with the chip-8 game that should be included with the emulator. The sample included is `Pong (1 player).ch8`
	4) Run `bass chip-64/chip8.asm` or `bass.exe chip-64\chip8.asm`, or put bass in `chip-64/` and run `make`