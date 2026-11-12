#include "../../common/io.h"

#ifdef SIM_FAST
#define HEARTBEAT_DELAY 50
#else
#define HEARTBEAT_DELAY 250000
#endif

void main(void) {
    // 100 MHz / 115200 baudios = 868
    REG_UART_CLKDIV = 868;
    puts("\r\n");
    puts("==================================================\r\n");
    puts("  SHRV32 (PicoRV32) en Digilent Nexys A7-100T     \r\n");
    puts("==================================================\r\n");
    puts("CPU iniciada correctamente. Contador en LEDs...\r\n\r\n");

    uint32_t counter = 0;
    while (1) {
        REG_LEDS = counter & 0x7FFF;

        if ((counter & 0x0F) == 0) {
            puts("[SHRV32 Latido] Contador = ");
            char hex_char = "0123456789ABCDEF"[(counter >> 4) & 0x0F];
            putc(hex_char);
            puts("\r\n");
        }

        counter++;
        delay(HEARTBEAT_DELAY);
    }
}
