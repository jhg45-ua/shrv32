// =============================================================================
// Proyecto:     SHRV32 (Space-Hardened RISC-V 32)
// Módulo:       bram_sp.v
// Descripción:  Memoria BRAM single-port síncrona de 16 KB (4096x32b) con wstrb
// Reloj/Reset:  clk (flanco de subida) | sin reset en la matriz de memoria
// =============================================================================

module bram_sp #(
    parameter integer WORDS     = 4096,
    parameter integer ADDR_BITS = 12,
    parameter         INIT_FILE = "build/firmware.hex"
) (
    input                      clk,    // Reloj del sistema (flanco de subida)
    input                      en,     // Habilitación de acceso (activo alto)
    input      [          3:0] wstrb,  // Máscara de escritura por byte (4'b0000 = lectura)
    input      [ADDR_BITS-1:0] addr,   // Dirección de palabra (log2(WORDS) bits)
    input      [         31:0] wdata,  // Dato de escritura (32 bits)
    output reg [         31:0] rdata   // Dato de lectura registrado (latencia de 1 ciclo)
);

  // Matriz de memoria unificada de 16 KB (4096 palabras de 32 bits)
  reg [31:0] mem[0:WORDS-1];

  // Precarga la imagen de firmware tanto en simulación como en el bitstream de FPGA
  // En modo proyecto de Vivado (synth_1/sim_1), los ficheros añadidos se buscan por nombre base
  initial begin
`ifdef SYNTHESIS
    $readmemh("firmware.hex", mem);
`elsif VIVADO_MEM_INIT
    $readmemh("firmware.hex", mem);
`else
    $readmemh(INIT_FILE, mem);
`endif
  end

  // Lectura/escritura síncrona: patrón obligatorio para inferir BRAM física (y no LUTRAM)
  always @(posedge clk) begin
    if (en) begin
      // Escritura selectiva por byte para instrucciones RV32I sb/sh/sw
      if (wstrb[0]) mem[addr][7:0] <= wdata[7:0];
      if (wstrb[1]) mem[addr][15:8] <= wdata[15:8];
      if (wstrb[2]) mem[addr][23:16] <= wdata[23:16];
      if (wstrb[3]) mem[addr][31:24] <= wdata[31:24];
      // Salida registrada: el dato leído queda válido tras el siguiente flanco de subida
      rdata <= mem[addr];
    end
  end
endmodule
