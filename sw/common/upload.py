#!/usr/bin/env python3
"""Envía una aplicación compilada (.bin) al bootloader de SHRV32 mediante UART."""

import serial
import struct
import sys
import time

port = sys.argv[2] if len(sys.argv) > 2 else "/dev/ttyUSB1"
with open(sys.argv[1], "rb") as f:
    data = f.read()

ser = serial.Serial(port, 115200, timeout=0.5)
ser.reset_input_buffer()
print(f"Esperando READY del bootloader ({len(data)} bytes). Pulsa CPU_RESETN...")

while True:
    line = ser.readline()
    if line:
        print("RX:", line)
    if b"READY" in line:
        break

print("READY detectado, enviando aplicación...")
for b in struct.pack("<I", len(data)) + data:
    ser.write(bytes([b]))
    ser.flush()
    time.sleep(0.002)  # 2 ms/byte para evitar overrun sin FIFO hardware

print("Aplicación enviada. Salida UART (Ctrl+C para salir):")
try:
    while True:
        c = ser.read(1)
        if c:
            sys.stdout.write(c.decode("ascii", "ignore"))
            sys.stdout.flush()
except KeyboardInterrupt:
    pass
