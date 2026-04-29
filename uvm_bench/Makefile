# Synopsys VCS — UVM 1.x (+ntb_opts uvm). Run from this directory:
#   make run
#   make pdf     — README.md → README.pdf (requires pandoc)
#
# Optional: EXTRA_VCSOPTS=...
SIMV      ?= ./simv
UVM_TEST  ?= chi_smoke_test
VCS       ?= vcs

VCS_BASE  ?= -full64 -sverilog -timescale=1ns/1ps -ntb_opts uvm-1.2 +acc+r

MD  := README.md
PDF := README.pdf

.PHONY: compile run clean clean-pdf pdf

compile:
	$(VCS) $(VCS_BASE) $(EXTRA_VCSOPTS) -f sim.f -o $(SIMV)

run: compile
	$(SIMV) +UVM_TESTNAME=$(UVM_TEST) +UVM_VERBOSITY=UVM_MEDIUM -l sim.log

pdf: $(PDF)

$(PDF): $(MD)
	@command -v pandoc >/dev/null 2>&1 || (echo "Error: pandoc not found in PATH"; exit 1)
	pandoc "$(MD)" -o "$(PDF)"

clean-pdf:
	rm -f "$(PDF)"

clean: clean-pdf
	rm -rf simv simv.daidir csrc ucli.key vdCovLog DVEfiles *.log *.vpd
