TOPLEVEL_LANG = verilog
SIM ?= icarus

VERILOG_SOURCES = $(PWD)/../src/chi_to_bow_bridge.v
TOPLEVEL = chi_to_bow_bridge
MODULE = test_chi_to_bow_bridge

ICARUS_BIN_DIR ?= /usr/bin
SIM_CMD_PREFIX := env -u VIRTUAL_ENV -u PYTHONHOME
export PYTHONPATH := $(PWD):$(PWD)/..:$(PYTHONPATH)
export PYGPI_PYTHON_BIN := /usr/bin/python3

include $(shell cocotb-config --makefiles)/Makefile.sim
