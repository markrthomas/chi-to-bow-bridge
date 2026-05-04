# Synopsys VCS — UVM 1.x (+ntb_opts uvm). Run from this directory:
#   make run
#   make pdf     — README.md → README.pdf (requires pandoc)
#
# Optional: EXTRA_VCSOPTS=...
SIMV      ?= ./simv
UVM_TEST  ?= chi_smoke_test
VCS       ?= vcs

VCS_BASE  ?= -full64 -sverilog -timescale=1ns/1ps -ntb_opts uvm-1.2 +acc+r

# Synopsys structural coverage (line/cond/toggle/branch). Output dir is gitignored.
COV_DIR         ?= ./uvm_cov.vdb
VCS_COV_COMPILE ?= -cm line+cond+tgl+branch -cm_dir $(COV_DIR) -cm_name chi_tb_uvm

MD  := README.md
PDF := README.pdf

.PHONY: compile run compile-cov run-cov coverage cov-report clean clean-pdf pdf

compile:
	$(VCS) $(VCS_BASE) $(EXTRA_VCSOPTS) -f sim.f -o $(SIMV)

run: compile
	$(SIMV) +UVM_TESTNAME=$(UVM_TEST) +UVM_VERBOSITY=UVM_MEDIUM -l sim.log

compile-cov:
	$(VCS) $(VCS_BASE) $(VCS_COV_COMPILE) $(EXTRA_VCSOPTS) -f sim.f -o $(SIMV)

run-cov: compile-cov
	$(SIMV) -cm_dir $(COV_DIR) +UVM_TESTNAME=$(UVM_TEST) +UVM_VERBOSITY=UVM_MEDIUM -l sim.log

coverage: run-cov

cov-report:
	@command -v urg >/dev/null 2>&1 || (echo "error: urg not on PATH (Synopsys URG)"; exit 1)
	urg -dir $(COV_DIR) -format text -report urg_report

pdf: $(PDF)

$(PDF): $(MD)
	@command -v pandoc >/dev/null 2>&1 || (echo "Error: pandoc not found in PATH"; exit 1)
	pandoc "$(MD)" -o "$(PDF)"

clean-pdf:
	rm -f "$(PDF)"

clean: clean-pdf
	rm -rf simv simv.daidir csrc ucli.key vdCovLog DVEfiles urg_report *.log *.vpd $(COV_DIR)
