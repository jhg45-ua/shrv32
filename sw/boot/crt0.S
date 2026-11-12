.section .init
.global main

/* Inicializar el puntero de pila (SP) al final de la BRAM de 16 KB */
lui sp, %hi(16*1024)
addi sp, sp, %lo(16*1024)

/* Saltar a la función principal en C */
jal ra, main

/* Bucle infinito de seguridad si main retorna */
1: j 1b
