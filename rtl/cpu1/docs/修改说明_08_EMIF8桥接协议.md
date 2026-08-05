# 修改说明 08：EMIF-8 片外存储桥接与创新

## 1. 背景

大作业要求芯片通过 **8 位 IO** 与 FPGA 上的外部 ROM/RAM 通信。FPGA 验收阶段使用 **MEM_BYPASS=1**（32 位直连），与原先行为一致；流片 RTL 使用 **MEM_BYPASS=0** 走 EMIF-8 协议。

参考文献思路：YiFive/Caravel 在 pin 受限时使用 8 位外存接口；Ibex/CV32 使用 prefetch 掩盖外存延迟。

## 2. 新增模块

| 文件 | 作用 |
|------|------|
| `soc/mem_bridge_master.v` | 芯片侧 EMIF-8 主设备 |
| `fpga/mem_bridge_slave.v` | FPGA 侧 EMIF-8 从设备 + chip_sel 地址偏移 |
| `soc/ext_mem_port.v` | BYPASS / 桥接双模式端口 |
| `soc/ifetch_line_buf.v` | 取指单字缓冲（桥接模式） |

## 3. EMIF-8 协议（定稿：纯 16 线 + 带内握手）

PAD：`bridge_o[7:0]`（芯片→FPGA）+ `bridge_i[7:0]`（FPGA→芯片），**无独立 req/ack 脚**。  
假设：**SoC 与 FPGA 外接同源时钟**（允许一定抖动）。空闲输出 `0x00`。

| 阶段 | 方向 | 内容 |
|------|------|------|
| MAGIC | 芯片→FPGA | `0xA5` 帧同步 |
| CMD | 芯片→FPGA | `{6'b0, memsel, we}`（memsel: 0=ROM 1=RAM） |
| ADDR×4 | 芯片→FPGA | 地址，**高字节先** |
| DATA×4 | 芯片→FPGA | 写：真实数据；读：dummy `0x00`（两端锁步进） |
| ACK | FPGA→芯片 | `0x5A`（写：多拍保持；读：1 拍后跟数据） |
| RDATA×4 | FPGA→芯片 | 仅读事务，**高字节先** |

- `chip_sel[1:0]`：FPGA 侧地址 += `{chip_sel, 2'b00}`。
- **ROM 写保护**：向 RAM 字 15 写 `0xDEADBEEF` 后锁定 ROM 写。
- CPU 侧 `busy_o` → `mem_hold`，整笔事务结束前停流水线；**片内不保留 ROM/RAM**。

## 4. 参数与 FPGA 验证

| 参数 | 含义 |
|------|------|
| `MEM_BYPASS=1` | 32 位直连 `ext_mem_fpga`（快速功能验收，见存档 `proj_tinyriscout_archive_bypass_ok`） |
| `MEM_BYPASS=0` | **当前默认**：FPGA 内 EMIF-8 环回（master ↔ slave ↔ ext_mem） |

修改位置：`fpga/fpga_top.v`、`soc/tinyriscv_soc_top.v` 的 `parameter MEM_BYPASS`。  
**无需改 xdc**（`em_dat` 在 FPGA 内部环回，不引出引脚）。

### 4.1 桥模式 FPGA 自测步骤

1. 确认两处 `MEM_BYPASS = 0`，重新综合烧录。
2. RESET → KEY1 进入下载模式。
3. 按顺序测试（比 bypass 慢，属正常）：

```bat
cd sim
python tinyriscv_fw_downloader.py COM13 ..\new\inst_clear.data
python tinyriscv_fw_downloader.py COM13 Baisc_Inst_Example\inst_add.data
python tinyriscv_fw_downloader.py COM13 Extend_Inst_Example\sID\sID_inst.data
```

4. 成功标准与 bypass 相同：F19 亮、`inst_add` 通过、sID 串口输出学号。

### 4.2 协议时序（定稿）

- Slave `S_IDLE` 见到 `0xA5` 开事务。
- Master 写：MAGIC → CMD → ADDR×4 → DATA×4 → 等待 `bridge_i==0x5A` → done。
- Master 读：同上发送（DATA 为 0）→ 等待 `0x5A` → 再采 RDATA×4 → done。
- 输出字节由 **当前状态组合驱动**（与常见同频字节流一致），避免 NBA 错拍。
- 顶层仅 `bridge_o/i`，无 `em_req` / `em_ack`。

## 5. ext_mem_port 桥模式仲裁

| 优先级 | 事务 |
|--------|------|
| 1 | ROM 写（uart_debug 固件下载） |
| 2 | RAM 写 |
| 3 | 取指 miss（`ifetch_line_buf`） |
| 4 | EX 阶段 load（RAM / ROM 读） |

`mem_hold_o` 在桥忙时拉高，暂停流水线直至事务完成。

## 6. 与创新点关系

- **双模式存储接口**：验收 bypass / 流片 bridge
- **取指缓冲**：`ifetch_line_buf` 减少顺序取指 stall
- **ROM 写保护**：固件下载后防误写
- 既有 **POPCOUNT**、**LFSR** 不变
