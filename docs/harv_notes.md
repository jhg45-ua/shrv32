# Notas sobre el core HARV

Este core utiliza la ISA RISC-V (RV32I) e implementa técnicas de protección contra SEU y SET (*Single Event Upset* y *Single Event Transient*) mediante codificación Hamming y Triple Modular Redundancy (TMR).

> **Contexto y trazabilidad:** El análisis RTL corresponde al submódulo de solo lectura [`external/harv`](../external/harv). Las métricas *post-route* de síntesis *Out-Of-Context* (`harv_*`) y las cifras de referencia de `picorv32-soc` (`system_ecc`, `system_tmr_ecc`) proceden de corridas previas en Vivado `v2025.2` (`xc7a100tcsg324-1`, 100 MHz) externas a los scripts actuales de este repositorio (actualmente en Hito 0, [`logbook.md`](logbook.md)).

## 1. Protección TMR
El core HARV implementa TMR con una estrategia "macro" donde se sigue el patron de envolver los modulos sin modificar su codigo RTL interno. Desde el *top-level* (`external/harv/hdl/harv.vhd`), la redundancia se habilita en tiempo de elaboracion mediante genericos booleanos independientes (`TMR_CONTROL` y `TMR_ALU`, ambos a `FALSE` por defecto), sustituyendo las instancias `control` y `alu` por los *wrappers* `control_tmr` y `alu_tmr`.

### 1.1. Cobertura y bloques protegidos
HARV no aplica TMR a todo el procesador, sino que reparte la mitigacion entre TMR y codificacion Hamming segun la naturaleza de cada bloque:

- **`control_tmr` (`external/harv/hdl/ft_components/control_tmr.vhd`):** envuelve 3 replicas completas de `control`. Esto triplica tanto la FSM secuencial de 6 estados (`proc_status_r`: `STAT_IDLE`, `STAT_REQ_INSTR`, `STAT_RUN`, `STAT_DMEM_STALL`, `STAT_UPDATE_PC`, `STAT_TRAP`) como toda la logica combinacional de decodificacion de instrucciones y generacion de señales de control. Sus 24 salidas pasan por 24 votadores mayoritarios.
- **`alu_tmr` (`external/harv/hdl/ft_components/alu_tmr.vhd`):** envuelve 3 replicas completas de `alu`. Como `alu` es un bloque **puramente combinacional** (sin reloj ni biestables), este TMR no mitiga SEUs en flip-flops, sino transitorios combinacionales (**SET**) o fallos por radiacion en la memoria de configuracion (CRAM/LUTs) de la FPGA. Sus salidas (`zero_o` de 1 bit y `data_o` de 32 bits) se votan bit a bit.
- **Bloques fuera del dominio TMR:** el *PC* e *IR* (`instr_fetch`) y el banco de registros (`regfile`) se protegen opcionalmente mediante Hamming (`HAMMING_PC`, `HAMMING_REGFILE`), mientras que el bloque `csr` queda **sin proteccion** (ni TMR ni Hamming).

### 1.2. Arquitectura interna de los *wrappers* (`gen_TMR`, votación y detección)
Tanto `control_tmr` como `alu_tmr` siguen exactamente el mismo esquema estructural:

1. **Replicacion 3x sin triplicar votador:** mediante `gen_TMR : for i in 2 downto 0 generate`, las 3 instancias (`control_u` o `alu_u`) reciben las mismas entradas compartidas y generan 3 vectores paralelos de salida. El votador final es unico (punto de convergencia en la salida).
2. **Votacion mayoritaria bit a bit:** cada señal o bus de salida se corrige con la ecuacion mayoritaria clasica:
   ```vhdl
   corr <= (x(2) and x(1)) or (x(2) and x(0)) or (x(1) and x(0));
   ```
   En `control_tmr` hay 24 votadores independientes; en `alu_tmr`, un votador de 1 bit (`corr_zero_w`) y 32 votadores en paralelo (`corr_data_w`).
3. **Deteccion de discrepancias y telemetria CSR:** en paralelo al votador, una red XOR detecta si alguna replica difiere de las otras dos (`(x(2) xor x(1)) or (x(2) xor x(0)) or (x(1) xor x(0))`, usando `or_reduce` en buses como `aluop_w` o `data_w`). Todas las discrepancias se agrupan mediante una puerta OR en la salida `error_o`, que alimenta dos contadores de 32 bits en `csr.vhd`:
   - `0x7C8` (`control_err_r`): habilitado permanentemente (`control_cen_i => '1'`).
   - `0x7C9` (`alu_err_r`): habilitado unicamente cuando la salida de la ALU es relevante (`alu_cen_i => dmem_gnt_i or update_pc_w or ctl_regwr_w`), evitando contar falsos transitorios cuando la ALU no se esta escribiendo ni usando para saltar.

### 1.3. Atributos de síntesis (Vivado y portabilidad a PolarFire)
Un sintetizador optimiza y fusiona automaticamente tres modulos identicos conectados a las mismas entradas. Para evitarlo, HARV anota directamente las instancias `control_u` y `alu_u` dentro de `gen_TMR` con atributos multi-herramienta:

- **AMD Xilinx Vivado:** `attribute DONT_TOUCH of <instancia> : label is "TRUE";`. Obliga a conservar integras las 3 copias de la jerarquia e impide fusionar logica a traves de sus pines.
- **Synplify (Microchip PolarFire):**
  - `syn_radhardlevel = "tmr"`: indica al sintetizador que la instancia forma parte de un esquema TMR.
  - `syn_keep = TRUE` y `syn_noprune = TRUE`: evitan eliminacion o fusion de redes e instancias redundantes.
  - `syn_safe_case = TRUE`: fuerza a mantener la logica de recuperacion hacia estados seguros (`when others => next_proc_status_w <= STAT_TRAP;` en `control.vhd`) en caso de estado invalido.

**Matiz hardware observado en Vivado:** al colocar `DONT_TOUCH` en las instancias hijas (`control_u`, `alu_u`) pero no en los votadores del *wrapper*, Vivado conserva intactas las 3 replicas (en `harv_tmr_all`, las 3 `alu_u` consumen `514`, `511` y `481` LUTs respectivamente, y `control_tmr` conserva `9` FFs = 3 replicas x 3 bits de `proc_status_r` codificada como `FSM_sequential_proc_status_r_reg`). Sin embargo, la logica externa del votador/mux queda libre para ser absorbida en LUTs compartidas con etapas posteriores.

### 1.4. Conmutación dinámica de la corrección (*bypass* por software)
Una particularidad de HARV es que sus *wrappers* incorporan la entrada `correct_error_i`, controlada desde el registro CSR `harden_conf_r` en la direccion `0xBC0` (`hard_control_o <= harden_conf_r(4)` y `hard_alu_o <= harden_conf_r(5)`). En la salida de cada votador existe un multiplexor 2:1:

```vhdl
-- Si correct_error_i = '1' usa el valor votado; si = '0', pasa directo el canal 0 sin corregir
data_o <= corr_data_w when correct_error_i = '1' else data_w(0);
```

- **Objetivo:** permitir activar o desactivar la correccion TMR en tiempo de ejecucion desde firmware (por ejemplo, en campañas de irradiacion bajo haz de particulas para comparar la tasa de fallos con y sin mitigacion sobre el mismo bitstream). Incluso en modo *bypass*, la red XOR y los contadores `0x7C8`/`0x7C9` siguen detectando y contabilizando discrepancias entre las 3 replicas. Ademas, el CSR `mimpid` (`mimpid_r(4)` y `mimpid_r(5)`) informa al software de que opciones TMR se incluyeron al sintetizar.
- **Debilidades de esta implementacion en `csr.vhd`:**
  1. **Sin reset definido:** `harden_conf_r` solo se actualiza ante escritura CSR en `0xBC0`, sin clausula de reset. Si arranca a `'0'`, el procesador empieza usando solo el canal `0` sin votar hasta que el codigo de arranque escriba en `0xBC0`.
  2. **Punto unico de fallo (SPOF):** `harden_conf_r` es un registro unico sin TMR ni Hamming. Un solo SEU en el bit `4` o `5` de `harden_conf_r` desactiva la correccion TMR en pleno vuelo.
  3. **Sin ahorro de area ni retardo:** las 3 replicas siguen sintetizadas y conmutando; ademas, el mux de *bypass* añade un nivel de multiplexacion extra justo detras del votador.

### 1.5. Debilidad arquitectónica crítica: ausencia de *self-healing* en `control_tmr`
El enfoque "macro" de no tocar `control.vhd` introduce un problema estructural grave en la maquina de estados `proc_status_r`:

```text
proc_status_r(i) ──► logica next_proc_status_w(i) ──► proc_status_r(i)   (bucle cerrado por replica)
                              │
                              ▼
                  salidas(i) ──► Votador mayoritario ──► salida corregida
```

El estado votado **nunca se realimenta** hacia los biestables `proc_status_r` de las tres replicas:

- **Que pasa ante 1 SEU en `proc_status_r(0)`:** en ese ciclo el votador enmascara el fallo gracias a las replicas `1` y `2` (el resto del core ve la salida correcta). **Sin embargo, la replica `0` no se corrige en el ciclo siguiente**, porque su propio bucle secuencial calcula el proximo estado a partir de su propio valor corrupto (pudiendo divergir de por vida o quedar atrapada en `STAT_TRAP`).
- **Consecuencia:** la replica afectada queda permanentemente desincronizada hasta un reset global del sistema, disparando `error_o` de forma continua en `0x7C8` y dejando al sistema indefenso frente a un segundo SEU en cualquiera de las otras dos replicas (acumulacion de errores).

### 1.6. Impacto en área y timing (Vivado v2025.2, `xc7a100tcsg324-1`, 100 MHz)
A partir de los reportes *Routed* de sintesis *standalone* del modulo `harv` (sin SoC alrededor ni IBUF/BUFG de reloj):

| Configuracion HARV | LUTs | FFs | WNS (100 MHz) | Niveles logicos | $F_{\max}$ aprox. |
| :--- | :---: | :---: | :---: | :---: | :---: |
| `harv_base` (sin FT) | 845 | 136 | -3.141 ns | 22 | ~76.1 MHz |
| `harv_tmr_ctrl` (`TMR_CONTROL`) | 928 (+9.8%) | 147 (+11) | -4.322 ns | 22 | ~69.8 MHz |
| `harv_tmr_all` (`TMR_CONTROL + TMR_ALU`) | 1995 (+136.1%) | 195 (+59) | -5.515 ns | 31 | ~64.5 MHz |
| `harv_ft_full` (TMR + Hamming PC/Regfile) | 3958 (+368.4%) | 1814 (+1678) | -17.504 ns | 27 | ~36.4 MHz |

*(Nota sobre los reportes: en `base`, `tmr_ctrl` y `tmr_all`, el banco de registros `regfile_u` desaparece de la jerarquia sintetizada; en `external/harv/hdl/regfile.vhd`, la rama `g_NORMAL` incluye la comparacion metalogica `rd_i /= "UUUUU"` que probablemente induce a Vivado a podarlo al sintetizar el core aislado, mientras que la rama `g_HAMMING` omite esa comprobacion y en `harv_ft_full` si instancia 1209 FFs para `31 x 39` bits).*

Lecturas principales de estos datos:
- **Camino critico ya comprometido en base:** en `harv_base` el camino critico (`13.088 ns`) encadena `register_instr_u` -> decodificacion (`control`) -> `alu` -> `pc_adder_w` -> `register_pc_u` en un unico ciclo, por lo que cualquier logica de votacion intercalada empeora directamente la frecuencia maxima.
- **`TMR_CONTROL` es ligero en area pero penaliza el camino critico:** solo añade `83` LUTs y `6` FFs de estado adicionales (mas `5` FFs en `csr_u` hasta totalizar `+11` FFs), pero el votador + mux de *bypass* (`harden_conf_r[4]`) suman `+1.181 ns` al retardo critico (`WNS` de `-3.141 ns` a `-4.322 ns`).
- **`TMR_ALU` es muy costoso en FPGA:** solo el *wrapper* `alu_tmr` consume **`1559` LUTs** (mas que todo un SoC PicoRV32 completo con TMR incluido, que ocupa `1357` LUTs en `picorv32-soc`) y encadena dos etapas consecutivas de votacion/mux en el mismo ciclo (`control_tmr` -> `alu_tmr` -> `pc_adder_w`), disparando la profundidad a **31 niveles logicos** y hundiendo la frecuencia maxima a ~64.5 MHz.

### 1.7. Comparativa con `picorv32-soc` y conclusiones para SHRV32
Mientras HARV aplica TMR "macro" por bloques completos sin *self-healing* (y con TMR combinacional en la ALU), en `picorv32-soc` se aplico un TMR **selectivo (*fine-grained*)** sobre los biestables de mayor impacto arquitectonico (`cpu_state`, `reg_pc`, `reg_next_pc`, `latched_rd`, `mem_state`):

- **Coste mucho menor en `picorv32-soc`:** en el SoC completo (`xc7a100tcsg324-1`, 100 MHz), el TMR pasa de `1100` LUTs / `703` FFs (`WNS = +3.056 ns`, $F_{\max} \approx 144\text{ MHz}$) a **`1357` LUTs (+23.4%) / `870` FFs (+23.8%)**, manteniendo `WNS = +2.426 ns` ($F_{\max} \approx 132\text{ MHz}$) y los mismos `5` niveles logicos.
- **Que aprovechar de HARV para SHRV32:**
  - Combinar atributos de sintesis de **Vivado (`DONT_TOUCH` / `keep`) y Synplify (`syn_radhardlevel="tmr"`, `syn_keep`, `syn_noprune`, `syn_safe_case`)** para garantizar portabilidad real entre Nexys A7 y Microchip PolarFire.
  - Exponer señales `fault_detected` / `error_o` hacia contadores CSR de diagnostico para validar tasas de fallo.
- **Que evitar de HARV en SHRV32:**
  - **Nunca usar TMR en caja negra sin *self-healing*** en FSMs o registros de estado: el votador debe realimentar directamente a la entrada D de las 3 copias para lograr autoreparacion en 1 ciclo de reloj.
  - **Evitar triplicar bloques combinacionales grandes como la ALU (`alu_tmr`)** salvo necesidad demostrada frente a SET, priorizando los flip-flops criticos (`reg_pc`, FSM de control, estado de memoria) para preservar area y frecuencia.
  - Si se implementa un registro de configuracion/bypass, protegerlo o iniciarlo con reset en estado mitigado activo por defecto para no introducir un SPOF.

---

## 2. Protección mediante codificación Hamming
El core HARV complementa el TMR de la logica de control y calculo protegiendo sus principales elementos de almacenamiento interno mediante codificacion Hamming SEC-DED (*Single Error Correction, Double Error Detection*). Desde el *top-level* (`external/harv/hdl/harv.vhd`), esta mitigacion se habilita en elaboracion mediante dos genericos booleanos independientes (`HAMMING_REGFILE` y `HAMMING_PC`, ambos a `FALSE` por defecto), apoyados en los modulos de `external/harv/hdl/ft_components/` (`hamming_pkg.vhd`, `hamming_encoder.vhd`, `hamming_decoder.vhd` y `hamming_register.vhd`).

### 2.1. Cobertura y bloques protegidos
HARV aplica codigo Hamming unicamente sobre registros de datos e instruccion dentro del procesador, delegando la memoria principal al SoC externo:

- **`instr_fetch` (`HAMMING_PC`):** sustituye los biestables simples por instancias de `hamming_register` de 39 bits:
  - `register_pc_u` (**PC**, valor de reset `PROGRAM_START_ADDR`): corrige el PC al vuelo y exporta `sbu_o`/`dbu_o` hacia los contadores CSR.
  - `register_instr_u` (**Instruction Register**, valor de reset `0`): protege la instruccion capturada de `imem_instr_i`, pero deja sus salidas `single_err_o` y `double_err_o` sin conectar (`open`), por lo que sus errores no quedan registrados en telemetria.
- **`regfile` (`HAMMING_REGFILE` en `external/harv/hdl/regfile.vhd`):** la rama `g_HAMMING` amplia el array `regfile_r(31 downto 1)` a palabras de **39 bits** (`32` datos + `7` paridad), manteniendo `x0` cableado a `39` ceros. Usa **1 `hamming_encoder`** compartido en el puerto de escritura (`data_i`) y **2 `hamming_decoder` independientes** en los puertos de lectura combinacional (`rs1_i` y `rs2_i`).
- **Memoria de datos externa (`dmem`):** el nucleo no incluye el ECC de la RAM; unicamente expone la señal de habilitacion `hard_dmem_o` y recibe `dmem_sbu_i` y `dmem_dbu_i` desde el controlador de memoria del SoC.
- **Bloques fuera del dominio Hamming:** todo el bloque `csr` (`cycle_r`, `uepc_r`, `ucause_r`, `harden_conf_r` y los propios contadores de fallos) utiliza biestables simples de 32 bits sin proteccion. Tampoco existe interfaz ECC (`sbu`/`dbu`) para la memoria de instrucciones externa (`imem`), solo la señal de fallo de bus `imem_err_i`.

### 2.2. Arquitectura interna del código SEC-DED (39,32)
Todos los bloques Hamming dentro de HARV fijan `DETECT_DOUBLE = TRUE` sobre `DATA_SIZE = 32` (`get_ecc_size(32, TRUE) = 7` bits):

1. **Formato sistematico (`hamming_encoder.vhd`):** la palabra codificada se construye concatenando los bits de redundancia en la parte alta sin intercalar los datos (`encoded_o <= parity_data_w & data_i`):
   - `[31:0]`: dato original de 32 bits.
   - `[37:32]`: 6 bits de paridad par Hamming calculados mediante `xor_reduce` sobre los indices definidos en la tabla `PARITY_POS` de `hamming_pkg.vhd`.
   - `[38]`: bit adicional de paridad global sobre los 38 bits `[37:0]`.
2. **Decodificacion puramente combinacional (`hamming_decoder.vhd`):**
   - Recalcula las 6 paridades sobre `[31:0]` y obtiene el sindrome `parity_diff_w` haciendo XOR con `[37:32]`.
   - Genera una mascara de correccion de 32 bits (`corr_mask_w`) comparando `parity_diff_w` contra las constantes `ERROR_BIT(0..31)` mediante `nor_reduce`. **Solo corrige bits de datos `[31:0]`** (si el error cae en `[37:32]`, el sindrome corresponde a una potencia de 2 ausente en `ERROR_BIT` y la mascara queda a cero).
   - Clasifica el error combinando el sindrome con la paridad total `addit_parity_w <= xor_reduce(encoded_i)` y `hamm_err_w <= or_reduce(parity_diff_w)`:
     ```vhdl
     double_err_w <= (not addit_parity_w) and hamm_err_w; -- sindrome != 0 y paridad global par -> 2 errores
     single_err_w <= hamm_err_w and not double_err_w;     -- sindrome != 0 y paridad global impar -> 1 error
     ```
3. **Encapsulado `hamming_register.vhd`:** situa `hamming_encoder` a la entrada `D` de `reg_r` (39 bits) y `hamming_decoder` a la salida `Q`, precalculando la palabra codificada de reset como `get_parity_data_result(RESET_VALUE, TRUE) & RESET_VALUE`.

### 2.3. Telemetría CSR y conmutación dinámica (*bypass* por software)
Al igual que en los *wrappers* TMR, la deteccion permanece siempre activa pero la correccion sobre `data_o` se habilita o deshabilita dinamicamente mediante `correct_error_i`:

```vhdl
corr_data_w <= (encoded_i(31 downto 0) xor corr_mask_w) when correct_error_i = '1' else encoded_i(31 downto 0);
data_o      <= corr_data_w when single_err_w = '1' else encoded_i(31 downto 0);
```

- **Configuracion e identificacion:** `mimpid` (`0xF13`) indica si el core se sintetizo con `HAMMING_PC` (bit `0`) y `HAMMING_REGFILE` (bit `1`). El registro `harden_conf_r` (`0xBC0`) controla en tiempo de ejecucion `hard_pc_o` (bit `0`), `hard_regfile_o` (bit `1`) y `hard_dmem_o` (bit `2`).
- **Contadores CSR de errores (`csr.vhd`):** disponen de 8 contadores de 32 bits en las direcciones `0x7C0`–`0x7C7` (`reg1_sbu_r`, `reg1_dbu_r`, `reg2_sbu_r`, `reg2_dbu_r`, `pc_sbu_r`, `pc_dbu_r`, `dmem_sbu_r`, `dmem_dbu_r`). En `harv.vhd`, sus habilitaciones de conteo (`*_cen_i`) se muestrean con `update_pc_w` para `reg1`, `reg2` y `pc` (una vez por instruccion) y con `dmem_gnt_i and not ctl_mem_wr_w` para lecturas validas de `dmem`, evitando contar multiples ciclos durante estados de espera.

### 2.4. Debilidades y bugs detectados en el RTL
El analisis detallado de `external/harv` revela varias carencias importantes respecto a un diseño robusto para espacio:

1. **Ausencia de *scrubbing* (reescritura correctiva):** tanto `hamming_register` como `regfile` corrigen unicamente en el camino combinacional de salida (`data_o`), sin realimentar la palabra corregida hacia el biestable almacenado. Si un registro de vida larga (p. ej., un puntero o constante en `regfile`) sufre un SEU y no se sobrescribe antes de recibir un segundo bit-flip, evoluciona a un error doble incorregible (`double_err_o = '1'`).
2. **Bug en `get_parity_data_result` para reset no nulo (`hamming_pkg.vhd:123-125`):** al generar `RESET_VALUE_HAMMING`, la funcion devuelve `xor_reduce(par_data) & par_data`, **omitiendo incluir `data` en el calculo de la paridad global** (a diferencia de `hamming_encoder`, que si calcula `xor_reduce(par_data & data_i)`). Con `PROGRAM_START_ADDR = 0x00000000` el fallo queda oculto porque el peso binario es par, pero con cualquier `RESET_VALUE` de peso impar, el bit `[38]` arranca invertido tras el reset y el primer SEU sobre `[37:0]` sera clasificado falsamente como error doble sin corregir.
3. **Bit de paridad global `[38]` ciego para `single_err_o`:** un bit-flip en `[38]` deja `parity_diff_w = 0` (`hamm_err_w = '0'`) y `addit_parity_w = '1'`, por lo que `single_err_o` y `double_err_o` permanecen a `'0'`. Aunque el dato no se corrompe en ese instante, el fallo queda oculto sin contabilizar hasta que un segundo SEU provoca un `double_err_o` directo.
4. **Traps por ECC de memoria desactivados (`control.vhd:172`):** aunque `harv.vhd` define codigos `ucause` especificos (`0x10` para `dmem_sbu_i` y `0x20` para `dmem_dbu_i`), en `control.vhd` la condicion `or dmem_sbu_i = '1' or dmem_dbu_i = '1'` esta comentada, por lo que `dmem_sbu_i`/`dmem_dbu_i` solo incrementan los contadores CSR sin disparar `STAT_TRAP`.
5. **Otras deficiencias de diseño y verificacion:**
   - **`harden_conf_r` sin reset y SPOF:** igual que en TMR, arranca deshabilitado (`0` en FPGA) y es vulnerable a un unico SEU en `csr.vhd`.
   - **Falsos conteos y poda en `regfile`:** los puertos `rs1_i`/`rs2_i` siempre decodifican `instr_w(19:15)` y `instr_w(24:20)` aunque la instruccion (como `LUI` o `ADDI`) no consuma `rs2`, pudiendo disparar `sbu2_o`/`dbu2_o`. Por otro lado, la comparacion `<` (en vez de `<=`) en `get_ecc_size` sobredimensiona en 1 bit fronteras exactas como `DATA_SIZE = 4`.
   - **Arbol XOR desbalanceado:** al usar Hamming estandar con paridad global en lugar de Hsiao, las filas de `PARITY_POS` para 32 bits suman pesos de `18, 18, 18, 15, 15, 6` datos, y el bit `[38]` exige un `xor_reduce` de **38/39 entradas**, penalizando la profundidad de LUTs.

### 2.5. Impacto en área y timing (Vivado v2025.2, `xc7a100tcsg324-1`, 100 MHz)
A partir de los reportes *Routed* de sintesis *Out-Of-Context* de `harv` sobre Nexys A7-100T:

| Configuracion HARV | LUTs | FFs (+Latches) | MUXF7 | LUTRAM | WNS (100 MHz) | Niveles logicos | $F_{\max}$ aprox. |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `harv_base` (sin FT) | 845 | 136 (136+0) | 0 | 0 | -3.141 ns | 22 | ~76.1 MHz |
| `harv_ecc` (`HAMMING_REGFILE + HAMMING_PC`) | 2674 (+216.4%) | 1808 (1806+2) | 306 | 0 | -14.964 ns | 29 | ~40.1 MHz |
| `harv_tmr_all` (`TMR_CONTROL + TMR_ALU`) | 1995 (+136.1%) | 195 (193+2) | 4 | 0 | -5.515 ns | 31 | ~64.5 MHz |
| `harv_ft_full` (TMR + Hamming PC/Regfile) | 3958 (+368.4%) | 1814 (1812+2) | 313 | 0 | -17.504 ns | 27 | ~36.4 MHz |

Desglose jerarquico de `harv_ecc` frente a `harv_base`:
- **`regfile_u`:** pasa de desaparecer de la jerarquia en `base` (donde `g_NORMAL` es podada por la herramienta —probablemente por `rd_i /= "UUUUU"`—) a consumir **`1308 LUTs`, `1209 FFs` (`31 x 39` bits) y `0 LUTRAMs`**. A nivel global de `harv_ecc` aparecen **`306 MUXF7`** (frente a `0` en `harv_base` y `4` en `harv_tmr_all`), reflejando que Vivado no infiere memoria distribuida (`RAM32M`), sino biestables individuales con multiplexores combinacionales 31:1 en los puertos de lectura (visibles dentro de `regfile_u` en el camino critico) mas los decodificadores y el codificador Hamming.
- **`instr_fetch_u`:** `register_pc_u` sube de `25 LUTs / 32 FFs` a **`80 LUTs / 39 FFs`** (`+55 LUTs`, `+7 FFs` de paridad); `register_instr_u` (en el que Vivado absorbe logica de decodificacion y control adyacente al disolver jerarquias sin `DONT_TOUCH`) sube de `803 LUTs / 32 FFs` a **`1240 LUTs / 39 FFs`**.
- **`csr_u`:** sube de `10 LUTs / 69 FFs` a **`42 LUTs / 518 FFs`** (`+449 FFs`), al dejar de podarse los registros contadores SBU/DBU de 32 bits y `harden_conf_r` cuando se conectan las señales reales de error. (Nota: los 2 latches `LDPE`+`LDCE` proceden de `rstcause_r` en `p_RSTCAUSE`).

**Analisis del camino critico:**
Al tratarse de una microarquitectura uniciclo sin *pipeline* entre etapas, activar Hamming encadena hasta tres etapas ECC en serie dentro del mismo periodo de reloj:
```text
register_instr_u (FF) -> hamming_decoder (IR) -> control -> regfile (MUXF7 + hamming_decoder) -> alu -> pc_4_o / mux WB -> hamming_encoder (regfile) -> regfile_r (FF)
```
En `harv_ecc`, el camino critico (`instr_fetch_u/register_instr_u/g_HAMMING_REG.reg_r_reg[30]` $\rightarrow$ `regfile_u/g_HAMMING.regfile_r_reg[12][32]`, con `control`/`alu` disueltos en la jerarquia) alcanza **`24.840 ns`** (`29` niveles logicos: **`19.753 ns` —el `79.5%`— de retardo de enrutado** frente a `5.087 ns` de logica, con alto *fanout* en señales como la salida hacia `regfile_u` `fo=315` y `data_wr_enc_w` `fo=31`), hundiendo la frecuencia maxima a **~40.1 MHz**. En `harv_ft_full`, donde `DONT_TOUCH` conserva explicitamente las instancias TMR, el camino critico (`register_instr_u/g_HAMMING_REG.reg_r_reg[21]` $\rightarrow$ `hamming_decoder_u` $\rightarrow$ `instr_w[7]` `fo=263` $\rightarrow$ `regfile_u` `MUXF7` + `hamming_decoder_data2_u` $\rightarrow$ `alu_u` $\rightarrow$ `control_u` $\rightarrow$ `pc_4_o[26]` $\rightarrow$ `hamming_encoder_u` $\rightarrow$ `regfile_r_reg[8][33]`) alcanza **`27.380 ns`** (`27` niveles, **`22.524 ns` —`82.3%`— de enrutado**, **~36.4 MHz**).

### 2.6. Comparativa con `picorv32-soc` y conclusiones para SHRV32
Mientras HARV aplica Hamming estandar pasivo sobre un core uniciclo sintetizando el banco de registros en FFs (sin cubrir la memoria principal), `picorv32-soc` utilizo una matriz **Hsiao SEC-DED (39,32)** de peso 3 constante sobre LUTRAM con *auto-scrubbing* y BRAM con controlador *Read-Modify-Write*:

- **Diferencia abismal en FPGA (`xc7a100tcsg324-1`, 100 MHz):** en `picorv32-soc`, el SoC completo con ECC en banco de registros y BRAM (`system_ecc`) ocupa **`1595` LUTs (+45.0%), `694` FFs (-1.3%, usando `84` LUTRAMs: `20 RAM32M` + `4 RAM32X1D`)** con `WNS = -1.011 ns` ($F_{\max} \approx 90.8\text{ MHz}$), y el SoC completo TMR+ECC (`system_tmr_ecc`) alcanza **`1856` LUTs / `861` FFs** con `WNS = -0.547 ns` ($F_{\max} \approx 94.8\text{ MHz}$), frente a los `3958` LUTs / `1814` FFs y `~36.4 MHz` del core aislado de HARV.
- **Que aprovechar de HARV para SHRV32:**
  - Su **capa de observabilidad y control**: exponer contadores de eventos `SBU`/`DBU` (separando banco de registros, PC y memoria) y flags de estado/capacidades hacia software (mediante CSRs o registros MMIO), filtrando las habilitaciones de conteo por transaccion valida.
- **Que evitar y mejorar en SHRV32:**
  - **Usar codigo Hsiao (39,32) balanceado en lugar de Hamming estandar + paridad global:** reduce el *fan-in* a 13–14 entradas por bit, elimina el arbol XOR global de 39 bits y trata de forma uniforme los 39 bits ante fallos simples y dobles.
  - **Implementar *auto-scrubbing* obligatorio:** en el banco de registros (`picorv32_regs`), aplicar reescritura oportunista en `(!wen && sbiterr)` cuando la CPU no escribe y solo ante error simple corregible (nunca ante `dbiterr`), ademas de realimentacion correctiva en registros protegidos para evitar acumulacion de SEUs.
  - **Inferir LUTRAM (`RAM32M`) en `picorv32_regs` y mantener ejecucion multiciclo/segmentada:** evita explotar a >1200 FFs + arboles `MUXF7` y evita encadenar decodificadores ECC en un camino critico de extremo a extremo.
  - **Implementar el ECC de la memoria BRAM dentro del SoC (`rtl/mem/bram_sp.v` + RMW para `sb`/`sh`):** en Artix-7 no depender de `blk_mem_gen_ecc` si requiere inicializacion de firmware (por la restriccion de archivos `.coe` en PG058) y valorar una etapa de registro adicional en la salida ECC de BRAM para sostener los `100 MHz`.

