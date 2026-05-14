riscv soc 挂载

m0-RISCV_ex

m1-RISCV_pc

m2-jtag

m3-uart_debug

m3>m0>m2>m1

req[1:0]='b01:取数计算（高优先级）

req[1:0]='b10:取指令

s0-rom

s1-ram

s2-timer

s3-uart

s4-gpio

s5-spi
