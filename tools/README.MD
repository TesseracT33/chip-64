When using the NUS-CIC-6102 IPL3, the `CRC1` and `CRC2` fields in the rom header must be particular values, depending on the first MiB of contents of the rom. We can compute these using `n64crc.c` (supply the .z64 file as the first argument). If the header is correct, the output should read something like (depending on the rom contents):

```
BootChip: CIC-NUS-6102
CRC 1: 0x18CAF15E  Calculated: 0x18CAF15E (Good)
CRC 2: 0x0FA65501  Calculated: 0x0FA65501 (Good)
```

https://n64brew.dev/wiki/PIF-NUS#IPL3_checksum_algorithm
