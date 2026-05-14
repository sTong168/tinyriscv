#ifndef _I2C_H_
#define _I2C_H_

#define I2C_BASE      (0x70000000)
#define I2C_ADDR      (I2C_BASE + (0x010000))
#define I2C_SEND      (I2C_BASE + (0x020000))
#define I2C_RECV      (I2C_BASE + (0x030000))

#define I2C_REG(addr) (*((volatile uint32_t *)addr))

#endif
