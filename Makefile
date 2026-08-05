# Makefile for 4-cpu tinyriscv simulation (VCS + Verdi)
# run from prj/4cpu/ (the dir that contains rtl/)

VCS      = vcs
VERDI    = verdi
VCS_FLAGS = -full64             -top riscv_soc_IO_tb             +v2k             -debug_access+all             +incdir+rtl/core             +incdir+rtl             -timescale=1ns/1ps             -f run.f             rtl/tinyriscv_soc_IO_tb.v

.PHONY: all cpl sim verdi clean

all: cpl sim

cpl:
	$(VCS) $(VCS_FLAGS) -l vcs.log -o simv

sim:
	./simv -l sim.log

verdi:
	$(VERDI) -full64 -top riscv_soc_IO_tb +incdir+rtl/core +incdir+rtl -f run.f rtl/tinyriscv_soc_IO_tb.v -ssf tb.fsdb

clean:
	rm -rf simv simv.daidir csrc ucli.key
	rm -rf vcs*.log sim*.log
	rm -rf tb.fsdb*
	rm -rf verdiLog vfastLog novas.conf novas.rc novas.log novas_dump.log
	rm -rf DVEfiles inter.vpd
