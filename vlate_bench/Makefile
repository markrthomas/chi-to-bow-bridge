# Verilator TB — parallel to uvm_bench (C++ driver/mon/scoreboard).
# From vlate_bench:  make lint — verilator --lint-only on sim.f (CI)
#                     make run  — simulation (no RTL coverage instrumentation)
#                     make coverage — rebuild with --coverage, run TB, emit lcov .info (OSS plan)
#                     make pdf  — README.md → README.pdf (requires pandoc)

VERILATOR ?= verilator
VERILATOR_COVERAGE ?= verilator_coverage

OBJ_DIR    = obj_dir
SIM        = $(OBJ_DIR)/Vtb_top

OBJ_DIR_COV ?= obj_dir_cov
SIM_COV     = $(OBJ_DIR_COV)/Vtb_top

COV_DAT  ?= $(CURDIR)/vlate_coverage.dat
COV_INFO ?= $(CURDIR)/vlate_coverage.info

RTL        = ../src/chi_to_bow_bridge.v ../integration/bow_link_partner_bfm.v ../integration/chi_to_bow_integration_top.v

VFLAGS     = -Wall -Wno-fatal \
	-cc --exe --build -j 0 \
	--top-module tb_top \
	--timescale 1ns/1ps \
	-Mdir $(OBJ_DIR)

VFLAGS_COV = -Wall -Wno-fatal \
	-cc --exe --build -j 0 \
	--coverage \
	--top-module tb_top \
	--timescale 1ns/1ps \
	-Mdir $(OBJ_DIR_COV)

MD  := README.md
PDF := README.pdf

.PHONY: run lint clean clean-pdf pdf coverage coverage-info

# OSS lint-only gate (CI): RTL + tb_top shell, no C++ link.
lint:
	$(VERILATOR) --lint-only -Wall -Wno-fatal -f sim.f

$(SIM): tb_main.cpp tb_top.sv $(RTL) sim.f
	$(VERILATOR) $(VFLAGS) \
		-o Vtb_top tb_main.cpp -f sim.f
	@if [ -f "$(SIM)" ]; then :; elif [ -f "$(OBJ_DIR)/Vtb_top" ]; then :; else ls -la $(OBJ_DIR); exit 1; fi

$(SIM_COV): tb_main.cpp tb_top.sv $(RTL) sim.f
	$(VERILATOR) $(VFLAGS_COV) \
		-o Vtb_top tb_main.cpp -f sim.f
	@if [ -f "$(SIM_COV)" ]; then :; elif [ -f "$(OBJ_DIR_COV)/Vtb_top" ]; then :; else ls -la $(OBJ_DIR_COV); exit 1; fi

run: $(SIM)
	$(SIM)

# OSS structural coverage per docs/PLAN.md: Verilator instrumentation + merged .info for downstream tools.
coverage: $(SIM_COV)
	@rm -f "$(COV_DAT)" "$(COV_INFO)"
	VL_COV_FILENAME="$(COV_DAT)" "$(SIM_COV)"
	@if [ ! -f "$(COV_DAT)" ]; then echo "ERROR: $(COV_DAT) not produced"; exit 1; fi
	$(VERILATOR_COVERAGE) -write-info "$(COV_INFO)" "$(COV_DAT)"
	@echo "Wrote $(COV_INFO) (inputs: $(COV_DAT))"
	@test -s "$(COV_INFO)" || (echo ERROR: empty $(COV_INFO); exit 1)

pdf: $(PDF)

$(PDF): $(MD)
	@command -v pandoc >/dev/null 2>&1 || (echo "Error: pandoc not found in PATH"; exit 1)
	pandoc "$(MD)" -o "$(PDF)"

clean-pdf:
	rm -f "$(PDF)"

clean: clean-pdf
	rm -rf $(OBJ_DIR) $(OBJ_DIR_COV) *.log *.vcd
	rm -f "$(COV_DAT)" "$(COV_INFO)"
