#include <stdint.h>
#include "../include/uart.h"
#include "../include/utils.h"


#define IF(imm) ({                              \
    register int ret asm("x30");                \
    asm volatile(".insn i 0x2f, 2, %0, %0, %1" \
                 : "+r"(ret)                    \
                 : "i"(imm)                     \
                 : /* x30 已显式管理 */);       \
    ret;                                        \
})

int main()
{
	int val;
	uart_init();
	
	asm volatile("addi x31, x0, 128" : : : "x31");
	asm volatile("add x30, x0, x0" : : : "x30");

	val = IF(0xa);
	// uart_putc(val & 0xff);
	val = IF(0x1a);
	// uart_putc(val & 0xff);
	val = IF(0x3a);
	// uart_putc(val & 0xff);
	val = IF(0x2c);
	// uart_putc(val & 0xff);
	val = IF(0x0);
	// uart_putc(val & 0xff);
	
    return 0;
}
