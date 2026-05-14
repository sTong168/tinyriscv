#include <stdint.h>
#include "../include/i2c.h"
#include "../include/utils.h"


int main()
{
    unsigned int data = 0;

    I2C_REG(I2C_ADDR) = 0xA5;
    I2C_REG(I2C_SEND) = 0xE3;

    while((data&0xC0000000) != 0xC0000000) {
        data = I2C_REG(I2C_RECV);
    }
    return 0;
}
