// =============================================================================
// Proyecto:     SHRV32 (Space-Hardened RISC-V 32)
// Módulo:       tb_soc.v
// Descripción:  Banco de pruebas del SoC base (arranque, UART TX, LEDs y trap)
// Reloj/Reset:  clk simulado a 100 MHz | resetn activo bajo
// =============================================================================

`timescale 1ns / 1ps

module tb_soc;

  reg clk = 1'b1;
  always #5 clk = ~clk;  // Reloj de 100 MHz (período de 10 ns)

  reg         resetn = 1'b0;

  wire        trap;
  wire [14:0] leds;
  wire        ser_tx;
  reg         ser_rx = 1'b1;  // Nivel en reposo de UART es alto

  soc uut (
      .clk   (clk),
      .resetn(resetn),
      .trap  (trap),
      .leds  (leds),
      .ser_tx(ser_tx),
      .ser_rx(ser_rx)
  );

  initial begin
    $dumpfile("build/dump.vcd");
    $dumpvars(0, tb_soc);
    repeat (10) @(posedge clk);
    resetn <= 1'b1;
  end

  // Decodificador UART RX virtual (115200 baudios @ 100 MHz -> 868 ciclos/bit)
  localparam integer BIT_CYCLES = 868;
  localparam integer HALF_BIT = 434;
  reg [7:0] uart_buf;

  always begin
    wait (uut.sys_resetn === 1'b1);
    @(negedge ser_tx);
    repeat (HALF_BIT) @(posedge clk);

    repeat (8) begin
      repeat (BIT_CYCLES) @(posedge clk);
      uart_buf = {ser_tx, uart_buf[7:1]};
    end

    repeat (BIT_CYCLES) @(posedge clk);
    $write("%c", uart_buf);
    $fflush;
  end

  // Monitor de cambios en el registro de LEDs tras liberar el reset interno
  always @(leds) begin
    if (uut.sys_resetn === 1'b1) begin
      $display("[%0t ns] LEDs = 15'b%015b (0x%04h)", $time, leds, leds);
    end
  end

  // Aborta inmediatamente si la CPU entra en estado trap
  always @(posedge clk) begin
    if (uut.sys_resetn && trap) begin
      $display("\n[SIM ERROR] La CPU activó TRAP en %0t ns", $time);
      $finish;
    end
  end

  // Límite de seguridad (30 ms @ 100 MHz)
  initial begin
    repeat (3000000) @(posedge clk);
    $display("\n[SIM FIN] Timeout alcanzado limpiamente sin trap.");
    $finish;
  end

endmodule
