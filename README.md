# SHRV32 — Space-Hardened RISC-V 32 SoC

**SHRV32** is a fault-tolerant System-on-Chip (SoC) built around the **PicoRV32** core (RV32I, native memory interface), designed to mitigate radiation-induced bit-flips (*Single Event Upsets* / SEUs) in space environments.

The processor is intended to serve as the control core inside a neural network hardware accelerator IP for aerospace applications.

---

## Architecture & Hardening Techniques

* **Triple Modular Redundancy (TMR):** Physical triplication with 2-of-3 majority voting applied to the Program Counter (`reg_pc`) and critical control registers.
* **Decoupled Harvard Bus:** Instruction and data memory paths separated via the core's `mem_instr` signal.
* **ECC-Protected Data Memory:** SECDED (*Single Error Correction, Double Error Detection*) protection featuring `sbiterr` and `dbiterr` error status flags.
* **Target Hardware:**
  * *Active Prototyping:* Digilent Nexys A7 100T (AMD Xilinx Artix-7 `xc7a100tcsg324-1`).
  * *Future Deployment:* Microchip PolarFire FPGA (written in portable, standard Verilog-2001).

---

## Repository Structure

```text
shrv32/
├── AGENTS.md          # Technical context, Verilog guidelines, and rules for AI agents[cite: 3, 4]
├── Makefile           # Unified build flow for simulation, firmware, and Vivado
├── external/          # Read-only Git submodules (upstream picorv32 and harv)[cite: 3, 4]
├── rtl/               # Synthesizable Verilog RTL (core, mem, periph, top)[cite: 3, 4]
├── tb/                # Testbenches and XOR fault-injection verification[cite: 3, 4]
├── sw/                # Bare-metal RISC-V firmware (bootloader and test apps)[cite: 3]
├── fpga/nexys_a7/     # Board constraints (.xdc) and Vivado Tcl scripts[cite: 3, 4]
└── docs/              # Engineering logbook, HARV analysis notes, and diagrams[cite: 3, 4]

```

---

## Getting Started

### 1. Clone the repository with submodules

```bash
git clone --recursive https://github.com/jhg45-ua/shrv32.git
cd shrv32
```

### 2. Build & Simulation Commands (`Makefile`)

| Command | Description |
| --- | --- |
| `make sw` | Compiles the bootloader and test firmware into `build/firmware.hex` |
| `make sim` | Runs CLI RTL simulation using **Icarus Verilog** (`iverilog` + `vvp`)
| `make wave` | Opens generated waveforms (`build/dump.vcd`) in **Surfer** |
| `make synth` | Runs synthesis, implementation, and bitstream generation in **Vivado** (batch mode)
| `make vivado-gui` | Generates the `.xpr` project in `build/vivado/` and launches the Vivado GUI |
| `make prog` | Programs the Nexys A7 board via `openFPGALoader` |
| `make clean` | Removes all generated artifacts inside `build/` |

---

## Documentation

* **Development Notes & Diagrams:** Located in [`docs/`](docs/) (`logbook.md`, HARV architectural notes, and editable block diagrams).
* **Formal Technical Report (Oleafy):** *[Link to Oleafy document]*

---

## References & License

* Based on [YosysHQ/picorv32](https://github.com/YosysHQ/picorv32) (ISC License).
* Radiation-hardening architectural reference: [xarc/harv](https://github.com/xarc/harv).
* Released under the **MIT License** (see [`LICENSE`](https://www.google.com/search?q=LICENSE) for details).
