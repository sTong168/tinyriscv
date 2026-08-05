# ============================================================
# 4-cpu tinyriscv simulation filelist (VCS)
# run from prj/4cpu/ (the dir that contains rtl/)
# rtl/core/defines.v is the MERGED union of cpu0+cpu1+cpu2+cpu3
# defines (160 macros, no value conflicts) — needed because VCS
# does not resolve `include relative to the source file's dir.
# Regenerate it if any cpu's defines.v changes.
# ============================================================

rtl/core/defines.v

# ---- CPU0 (苏桐, pad/tape-out version) ----
rtl/cpu0/core/tinyriscv.v
rtl/cpu0/core/ctrl.v
rtl/cpu0/core/ex.v
rtl/cpu0/core/id.v
rtl/cpu0/core/id_ex.v
rtl/cpu0/core/if_id.v
rtl/cpu0/core/pc_reg.v
rtl/cpu0/core/regs.v
rtl/cpu0/core/rib.v
rtl/cpu0/core/inst_if_ctrl.v
rtl/cpu0/core/inst_rt_ctrl.v
rtl/cpu0/core/inst_sid_ctrl.v
rtl/cpu0/perips/bridge.v
rtl/cpu0/perips/i2c.v
rtl/cpu0/perips/uart.v
rtl/cpu0/perips/pwm.v
rtl/cpu0/perips/bridge_fpga.v
rtl/cpu0/perips/ram.v
rtl/cpu0/perips/rom.v
rtl/cpu0/debug/uart_debug.v
rtl/cpu0/utils/gen_dff.v
rtl/cpu0/soc/tinyriscv_soc_top_pad.v

# ---- CPU1 (王子阳) ----
rtl/cpu1/soc/tinyriscv_soc_top.v
rtl/cpu1/soc/ext_mem_port.v
rtl/cpu1/soc/mem_bridge_master.v
rtl/cpu1/soc/ifetch_line_buf.v
rtl/cpu1/core/tinyriscv.v
rtl/cpu1/core/ctrl.v
rtl/cpu1/core/ex.v
rtl/cpu1/core/id.v
rtl/cpu1/core/id_ex.v
rtl/cpu1/core/if_id.v
rtl/cpu1/core/pc_reg.v
rtl/cpu1/core/regs.v
rtl/cpu1/core/rib.v
rtl/cpu1/perips/uart.v
rtl/cpu1/perips/i2c.v
rtl/cpu1/perips/pwm.v
rtl/cpu1/perips/lfsr.v
rtl/cpu1/perips/custom_inst.v
rtl/cpu1/debug/uart_debug.v
rtl/cpu1/utils/gen_dff.v
rtl/cpu1/utils/gen_buf.v
rtl/cpu1/utils/full_handshake_tx.v
rtl/cpu1/utils/full_handshake_rx.v

# ---- CPU2 ----
rtl/cpu2/soc/tinyriscv_soc_top.v
rtl/cpu2/core/tinyriscv.v
rtl/cpu2/core/ctrl.v
rtl/cpu2/core/ex.v
rtl/cpu2/core/id.v
rtl/cpu2/core/id_ex.v
rtl/cpu2/core/if_id.v
rtl/cpu2/core/pc_reg.v
rtl/cpu2/core/regs.v
rtl/cpu2/core/rib.v
rtl/cpu2/perips/i2c.v
rtl/cpu2/perips/mem_bridge.v
rtl/cpu2/perips/pwm.v
rtl/cpu2/perips/uart.v
rtl/cpu2/debug/uart_debug.v
rtl/cpu2/utils/gen_dff.v

# ---- CPU3 ----
rtl/cpu3/soc/tinyriscv_soc_top.v
rtl/cpu3/core/tinyriscv.v
rtl/cpu3/core/ctrl.v
rtl/cpu3/core/ex.v
rtl/cpu3/core/id.v
rtl/cpu3/core/id_ex.v
rtl/cpu3/core/if_id.v
rtl/cpu3/core/pc_reg.v
rtl/cpu3/core/regs.v
rtl/cpu3/core/rib.v
rtl/cpu3/core/chip_bridge.v
rtl/cpu3/perips/uart.v
rtl/cpu3/perips/i2c_master.v
rtl/cpu3/perips/pwm.v
rtl/cpu3/perips/sID.v
rtl/cpu3/perips/sendif.v
rtl/cpu3/debug/uart_debug.v
rtl/cpu3/utils/gen_dff.v
rtl/cpu3/utils/gen_buf.v
rtl/cpu3/utils/full_handshake_tx.v
rtl/cpu3/utils/full_handshake_rx.v

# ---- 4-CPU top + IO wrapper (includes tb separately in Makefile) ----
rtl/tinyriscv_4cpu_top.v
rtl/tinyriscv_top_IO.v

# ---- TSMC IO pad library (PDDW0204CDG etc.) ----
/data2/class/chenh/chenh51/Process/TSMC18_Lib_new/lib/IO/Front_End/verilog/tpd018nv_260a/tpd018nv.v
