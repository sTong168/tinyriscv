#include <stdint.h>
#include "../include/i2c.h"
#include "../include/uart.h"
#include "../include/utils.h"


int main()
{
    uart_init();
    unsigned int data = 0;

    I2C_REG(I2C_ADDR) = 0x90;
    I2C_REG(I2C_SEND) = 0x00;

    while((data>>30) != 2) {
        data = I2C_REG(I2C_RECV);
        uart_putc(data & 0xFF);
        uart_putc((data >> 8) & 0xFF);
        uart_putc((data >> 16) & 0xFF);
        uart_putc((data >> 24) & 0xFF);
    }

    // uart_putc(data & 0xFF);
    // uart_putc((data >> 8) & 0xFF);
    return 0;
}
