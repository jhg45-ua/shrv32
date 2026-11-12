# ==============================================================================
# Makefile raíz — SHRV32 (Space-Hardened RISC-V 32)
# ==============================================================================

BUILD_DIR   := build
VIVADO_DIR  := $(BUILD_DIR)/vivado
TCL_DIR     := fpga/nexys_a7

RTL_SRCS    := $(wildcard rtl/core/*.v rtl/mem/*.v rtl/periph/*.v rtl/top/*.v)
TB          ?= tb/tb_soc.v
PORT        ?= /dev/ttyUSB1
APP         ?= counter
FW          ?= counter
SIM_FAST    ?= 0

.PHONY: help sw upload sim wave lint synth vivado-gui prog clean

help:
	@echo "Comandos disponibles en SHRV32:"
	@echo "  make sw [FW=counter|boot] -> Compila bootloader + app y genera build/firmware.hex"
	@echo "  make upload [PORT=...]    -> Sube build/$(APP).bin al bootloader vía UART"
	@echo "  make sim [TB=...]         -> Compila firmware y simula con iverilog"
	@echo "  make wave                 -> Abre build/dump.vcd en Surfer"
	@echo "  make lint                 -> Comprueba sintaxis y reglas RTL con Verilator"
	@echo "  make synth                -> Síntesis e implementación en Vivado (modo batch)"
	@echo "  make vivado-gui           -> Genera el .xpr y abre la interfaz gráfica de Vivado"
	@echo "  make prog                 -> Programa la Nexys A7 usando openFPGALoader"
	@echo "  make clean                -> Elimina la carpeta build/"

sw:
	@mkdir -p $(BUILD_DIR)
	$(MAKE) -C sw FW=$(FW) SIM_FAST=$(SIM_FAST)

upload: sw
	python3 sw/common/upload.py $(BUILD_DIR)/$(APP).bin $(PORT)

sim: sw
	@mkdir -p $(BUILD_DIR)
	iverilog -g2001 -o $(BUILD_DIR)/sim.out $(TB) $(RTL_SRCS)
	vvp $(BUILD_DIR)/sim.out

wave:
	surfer $(BUILD_DIR)/dump.vcd &

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-UNDRIVEN -Wno-PINCONNECTEMPTY \
		-Wno-PINMISSING -Wno-BLKSEQ -Wno-GENUNNAMED -Wno-PROCASSINIT -Wno-WIDTHTRUNC \
		-Wno-WIDTHEXPAND -Wno-SYNCASYNCNET --top-module soc $(RTL_SRCS)

synth: sw
	@mkdir -p $(VIVADO_DIR)
	vivado -mode batch \
		-source $(TCL_DIR)/build.tcl \
		-log $(VIVADO_DIR)/build.log \
		-journal $(VIVADO_DIR)/build.jou

vivado-gui: sw
	@mkdir -p $(VIVADO_DIR)
	vivado -mode batch \
		-source $(TCL_DIR)/create_project.tcl \
		-log $(VIVADO_DIR)/create.log \
		-journal $(VIVADO_DIR)/create.jou
	vivado $(VIVADO_DIR)/shrv32.xpr \
		-log $(VIVADO_DIR)/gui.log \
		-journal $(VIVADO_DIR)/gui.jou &

prog:
	openFPGALoader -b nexys_a7_100 $(VIVADO_DIR)/shrv32.bit

clean:
	rm -rf $(BUILD_DIR)
