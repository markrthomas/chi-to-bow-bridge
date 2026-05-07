# Synopsys VCS — UVM 1.x (+ntb_opts uvm). Run from this directory:
#   make run
#   make pdf              — all Markdown guides → PDF (requires pandoc + PDF backend)
#   make pdf-readme       — README.md → README.pdf
#   make pdf-quickref     — UVM_QUICKREF.md → UVM_QUICKREF.pdf
#
# Optional: EXTRA_VCSOPTS=...
SIMV      ?= ./simv
UVM_TEST  ?= chi_smoke_test
VCS       ?= vcs

VCS_BASE  ?= -full64 -sverilog -timescale=1ns/1ps -ntb_opts uvm-1.2 +acc+r

# Synopsys structural coverage (line/cond/toggle/branch). Output dir is gitignored.
COV_DIR         ?= ./uvm_cov.vdb
VCS_COV_COMPILE ?= -cm line+cond+tgl+branch -cm_dir $(COV_DIR) -cm_name chi_tb_uvm

PANDOC          ?= pandoc
# Optional extra flags for all PDFs, e.g. -V geometry:margin=1in --toc
PANDOC_PDF_OPTS ?=

MD_README   := README.md
MD_QUICKREF := UVM_QUICKREF.md
PDF_README  := README.pdf
PDF_QUICKREF := UVM_QUICKREF.pdf
PDF_ALL     := $(PDF_README) $(PDF_QUICKREF)

.PHONY: compile run compile-cov run-cov coverage cov-report clean clean-pdf \
	pdf pdf-readme pdf-quickref pdf-all

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

# --- Markdown → PDF (Pandoc), UVM-focused docs ------------------------------
pdf: pdf-all

pdf-all: $(PDF_ALL)

pdf-readme: $(PDF_README)

pdf-quickref: $(PDF_QUICKREF)

$(PDF_README): $(MD_README)
	@command -v $(PANDOC) >/dev/null 2>&1 || (echo "Error: pandoc not found in PATH"; exit 1)
	$(PANDOC) $(PANDOC_PDF_OPTS) "$(MD_README)" -o "$(PDF_README)"

$(PDF_QUICKREF): $(MD_QUICKREF)
	@command -v $(PANDOC) >/dev/null 2>&1 || (echo "Error: pandoc not found in PATH"; exit 1)
	$(PANDOC) $(PANDOC_PDF_OPTS) "$(MD_QUICKREF)" -o "$(PDF_QUICKREF)"

clean-pdf:
	rm -f $(PDF_ALL)

clean: clean-pdf
	rm -rf simv simv.daidir csrc ucli.key vdCovLog DVEfiles urg_report *.log *.vpd $(COV_DIR)
