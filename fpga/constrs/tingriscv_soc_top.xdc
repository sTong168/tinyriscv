# 时钟约束50MHz
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports {clk}]; 
create_clock -add -name sys_clk_pin -period 20.00 -waveform {0 10} [get_ports {clk}];

# 时钟引脚
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN Y18 [get_ports clk]

# 复位引脚
set_property IOSTANDARD LVCMOS33 [get_ports rst]
set_property PACKAGE_PIN F20 [get_ports rst]

# # 程序执行成功指示引脚 LED1 �?=成功，灭=失败
 set_property IOSTANDARD LVCMOS33 [get_ports succ]
 set_property PACKAGE_PIN F19 [get_ports succ]

# # 程序执行结束指示引脚 LED2 �?=结束，灭=未结�?
# set_property IOSTANDARD LVCMOS33 [get_ports over]
# set_property PACKAGE_PIN E21 [get_ports over]

# 串口发�?�引�?
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_pin]
set_property PACKAGE_PIN G16 [get_ports uart_tx_pin]

# 串口接收引脚
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_pin]
set_property PACKAGE_PIN G15 [get_ports uart_rx_pin]

# PWM 引脚
set_property IOSTANDARD LVCMOS33 [get_ports pwm[0]]
set_property PACKAGE_PIN E21 [get_ports pwm[0]]

set_property IOSTANDARD LVCMOS33 [get_ports pwm[1]]
set_property PACKAGE_PIN D20 [get_ports pwm[1]]

set_property IOSTANDARD LVCMOS33 [get_ports pwm[2]]
set_property PACKAGE_PIN C20 [get_ports pwm[2]]

#set_property IOSTANDARD LVCMOS33 [get_ports pwm[3]]
#set_property PACKAGE_PIN C20 [get_ports pwm[3]]

# GPIO引脚
# set_property IOSTANDARD LVCMOS33 [get_ports {gpio_out[*]}]
# set_property PACKAGE_PIN J5 [get_ports {gpio_out[0]}]
# set_property PACKAGE_PIN M3 [get_ports {gpio_out[1]}]
# set_property PACKAGE_PIN J6 [get_ports {gpio_out[2]}]
# set_property PACKAGE_PIN H5 [get_ports {gpio_out[3]}]
# set_property PACKAGE_PIN G4 [get_ports {gpio_out[4]}]
# set_property PACKAGE_PIN K6 [get_ports {gpio_out[5]}]
# set_property PACKAGE_PIN K3 [get_ports {gpio_out[6]}]
# set_property PACKAGE_PIN H4 [get_ports {gpio_out[7]}]
# set_property PACKAGE_PIN M2 [get_ports {gpio_out[8]}]
# set_property PACKAGE_PIN N4 [get_ports {gpio_out[9]}]
# set_property PACKAGE_PIN L5 [get_ports {gpio_out[10]}]
# set_property PACKAGE_PIN L4 [get_ports {gpio_out[11]}]
# set_property PACKAGE_PIN M16 [get_ports {gpio_out[12]}]
# set_property PACKAGE_PIN M17 [get_ports {gpio_out[13]}]
# set_property PACKAGE_PIN B20 [get_ports {gpio_out[14]}]
# set_property PACKAGE_PIN D17 [get_ports {gpio_out[15]}]

# I2C 引脚
set_property IOSTANDARD LVCMOS33 [get_ports scl]
set_property PULLUP true [get_ports scl]
set_property PACKAGE_PIN M22 [get_ports scl]

set_property IOSTANDARD LVCMOS33 [get_ports sda]
set_property PULLUP true [get_ports sda]
set_property PACKAGE_PIN N22 [get_ports sda]

# Debug 引脚
set_property IOSTANDARD LVCMOS33 [get_ports uart_debug_pin]
set_property PACKAGE_PIN M13 [get_ports uart_debug_pin]

# # JTAG TCK引脚
# set_property IOSTANDARD LVCMOS33 [get_ports jtag_TCK]
# set_property PACKAGE_PIN V12 [get_ports jtag_TCK]

# #create_clock -name jtag_clk_pin -period 300 [get_ports {jtag_TCK}];

# # JTAG TMS引脚
# set_property IOSTANDARD LVCMOS33 [get_ports jtag_TMS]
# set_property PACKAGE_PIN T13 [get_ports jtag_TMS]

# # JTAG TDI引脚
# set_property IOSTANDARD LVCMOS33 [get_ports jtag_TDI]
# set_property PACKAGE_PIN R13 [get_ports jtag_TDI]

# # JTAG TDO引脚
# set_property IOSTANDARD LVCMOS33 [get_ports jtag_TDO]
# set_property PACKAGE_PIN U13 [get_ports jtag_TDO]