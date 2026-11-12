# ==============================================================================
# Makefile de Firmware — SHRV32
# Compila sw/boot/ y sw/apps/counter/, generando ../build/firmware.hex
# ==============================================================================

TOOLCHAIN ?= riscv64-unknown-elf-
BUILD_DIR := ../build
MEM_WORDS := 4096

# Imagen por defecto en BRAM (0x0): counter (autónomo) o boot (bootloader UART)
FW        ?= counter
SIM_FAST  ?= 0

CFLAGS    := -Os -mabi=ilp32 -march=rv32i -ffreestanding -nostdlib --std=gnu99
ifeq ($(SIM_FAST),1)
CFLAGS    += -DSIM_FAST
endif

LDFLAGS   := -Wl,-Bstatic,-T,boot/sections.ld,--strip-debug
LIBS      := -lgcc

CRT0      := boot/crt0.S
LDS       := boot/sections.ld
IO_H      := common/io.h
MAKEHEX   := common/makehex.py

.PHONY: all clean force_cfg

all: $(BUILD_DIR)/firmware.hex $(BUILD_DIR)/bootloader.hex $(BUILD_DIR)/counter.bin

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Registra FW y SIM_FAST activos para recompilar automáticamente si cambia alguno
CFG_FILE := $(BUILD_DIR)/.sw_cfg
$(CFG_FILE): force_cfg | $(BUILD_DIR)
	@echo "FW=$(FW) SIM_FAST=$(SIM_FAST)" > $@.tmp
	@cmp -s $@.tmp $@ 2>/dev/null || mv $@.tmp $@
	@rm -f $@.tmp

# 1. Bootloader UART en 0x0000_0000
$(BUILD_DIR)/bootloader.elf: $(CRT0) boot/bootloader.c $(LDS) $(IO_H) $(CFG_FILE) | $(BUILD_DIR)
	$(TOOLCHAIN)gcc $(CFLAGS) $(CRT0) boot/bootloader.c \
		$(LDFLAGS),--defsym=ORG=0x0,-Map,$(BUILD_DIR)/bootloader.map $(LIBS) -o $@
	@$(TOOLCHAIN)size $@

$(BUILD_DIR)/bootloader.bin: $(BUILD_DIR)/bootloader.elf
	$(TOOLCHAIN)objcopy -O binary $< $@

$(BUILD_DIR)/bootloader.hex: $(BUILD_DIR)/bootloader.bin $(MAKEHEX)
	python3 $(MAKEHEX) $< $(MEM_WORDS) > $@

# 2. App Counter para carga vía bootloader (ORG=0x800)
$(BUILD_DIR)/counter.elf: $(CRT0) apps/counter/main.c $(LDS) $(IO_H) $(CFG_FILE) | $(BUILD_DIR)
	$(TOOLCHAIN)gcc $(CFLAGS) $(CRT0) apps/counter/main.c \
		$(LDFLAGS),--defsym=ORG=0x800,-Map,$(BUILD_DIR)/counter.map $(LIBS) -o $@
	@$(TOOLCHAIN)size $@

$(BUILD_DIR)/counter.bin: $(BUILD_DIR)/counter.elf
	$(TOOLCHAIN)objcopy -O binary $< $@

# 3. App Counter autónoma en 0x0000_0000 (ideal para simulación y arranque directo)
$(BUILD_DIR)/counter_standalone.elf: $(CRT0) apps/counter/main.c $(LDS) $(IO_H) $(CFG_FILE) | $(BUILD_DIR)
	$(TOOLCHAIN)gcc $(CFLAGS) $(CRT0) apps/counter/main.c \
		$(LDFLAGS),--defsym=ORG=0x0,-Map,$(BUILD_DIR)/counter_standalone.map $(LIBS) -o $@

$(BUILD_DIR)/counter_standalone.bin: $(BUILD_DIR)/counter_standalone.elf
	$(TOOLCHAIN)objcopy -O binary $< $@

$(BUILD_DIR)/counter_standalone.hex: $(BUILD_DIR)/counter_standalone.bin $(MAKEHEX)
	python3 $(MAKEHEX) $< $(MEM_WORDS) > $@

# 4. Imagen activa para $readmemh("build/firmware.hex", ...)
ifeq ($(FW),boot)
$(BUILD_DIR)/firmware.hex: $(BUILD_DIR)/bootloader.hex $(CFG_FILE)
	cp $< $@
else
$(BUILD_DIR)/firmware.hex: $(BUILD_DIR)/counter_standalone.hex $(CFG_FILE)
	cp $< $@
endif

clean:
	rm -f $(BUILD_DIR)/*.elf $(BUILD_DIR)/*.bin $(BUILD_DIR)/*.hex $(BUILD_DIR)/*.map
