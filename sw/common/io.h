#pragma once
#include <stdint.h>

#define REG_LEDS        (*(volatile uint32_t *)0x10000000)
#define REG_UART_CLKDIV (*(volatile uint32_t *)0x20000004)
#define REG_UART_DATA   (*(volatile uint32_t *)0x20000008)

static inline void putc(char c) {
    if (c == '\n') REG_UART_DATA = '\r';
    REG_UART_DATA = c;
}

static inline void puts(const char *s) {
    while (*s) putc(*s++);
}

static inline void delay(volatile uint32_t count) {
    while (count--) __asm__ volatile("");
}

static inline uint8_t uart_getc(void) {
    int32_t c;
    while ((c = (int32_t)REG_UART_DATA) == -1);
    return (uint8_t)c;
}
