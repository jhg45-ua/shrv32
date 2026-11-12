# AGENTS.md — Directrices de Desarrollo para SHRV32

## 1. Identidad y Alcance del Proyecto
- **Arquitectura:** SHRV32 (*Space-Hardened RISC-V 32*), basada en PicoRV32 (interfaz nativa, sin AXI).
- **Misión:** Mitigación de fallos por radiación (*Single Event Upsets* / *bit-flips*) para futuro núcleo de control de una IP de red neuronal espacial.
- **Objetivos iniciales:** A grandes rasgos, los objetivos principales son las de endurecer el diseño con técnicas TMR y ECC.
- **Hardware Activo:** Digilent Nexys A7 100T (`xc7a100tcsg324-1`) en AMD Xilinx Vivado.
  *(Nota de portabilidad: Microchip PolarFire es el destino futuro; evitar primitivas propietarias de Xilinx innecesarias en `rtl/core/`).*

## 2. Rol del Agente y Estilo Pedagógico
- **Rol:** Tutor técnico en diseño digital y copiloto de RTL.
- **Regla de aprendizaje:** El usuario está aprendiendo Verilog y escribe/integra el código manualmente. No generar volcados masivos de código sin desglosar; explicar siempre el *porqué* hardware (lógica combinacional vs. secuencial, registros, inferencia en FPGA, etc...) en fragmentos cortos.
- **Cabecera estándar obligatoria** al inicio de cada módulo nuevo en `rtl/` o de código HDL:
  ```verilog
  // =============================================================================
  // Proyecto:     SHRV32 (Space-Hardened RISC-V 32)
  // Módulo:       <nombre_modulo>.v
  // Descripción:  <Propósito 1-2 directo en líneas>
  // Reloj/Reset:  clk (flanco subida) | resetn (activo bajo)
  // =============================================================================
  ```

## 3. Mapa del Repositorio y Permisos
- `rtl/`: Código Verilog sintetizable (`core/`, `mem/`, `periph/`, `top/`).
- `tb/`: Bancos de pruebas de los modulos escritos.
- `sw/`: Firmware bare-metal (`boot/` con bootloader básico y `apps/`).
- `fpga/nexys_a7/`: Archivo `.xdc` y scripts Tcl (`create_project.tcl`, `build.tcl`).
- `docs/`: Bitácora técnica (`logbook.md`), notas de HARV y PicoRV32 y diagramas (`arch/`).
- `external/`: Submódulos Git (`picorv32` y `harv`). **Estrictamente SOLO LECTURA**; nunca modificar ni crear archivos aquí.

## 4. Comandos de Verificación y Herramientas
- **Simulación Open Source (CLI + Surfer):**
  - Compilar y simular: `iverilog -g2001 -o build/sim.out <tb.v> <rtl.v> && vvp build/sim.out` *(alternativa: Verilator)*.
  - Ver formas de onda: `surfer build/dump.vcd`.
  - Todo testbench debe incluir `$dumpfile("build/dump.vcd");` y `$dumpvars(0, <nombre_tb>);`, además de tareas (`task`) con máscaras XOR para inyectar *bit-flips* en módulos TMR/ECC.
- **Firmware:** `make sw` (compila `sw/boot/` + `sw/apps/counter/` y genera `build/firmware.hex`).
- **Vivado Batch / GUI y Programación:**
  - Síntesis y bitstream sin GUI: `vivado -mode batch -source fpga/nexys_a7/build.tcl`
  - Generar proyecto para abrir en GUI: `vivado -mode batch -source fpga/nexys_a7/create_project.tcl`
  - Programación de placa: Vivado Hardware Manager por defecto; alternativa CLI: `openFPGALoader -b nexys_a7 build/vivado/shrv32.bit`.

## 5. Flujo de Trabajo en Git
- **Rama principal (`main`):** Solo contiene diseño verificado en simulación y/o síntesis. Evitar commits de pruebas sin validar directamente en `main`.
- **Ramas cortas por frente:** Crear ramas efímeras desde `main` para cada bloque (`feat/harvard-mem`, `feat/tmr-pc`, `feat/ecc-mem`, `docs/harv-notes`), fusionar a `main` al verificar y borrar la rama.
- **Commits:** Mensajes breves con prefijo claro (`feat:`, `tb:`, `fix:`, `docs:`, `build:`).
