# Bitácora Técnica — SHRV32

Registro cronológico de hitos, verificaciones en simulación y métricas reales de implementación (*post-route* `impl_1`) en **Digilent Nexys A7-100T** (`xc7a100tcsg324-1`) para comparar la evolución de recursos y frecuencia frente al diseño base.

---

## [2026-10-30] — Inicio del proyecto: SoC base con PicoRV32 y firmware bare-metal

### Objetivo
Levantar un *System-on-Chip* funcional mínimo en la placa **Digilent Nexys A7-100T** (100 MHz) alrededor del núcleo **PicoRV32** (RV32I, bus nativo sin AXI), sin técnicas de endurecimiento frente a radiación, junto con un flujo de firmware bare-metal propio.

### Trabajo realizado (fase inicial en `picorv32-soc`)
- Integración inicial de `picorv32` conectado a memoria BRAM unificada de 16 KB (4096 palabras de 32 bits), periférico UART (`simpleuart` a 115200 baudios, divisor `868`) y registro de 15 LEDs + indicador `trap` en LED15.
- Desarrollo del firmware básico en C/ensamblador RISC-V (`rv32i` / `ilp32`):
  - **Bootloader UART** en `0x0000_0000`: autocomprobación de LEDs y RAM, mensaje `READY` y recepción de binarios hacia `0x0000_0800`.
  - **Aplicación contador**: parpadeo en `leds[14:0]` y envío periódico de latido por puerto serie.
- Primeras pruebas exploratorias de TMR y ECC sobre la base de trabajo antes de planificar una reorganización limpia por ramas.

---

## [2026-11-13] — Hito 0: Transición a `shrv32` y línea base verificada (`feat/baseline-soc`)

### Cambios de arquitectura y organización
- Reestructuración limpia en `shrv32` con submódulos de solo lectura (`external/picorv32`, `external/harv`), separación modular en `rtl/` (`core/`, `mem/`, `periph/`, `top/`), `sw/` unificado y scripts duales para Vivado batch/GUI (`create_project.tcl`, `build.tcl`).
- Extracción de la memoria a [`bram_sp.v`](../rtl/mem/bram_sp.v) (lectura/escritura síncrona con máscara por bytes `wstrb`) y módulo raíz [`soc.v`](../rtl/top/soc.v) (latencia de lectura de 1 ciclo en BRAM mediante mux combinacional sobre `ram_rdata`).
- Adaptación del firmware en `sw/` (`bootloader.elf`: `564` B; `counter.elf`: `600` B) con recompilación automática ante cambios de `FW` o `SIM_FAST`.

### Verificación en simulación y linting
- **Verilator (`make lint`):** superado sin errores (`0` avisos bloqueantes sobre `soc`).
- **Icarus Verilog (`iverilog -g2001` + `vvp` con `tb_soc.v`):** arranque tras *Power-On Reset* (63 ciclos), banner UART completo, contador en LEDs (`0x0001`..`0x0040` con `[SHRV32 Latido] Contador = 0..3` usando `SIM_FAST=1`, y `Contador = 0` con `SIM_FAST=0`) y salida limpia sin `trap`.

### Métricas de implementación en Vivado (`impl_1` — *Post-Route*)
- **Herramienta y dispositivo:** Vivado `v2025.2` (lin64) · `xc7a100tcsg324-1` (`-1`) · Reloj objetivo `sys_clk_pin` = `100.000 MHz` (`10.000 ns`).

| Recurso / Métrica | Usado | Disponible | Utilización | Notas |
| --- | ---: | ---: | ---: | --- |
| **Slice LUTs** | 1114 | 63400 | 1.76 % | 1070 lógica + 44 LUTRAM (`cpuregs`) |
| **Slice Registers (FF)** | 703 | 126800 | 0.55 % | 680 `FDRE` + 23 `FDSE`, 0 latches |
| **Block RAM Tile (`RAMB36E1`)** | 4 | 135 | 2.96 % | 16 KB (`bram_sp`) inferidos como BRAM |
| **DSPs** | 0 | 240 | 0.00 % | RV32I base sin multiplicador hardware |
| **Bonded IOB** | 20 | 210 | 9.52 % | `clk`, `resetn`, `trap`, `leds[14:0]`, UART |
| **BUFGCTRL** | 1 | 32 | 3.13 % | Reloj principal `clk` |

| Parámetro de Timing (`sys_clk_pin` @ 100 MHz) | Valor | Endpoints con fallo | Notas |
| --- | ---: | ---: | --- |
| **WNS (Setup)** | +3.531 ns | 0 / 2267 | $F_{\max}$ estimada $\approx 154.6\text{ MHz}$ |
| **WHS (Hold)** | +0.104 ns | 0 / 2267 | Cumple holgura mínima |
| **WPWS (Pulse Width)** | +3.750 ns | 0 / 796 | Cumple ancho de pulso |

### Observaciones técnicas
- **Camino crítico:** `ram/mem_reg_3/CLKARDCLK` (`RAMB36E1`) $\rightarrow$ 3 niveles de LUT $\rightarrow$ `cpu/reg_out_reg[10]/D` (`6.373 ns` de retardo de datos).
- **Aviso `SYNTH-6` (x4):** Vivado indica que el registro de salida de las `RAMB36E1` no usa una etapa adicional interna (`DOA_REG`), al estar multiplexado directamente hacia la CPU. Con `+3.531 ns` de margen a 100 MHz no supone problema en la línea base, pero conviene tenerlo en cuenta cuando se añada lógica combinacional de decodificación **ECC** en la ruta de lectura.
- **Aviso `TIMING-18` (x19):** Esperable en esta etapa al tratarse de E/S lentas o asíncronas (`resetn`, `leds`, `trap`, `ser_tx`, `ser_rx`) sin restricciones `set_input_delay`/`set_output_delay` en el `.xdc`.
- **Modo proyecto Vivado:** `$readmemh` en `synth_1`/`sim_1` requiere referenciar `"firmware.hex"` por nombre base y marcar el fichero como `Memory Initialization Files` en `create_project.tcl`.
