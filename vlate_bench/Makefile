# Verilator TB — parallel to uvm_bench (C++ driver/mon/scoreboard).
# From vlate_bench:  make run
#                     make pdf  — README.md → README.pdf (requires pandoc)

VERILATOR ?= verilator
OBJ_DIR    = obj_dir
SIM        = $(OBJ_DIR)/Vtb_top

RTL        = ../src/chi_to_bow_bridge.v ../integration/bow_link_partner_bfm.v ../integration/chi_to_bow_integration_top.v

VFLAGS     = -Wall -Wno-fatal \
	-cc --exe --build -j 0 \
	--top-module tb_top \
	--timescale 1ns/1ps \
	-Mdir $(OBJ_DIR)

MD  := README.md
PDF := README.pdf

.PHONY: run clean clean-pdf pdf

$(SIM): tb_main.cpp tb_top.sv $(RTL) sim.f
	$(VERILATOR) $(VFLAGS) \
		-o Vtb_top tb_main.cpp -f sim.f
	@if [ -f "$(SIM)" ]; then :; elif [ -f "$(OBJ_DIR)/Vtb_top" ]; then :; else ls -la $(OBJ_DIR); exit 1; fi

run: $(SIM)
	$(SIM)

pdf: $(PDF)

$(PDF): $(MD)
	@command -v pandoc >/dev/null 2>&1 || (echo "Error: pandoc not found in PATH"; exit 1)
	pandoc "$(MD)" -o "$(PDF)"

clean-pdf:
	rm -f "$(PDF)"

clean: clean-pdf
	rm -rf $(OBJ_DIR) *.log *.vcd
