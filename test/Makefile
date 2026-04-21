TOPLEVEL_LANG = verilog
SIM ?= icarus

VERILOG_SOURCES = $(PWD)/../src/chi_to_bow_bridge.v
TOPLEVEL = chi_to_bow_bridge
MODULE = test_chi_to_bow_bridge
WAVE_FST = sim_build/$(TOPLEVEL).fst
WAVE_VCD = sim_build/$(TOPLEVEL).vcd

.PHONY: waves gtkwave

ICARUS_BIN_DIR ?= /usr/bin
SIM_CMD_PREFIX := env -u VIRTUAL_ENV -u PYTHONHOME
export PYTHONPATH := $(PWD):$(PWD)/..:$(PYTHONPATH)
export PYGPI_PYTHON_BIN := /usr/bin/python3

include $(shell cocotb-config --makefiles)/Makefile.sim

waves:
	$(MAKE) clean
	$(MAKE) WAVES=1
	@if command -v fst2vcd >/dev/null 2>&1; then \
		fst2vcd "$(WAVE_FST)" > "$(WAVE_VCD)"; \
		echo "Generated VCD: $(WAVE_VCD)"; \
	else \
		echo "fst2vcd not found; generated FST only: $(WAVE_FST)"; \
		echo "Install gtkwave package to enable FST->VCD conversion."; \
	fi

gtkwave: waves
	@if command -v gtkwave >/dev/null 2>&1; then \
		if [ -f "$(WAVE_VCD)" ]; then \
			gtkwave "$(WAVE_VCD)"; \
		else \
			gtkwave "$(WAVE_FST)"; \
		fi; \
	else \
		echo "gtkwave not found. Install GTKWave and run this target again."; \
		exit 1; \
	fi
