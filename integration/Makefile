# Cocotb integration test (DUT: chi_to_bow_integration_top)
TOPLEVEL_LANG = verilog
SIM ?= icarus

VERILOG_SOURCES = $(PWD)/../src/chi_to_bow_bridge.v \
	$(PWD)/bow_link_partner_bfm.v \
	$(PWD)/chi_to_bow_integration_top.v
TOPLEVEL = chi_to_bow_integration_top
MODULE = test_integration

ICARUS_BIN_DIR ?= /usr/bin
SIM_CMD_PREFIX := env -u VIRTUAL_ENV -u PYTHONHOME
export PYTHONPATH := $(PWD):$(PWD)/..:$(PYTHONPATH)
export PYGPI_PYTHON_BIN := $(or $(shell command -v python3 2>/dev/null),/usr/bin/python3)

include $(shell cocotb-config --makefiles)/Makefile.sim
