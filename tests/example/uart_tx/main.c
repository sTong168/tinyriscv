#include <stdint.h>

#include "../include/uart.h"
#include "../include/xprintf.h"



int main()
{
    uart_init();

    xputs("hello world\n");
    // xprintf("hello world\n");

    // while (1);
}
