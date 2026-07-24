# tinyriscv RTL 文件说明

## 目录结构

```
rtl/
├── core/          # CPU 核心模块
├── perips/        # 外设模块
├── soc/           # SoC 顶层模块
├── debug/         # 调试模块
├── utils/         # 通用工具模块
└── tinyriscv_top_IO.v  # 芯片顶层（含 IO PAD）
```

---

## core/ — CPU 核心模块

| 文件 | 说明 |
|------|------|
| `defines.v` | 全局参数与宏定义（位宽、地址空间、指令编码等） |
| `ctrl.v` | 流水线控制模块，生成各阶段停顿/跳转信号 |
| `pc_reg.v` | PC 寄存器，控制取指地址 |
| `if_id.v` | IF/ID 流水线寄存器 |
| `id.v` | 译码模块，解析指令并生成控制信号 |
| `id_ex.v` | ID/EX 流水线寄存器 |
| `ex.v` | 执行模块，完成 ALU 运算及访存控制 |
| `regs.v` | 32 个通用寄存器堆 |
| `rib.v` | RIB 内部总线，仲裁取指与执行阶段的总线访问 |
| `tinyriscv.v` | CPU 核顶层模块，例化上述所有核心子模块 |
| `inst_if_ctrl.v` | 自定义扩展指令 IF 的控制模块（UART 单字节发送） |
| `inst_rt_ctrl.v` | 自定义扩展指令 rT 的控制模块（I2C 读写） |
| `inst_sid_ctrl.v` | 自定义扩展指令 sID 的控制模块（UART 发送学号） |
| `clint.v` | ⚠️ 已弃用 — Core Local Interruptor，核心局部中断控制器 |
| `csr_reg.v` | ⚠️ 已弃用 — CSR 寄存器模块 |
| `div.v` | ⚠️ 已弃用 — 硬件除法模块 |

## perips/ — 外设模块

| 文件 | 说明 |
|------|------|
| `bridge.v` | 总线桥接模块，将 RIB 总线请求分发到各外设地址空间 |
| `bridge_fpga.v` | FPGA 验证用桥接模块，通过单根双向线与 bridge 通信，内含 ROM/RAM |
| `ram.v` | 数据 RAM（256×32bit） |
| `rom.v` | 指令 ROM（256×32bit） |
| `uart.v` | UART 串口收发模块（8-bit 数据，可配置波特率） |
| `i2c.v` | I2C 主机控制器（轮询模式，支持 START/STOP/ACK 序列） |
| `pwm.v` | PWM 输出模块（4 通道，可配置周期与占空比） |
| `uart_debug.v` | 串口下载调试模块，通过 UART 接收数据写入 RAM |
| `bridge_5c.v` | ⚠️ 已弃用 — bridge 的 5 周期取指版本 |
| `bridge_pad.v` | 流片用 bridge，端口改为带 `_in`/`_o`/`_oe` 的三态风格，适配 IO PAD |
| `i2c_pad.v` | 流片用 I2C，端口改为带 `_in`/`_o`/`_oe` 的三态风格，适配 IO PAD |
| `i2c_v2.v` | ⚠️ 已弃用 — I2C v2 版本（4-phase SCL 状态机，直接读模式） |
| `i2c_modified.v` | ⚠️ 已弃用 — I2C 的早期修改版本 |
| `gpio.v` | ⚠️ 已弃用 — GPIO 通用输入输出模块 |
| `spi.v` | ⚠️ 已弃用 — SPI 主机模块 |
| `timer.v` | ⚠️ 已弃用 — 32 位定时器模块 |

## soc/ — SoC 顶层模块

| 文件 | 说明 |
|------|------|
| `tinyriscv_soc_top.v` | SoC 顶层，例化 CPU 核 + 所有外设（仿真/FPGA 用） |
| `tinyriscv_soc_top_pad.v` | 流片用 SoC 顶层，使用 `bridge_pad` 和 `i2c_pad`，端口适配 IO PAD |
| `tinyriscv_bridge_soc_top.v` | 联合顶层，例化 `tinyriscv_soc_top` + `bridge_fpga`（FPGA 验证用） |

## debug/ — 调试模块

| 文件 | 说明 |
|------|------|
| `uart_debug.v` | UART 调试模块，通过串口下载固件到 RAM |
| `jtag_driver.v` | ⚠️ 已弃用 — JTAG TAP 驱动模块 |
| `jtag_dm.v` | ⚠️ 已弃用 — JTAG Debug Module |
| `jtag_top.v` | ⚠️ 已弃用 — JTAG 顶层模块 |

## utils/ — 通用工具模块

| 文件 | 说明 |
|------|------|
| `gen_buf.v` | 通用缓冲器（BUF） |
| `gen_dff.v` | 通用 D 触发器（DFF） |
| `full_handshake_rx.v` | 全握手协议接收端 |
| `full_handshake_tx.v` | 全握手协议发送端 |

## rtl/ 根目录

| 文件 | 说明 |
|------|------|
| `tinyriscv_top_IO.v` | 芯片顶层模块，例化 `tinyriscv_soc_top_pad` + 所有 IO PAD，为最终流片网表入口 |

---

## 仿真 vs 流片文件清单

### 仿真

仿真通过 `sim/compile_rtl.py` 编译，使用 `iverilog` + `vvp`。

**RTL 文件（由 `compile_rtl.py` 指定）：**

```
rtl/core/defines.v
rtl/core/ctrl.v
rtl/core/ex.v
rtl/core/id.v
rtl/core/id_ex.v
rtl/core/if_id.v
rtl/core/pc_reg.v
rtl/core/regs.v
rtl/core/rib.v
rtl/core/tinyriscv.v
rtl/core/inst_if_ctrl.v
rtl/core/inst_rt_ctrl.v
rtl/core/inst_sid_ctrl.v
rtl/perips/bridge.v
rtl/perips/bridge_fpga.v
rtl/perips/ram.v
rtl/perips/rom.v
rtl/perips/uart.v
rtl/perips/i2c.v
rtl/perips/pwm.v
rtl/debug/uart_debug.v
rtl/soc/tinyriscv_soc_top.v
rtl/utils/gen_buf.v
rtl/utils/gen_dff.v
```

**对应 Testbench：**

| Testbench | 用途 | 说明 |
|-----------|------|------|
| `tb/tinyriscv_soc_tb.v` | C 语言程序仿真 | 例化 `tinyriscv_soc_top` + `bridge_fpga`，通过 x26/x27 判断 PASS/FAIL |
| `tb/compliance_test/tinyriscv_soc_tb.v` | 指令兼容性测试 | 例化 `tinyriscv_soc_top` + `bridge_fpga`，支持 signature 校验 |

**运行命令（以 simple 程序为例）：**

```bash
cd sim
python ../tools/BinToMem_CLI.py ../tests/example/simple/simple.bin inst.data
python compile_rtl.py ..
vvp out.vvp
```

### 流片（Tape-out）

流片使用带 IO PAD 的版本，顶层入口为 `tinyriscv_top_IO`。

**RTL 文件：**

```
rtl/core/defines.v
rtl/core/ctrl.v
rtl/core/ex.v
rtl/core/id.v
rtl/core/id_ex.v
rtl/core/if_id.v
rtl/core/pc_reg.v
rtl/core/regs.v
rtl/core/rib.v
rtl/core/tinyriscv.v
rtl/core/inst_if_ctrl.v
rtl/core/inst_rt_ctrl.v
rtl/core/inst_sid_ctrl.v
rtl/perips/bridge_pad.v          # 替换 bridge.v
rtl/perips/i2c_pad.v             # 替换 i2c.v
rtl/perips/ram.v
rtl/perips/rom.v
rtl/perips/uart.v
rtl/perips/pwm.v
rtl/debug/uart_debug.v
rtl/soc/tinyriscv_soc_top_pad.v # 替换 tinyriscv_soc_top.v
rtl/utils/gen_buf.v
rtl/utils/gen_dff.v
rtl/tinyriscv_top_IO.v           # 最终顶层入口
```

**对应 Testbench：**

| Testbench | 用途 | 说明 |
|-----------|------|------|
| `tb/compliance_test/tinyriscv_soc_IO_tb.v` | IO 版本仿真 | 例化 `tinyriscv_top_IO` + `bridge_fpga`，用于流片前带 PAD 的仿真验证 |
