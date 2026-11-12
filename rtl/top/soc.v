// =============================================================================
// Proyecto:     SHRV32 (Space-Hardened RISC-V 32)
// Módulo:       soc.v
// Descripción:  Módulo raíz del SoC base (PicoRV32 + BRAM 16 KB + UART + LEDs)
// Reloj/Reset:  clk (flanco subida, 100 MHz) | resetn (activo bajo)
// =============================================================================

module soc #(
    parameter integer MEM_SIZE      = 4096,
    parameter         FIRMWARE_FILE = "build/firmware.hex"
) (
    input             clk,     // Reloj del sistema a 100 MHz (Nexys A7 pin E3)
    input             resetn,  // Botón externo de reset activo bajo (CPU_RESETN)
    output            trap,    // Indicador de trampa de la CPU (insn ilegal / desalineada -> LED15)
    output reg [14:0] leds,    // 15 LEDs de usuario mapeados en 0x1000_0000
    output            ser_tx,  // Línea TX UART hacia el puente USB-UART FTDI
    input             ser_rx   // Línea RX UART desde el puente USB-UART FTDI
);

  // Power-On Reset (POR): mantiene sys_resetn bajo durante 63 ciclos tras soltar resetn
  reg [5:0] reset_cnt = 6'd0;
  wire sys_resetn = &reset_cnt;

  always @(posedge clk) begin
    if (!resetn) reset_cnt <= 6'd0;
    else if (!sys_resetn) reset_cnt <= reset_cnt + 6'd1;
  end

  // Interfaz nativa de memoria de PicoRV32 (protocolo valid/ready, sin AXI)
  wire        mem_valid;
  wire        mem_instr;
  reg         mem_ready;
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  wire [ 3:0] mem_wstrb;
  wire [31:0] mem_rdata;

  // Decodificador combinacional de direcciones: selecciona el esclavo en cuanto mem_valid sube
  wire        ram_sel = mem_valid && ((mem_addr >> 2) < MEM_SIZE);  // 0x0000_0000 - 0x0000_3FFF
  wire        leds_sel = mem_valid && (mem_addr == 32'h1000_0000);
  wire        uart_div_sel = mem_valid && (mem_addr == 32'h2000_0004);
  wire        uart_dat_sel = mem_valid && (mem_addr == 32'h2000_0008);

  // Núcleo PicoRV32 RV32I base (sin endurecimiento TMR)
  picorv32 #(
      .ENABLE_COUNTERS     (1),
      .ENABLE_COUNTERS64   (0),
      .ENABLE_REGS_16_31   (1),
      .ENABLE_REGS_DUALPORT(1),
      .TWO_STAGE_SHIFT     (1),
      .BARREL_SHIFTER      (1),
      .COMPRESSED_ISA      (0),
      .CATCH_MISALIGN      (1),
      .CATCH_ILLINSN       (1),
      .REGS_INIT_ZERO      (1)
  ) cpu (
      .clk         (clk),
      .resetn      (sys_resetn),
      .trap        (trap),
      .mem_valid   (mem_valid),
      .mem_instr   (mem_instr),
      .mem_ready   (mem_ready),
      .mem_addr    (mem_addr),
      .mem_wdata   (mem_wdata),
      .mem_wstrb   (mem_wstrb),
      .mem_rdata   (mem_rdata),
      .mem_la_read (),
      .mem_la_write(),
      .mem_la_addr (),
      .mem_la_wdata(),
      .mem_la_wstrb(),
      .pcpi_valid  (),
      .pcpi_insn   (),
      .pcpi_rs1    (),
      .pcpi_rs2    (),
      .pcpi_wr     (1'b0),
      .pcpi_rd     (32'h0),
      .pcpi_wait   (1'b0),
      .pcpi_ready  (1'b0),
      .irq         (32'h0),
      .eoi         ()
  );

  // BRAM unificada de 16 KB (instrucciones, datos y pila)
  // El direccionamiento por palabra usa mem_addr[13:2], descartando los bits de byte [1:0]
  wire [31:0] ram_rdata;

  bram_sp #(
      .WORDS    (MEM_SIZE),
      .ADDR_BITS(12),
      .INIT_FILE(FIRMWARE_FILE)
  ) ram (
      .clk(clk),
      .en   (ram_sel && !mem_ready),  // Cualificado con !mem_ready para evitar doble acceso en el ciclo final
      .wstrb(mem_wstrb),
      .addr(mem_addr[13:2]),
      .wdata(mem_wdata),
      .rdata(ram_rdata)
  );

  // Controlador UART (divisor a 115200 baudios configurado por firmware)
  wire [31:0] uart_div_do;
  wire [31:0] uart_dat_do;
  wire        uart_dat_wait;

  simpleuart uart (
      .clk         (clk),
      .resetn      (sys_resetn),
      .ser_tx      (ser_tx),
      .ser_rx      (ser_rx),
      // Cualifica los strobes con !mem_ready para que los pulsos de control duren exactamente 1 ciclo
      .reg_div_we  ((uart_div_sel && !mem_ready) ? mem_wstrb : 4'b0000),
      .reg_div_di  (mem_wdata),
      .reg_div_do  (uart_div_do),
      .reg_dat_we  (uart_dat_sel && mem_wstrb[0] && !mem_ready),
      .reg_dat_re  (uart_dat_sel && !(|mem_wstrb) && !mem_ready),
      .reg_dat_di  (mem_wdata),
      .reg_dat_do  (uart_dat_do),
      .reg_dat_wait(uart_dat_wait)
  );

  // Controlador síncrono de respuesta del bus y multiplexor de lectura
  reg        ram_read_r;
  reg [31:0] mmio_rdata;

  // Mux combinacional: entrega directamente la salida registrada de BRAM al completarse la lectura
  assign mem_rdata = ram_read_r ? ram_rdata : mmio_rdata;

  always @(posedge clk) begin
    if (!sys_resetn) begin
      mem_ready  <= 1'b0;
      ram_read_r <= 1'b0;
      mmio_rdata <= 32'h0;
      leds       <= 15'h0;
    end else begin
      // Por defecto desactivados: mem_ready y ram_read_r son pulsos de 1 ciclo
      mem_ready  <= 1'b0;
      ram_read_r <= 1'b0;

      if (mem_valid && !mem_ready) begin
        if (ram_sel) begin
          // La BRAM captura addr/wdata en este flanco; el dato queda válido para la CPU en el ciclo siguiente
          ram_read_r <= !(|mem_wstrb);
          mem_ready  <= 1'b1;
        end else if (leds_sel) begin
          if (|mem_wstrb) leds <= mem_wdata[14:0];
          mmio_rdata <= {17'b0, leds};
          mem_ready  <= 1'b1;
        end else if (uart_div_sel) begin
          mmio_rdata <= uart_div_do;
          mem_ready  <= 1'b1;
        end else if (uart_dat_sel) begin
          // Mantiene en espera a la CPU hasta que termine el envío TX UART anterior
          if (!uart_dat_wait) begin
            mmio_rdata <= uart_dat_do;
            mem_ready  <= 1'b1;
          end
        end
      end
    end
  end

endmodule
