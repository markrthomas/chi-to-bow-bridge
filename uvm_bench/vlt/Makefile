# Verilator UVM flow for the CHI-to-BoW integration UVM bench (../ = uvm_bench).
#
# Runs the *same* SystemVerilog UVM env as VCS would, but under open-source
# Verilator (>= 5.050) with the Accellera UVM 2020.3.1 library bundled in the
# Verilator source tree (test_regress/t/uvm).
#
# Quick start (local lint is RAM-safe; the full --binary build belongs in CI):
#   V=~/verilator/bin/verilator ; U=~/verilator/test_regress/t/uvm
#   ( unset VERILATOR_ROOT; make -C uvm_bench/vlt lint  VERILATOR=$V UVM_HOME=$U )
#   ( unset VERILATOR_ROOT; make -C uvm_bench/vlt smoke VERILATOR=$V UVM_HOME=$U )
#
# NOTE: Verilator solves randomize() constraints with an external SMT solver
# (z3/cvc5); ensure z3 is on PATH or constrained randomize() returns 0.

VERILATOR ?= verilator

UVM_HOME ?= $(error Set UVM_HOME to the bundled Verilator UVM dir, e.g. \
  ~/verilator/test_regress/t/uvm)
UVM_HDR := $(UVM_HOME)/uvm_pkg_all_v2020_3_1_dpi.svh
UVM_DPI := $(UVM_HOME)/v2020_3_1/dpi/uvm_dpi.cc

BUILD_JOBS ?= 1
# Default (no explicit UVM_TEST override): constrained-random mixed read/write
# sequence, >= 5 transactions (DV_STANDARDS.md). Override for a directed test,
# e.g. `make smoke UVM_TEST=chi_smoke_test`.
UVM_TEST   ?= chi_random_test

VFLAGS ?= --binary --timing --vpi -j $(BUILD_JOBS) --build-jobs $(BUILD_JOBS) \
          -Wno-fatal -Wno-COVERIGN -Wno-TIMESCALEMOD --CFLAGS -O0
UVM_PLUSARGS ?= +UVM_NO_RELNOTES

VLT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BENCH   := $(abspath $(VLT_DIR)/..)
ROOT    := $(abspath $(VLT_DIR)/../..)
OBJ     := $(VLT_DIR)/obj

INCS := +incdir+$(BENCH)/tb +incdir+$(BENCH)/uvm +incdir+$(VLT_DIR) \
        +incdir+$(UVM_HOME)

# Order matches uvm_bench/sim.f: RTL + BFMs + checker, interface, package, top.
SRCS := $(ROOT)/src/chi_to_bow_bridge.v \
        $(ROOT)/integration/bow_link_partner_bfm.v \
        $(ROOT)/integration/chi_to_bow_integration_top.v \
        $(ROOT)/verification/chi_integration_protocol_chk.sv \
        $(BENCH)/tb/chi_integration_if.sv $(BENCH)/uvm/chi_tb_pkg.sv \
        $(BENCH)/tb/tb_top.sv

define build
	rm -rf $(OBJ)/tb_top
	mkdir -p $(OBJ)/tb_top
	$(VERILATOR) $(VFLAGS) --top-module tb_top --Mdir $(OBJ)/tb_top \
	  $(INCS) $(UVM_HDR) $(UVM_DPI) $(SRCS)
endef
define run
	$(OBJ)/tb_top/Vtb_top $(UVM_PLUSARGS) +UVM_TESTNAME=$(1)
endef

.PHONY: all build smoke lint clean

all: smoke

build:
	$(build)

# The TB top calls run_test() with no default, so the test is chosen here.
smoke: build
	$(call run,$(UVM_TEST))

LINTFLAGS ?= --lint-only --timing -Wno-fatal -Wno-COVERIGN -Wno-TIMESCALEMOD
lint:
	$(VERILATOR) $(LINTFLAGS) --top-module tb_top $(INCS) $(UVM_HDR) $(SRCS)

clean:
	rm -rf $(OBJ)
