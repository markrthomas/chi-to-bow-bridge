TOPLEVEL_LANG = verilog
SIM ?= icarus

VERILOG_SOURCES = $(PWD)/../src/chi_to_bow_bridge.v
TOPLEVEL = chi_to_bow_bridge
MODULE = test_chi_to_bow_bridge
WAVE_FST = sim_build/$(TOPLEVEL).fst
WAVE_VCD = sim_build/$(TOPLEVEL).vcd
# make waves/gtkwave dump a single, focused test by default (a full multi-test
# regression trace is hard to read). Default is the randomized mixed
# read/write test (10 transactions); override with WAVE_TESTCASE=<name>.
WAVE_TESTCASE ?= test_interleaved_mixed_read_write_responses
WAVE_GTKW = chi_to_bow_bridge.gtkw
WAVE_ZOOM = zoom_full.tcl
# The waveform flow is a random run: a fresh TEST_SEED every time unless SEED=<n>
# is given (the seed is printed so a run can be replayed). Plain `make` keeps
# each test's fixed default seed.
WAVE_SEED := $(or $(SEED),$(shell echo $$(( $$(od -An -N4 -tu4 /dev/urandom) % 2147483646 + 1 ))))

.PHONY: waves gtkwave wave

ICARUS_BIN_DIR ?= /usr/bin
SIM_CMD_PREFIX := env -u VIRTUAL_ENV -u PYTHONHOME
export PYTHONPATH := $(PWD):$(PWD)/..:$(PYTHONPATH)
# Match the interpreter that provides cocotb (falls back for minimal environments)
export PYGPI_PYTHON_BIN := $(or $(shell command -v python3 2>/dev/null),/usr/bin/python3)

include $(shell cocotb-config --makefiles)/Makefile.sim

waves:
	$(MAKE) clean
	@echo "[WAVE] $(WAVE_TESTCASE) with random seed: SEED=$(WAVE_SEED)"
	TEST_SEED=$(WAVE_SEED) $(MAKE) WAVES=1 TESTCASE=$(WAVE_TESTCASE)
	@if command -v fst2vcd >/dev/null 2>&1; then \
		fst2vcd "$(WAVE_FST)" > "$(WAVE_VCD)"; \
		echo "Generated VCD: $(WAVE_VCD)"; \
	else \
		echo "fst2vcd not found; generated FST only: $(WAVE_FST)"; \
		echo "Install gtkwave package to enable FST->VCD conversion."; \
	fi

# Dumps WAVE_TESTCASE (default: the randomized mixed read/write test, fresh
# seed) and opens it in GTKWave with the curated signal grouping in WAVE_GTKW,
# zoomed to fit (WAVE_ZOOM). No gtkwave on PATH is a clean skip after the dump.
gtkwave wave: waves
	@if command -v gtkwave >/dev/null 2>&1; then \
		if [ -f "$(WAVE_VCD)" ]; then f="$(WAVE_VCD)"; else f="$(WAVE_FST)"; fi; \
		echo "[WAVE] opening $$f with $(WAVE_GTKW)"; \
		gtkwave -S "$(WAVE_ZOOM)" "$$f" -a "$(WAVE_GTKW)"; \
	else \
		echo "[WAVE] gtkwave not on PATH — dump is at $(WAVE_FST) (layout: $(WAVE_GTKW))"; \
	fi
