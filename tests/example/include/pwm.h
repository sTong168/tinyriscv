#ifndef _PWM_H_
#define _PWM_H_

#define PWM_BASE      (0x60000000)
#define PWM_A0        (PWM_BASE + (0x000000))
#define PWM_A1        (PWM_BASE + (0x010000))
#define PWM_A2        (PWM_BASE + (0x020000))
#define PWM_A3        (PWM_BASE + (0x030000))
#define PWM_B0        (PWM_BASE + (0x100000))
#define PWM_B1        (PWM_BASE + (0x110000))
#define PWM_B2        (PWM_BASE + (0x120000))
#define PWM_B3        (PWM_BASE + (0x130000))
#define PWM_C         (PWM_BASE + (0x040000))

#define PWM_REG(addr) (*((volatile uint32_t *)addr))

#endif
