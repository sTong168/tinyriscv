import sys
import filecmp
import subprocess
import sys
import os


# 主函数
def main():
    rtl_dir = sys.argv[1]

    if rtl_dir != r'..':
        tb_file = r'/tb/compliance_test/tinyriscv_soc_tb.v'
    else:
        tb_file = r'/tb/tinyriscv_soc_tb.v'

    # iverilog 程序
    iverilog_cmd = ['iverilog']
    # 顶层模块
    iverilog_cmd += ['-o', r'out.vvp']
    # 头文件 (defines.v) 路径
    iverilog_cmd += ['-I', rtl_dir + r'/rtl/core']
    # 宏定义，仿真输出文件
    iverilog_cmd += ['-D', r'OUTPUT="signature.output"']
    # ../rtl/core
    iverilog_cmd.append(rtl_dir + r'/rtl/core/ctrl.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/core/defines.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/core/ex.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/core/id.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/core/id_ex.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/core/if_id.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/core/pc_reg.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/core/regs.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/core/rib.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/core/tinyriscv.v')
    # ../rtl/perips
    iverilog_cmd.append(rtl_dir + r'/rtl/perips/bridge.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/perips/bridge_fpga.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/perips/ram.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/perips/rom.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/perips/uart.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/perips/i2c.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/perips/pwm.v')
    # ../rtl/core
    iverilog_cmd.append(rtl_dir + r'/rtl/core/inst_if_ctrl.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/core/inst_rt_ctrl.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/core/inst_sid_ctrl.v')
    # ../rtl/debug
    iverilog_cmd.append(rtl_dir + r'/rtl/debug/uart_debug.v')
    # ../rtl/soc
    iverilog_cmd.append(rtl_dir + r'/rtl/soc/tinyriscv_soc_top.v')
    # ../rtl/utils
    iverilog_cmd.append(rtl_dir + r'/rtl/utils/gen_buf.v')
    iverilog_cmd.append(rtl_dir + r'/rtl/utils/gen_dff.v')
    # testbench 文件（放在最后）
    iverilog_cmd.append(rtl_dir + tb_file)

    # 编译
    process = subprocess.Popen(iverilog_cmd)
    process.wait(timeout=5)

if __name__ == '__main__':
    sys.exit(main())