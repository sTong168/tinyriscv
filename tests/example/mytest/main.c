#include <stdint.h>
#include "../include/pwm.h"
#include "../include/utils.h"


int main()
{
    PWM_REG(PWM_A0) = 0x05;
    PWM_REG(PWM_B0) = 0x03;
    PWM_REG(PWM_A1) = 0x1000;
    PWM_REG(PWM_B1) = 0x100;
    PWM_REG(PWM_C)  = 0x0F;
    return 0;
}
