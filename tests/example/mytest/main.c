#include <stdint.h>
#include "../include/pwm.h"
#include "../include/utils.h"


int main()
{
    PWM_REG(PWM_A0) = 0x05;
    PWM_REG(PWM_B0) = 0x03;
    PWM_REG(PWM_A2) = 0x100;
    PWM_REG(PWM_B2) = 0x80;
    PWM_REG(PWM_C)  = 0x0F;
    return 0;
}
