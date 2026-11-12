SECTIONS {
    . = ORG;            /* 0x0 para imagen base en BRAM, 0x800 para app cargada por UART */
    .memory : {
        *(.init);
        *(.text);
        *(*);
        . = ALIGN(4);
        end = .;
    }
}
