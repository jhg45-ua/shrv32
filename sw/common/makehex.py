#!/usr/bin/env python3
"""Convierte un binario RISC-V raw (.bin) en formato .hex de palabras de 32 bits para $readmemh."""

from sys import argv

binfile = argv[1]
nwords = int(argv[2])
coefile = argv[3] if len(argv) > 3 else None

with open(binfile, "rb") as f:
    bindata = f.read()

while len(bindata) % 4 != 0:
    bindata += b"\x00"

assert len(bindata) <= 4 * nwords, (
    f"Firmware ({len(bindata)} B) excede la capacidad de memoria ({4 * nwords} B)"
)

words = []
for i in range(nwords):
    if i < len(bindata) // 4:
        w = bindata[4 * i : 4 * i + 4]
        words.append("%02x%02x%02x%02x" % (w[3], w[2], w[1], w[0]))
    else:
        words.append("00000000")

for w in words:
    print(w)

if coefile:
    with open(coefile, "w") as f:
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        f.write(",\n".join(words))
        f.write(";\n")
