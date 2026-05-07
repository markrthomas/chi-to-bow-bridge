.PHONY: all test integration-test docs uvm-pdf clean doctor waves gtkwave oss-regress oss-regress-coverage

all: test integration-test docs

test:
	$(MAKE) -C test clean
	$(MAKE) -C test

integration-test:
	$(MAKE) -C integration clean
	$(MAKE) -C integration

docs:
	$(MAKE) -C docs
	$(MAKE) -C uvm_bench pdf
	$(MAKE) -C vlate_bench pdf

# UVM bench Markdown → PDF only (`README.pdf`, `UVM_QUICKREF.pdf`). Requires pandoc (+ PDF backend).
uvm-pdf:
	$(MAKE) -C uvm_bench pdf

waves:
	$(MAKE) -C test waves

gtkwave:
	$(MAKE) -C test gtkwave

clean:
	$(MAKE) -C test clean
	$(MAKE) -C integration clean
	$(MAKE) -C docs clean
	$(MAKE) -C uvm_bench clean-pdf
	$(MAKE) -C vlate_bench clean-pdf
	rm -f results.xml

# Full OSS regression (Icarus cocotb + docs + Verilator lint + vlate_bench run). Needs `verilator` on PATH.
oss-regress:
	./scripts/oss-regress.sh

# Same as oss-regress, plus structural coverage: builds `obj_dir_cov/`, emits `vlate_bench/vlate_coverage.info`.
oss-regress-coverage:
	OSS_COVERAGE=1 ./scripts/oss-regress.sh

doctor:
	@echo "== Tool checks =="
	@command -v make >/dev/null 2>&1 || (echo "ERROR: make not found"; exit 1)
	@command -v python3 >/dev/null 2>&1 || (echo "ERROR: python3 not found"; exit 1)
	@command -v iverilog >/dev/null 2>&1 || (echo "ERROR: iverilog not found"; exit 1)
	@command -v vvp >/dev/null 2>&1 || (echo "ERROR: vvp not found"; exit 1)
	@command -v pandoc >/dev/null 2>&1 || (echo "ERROR: pandoc not found"; exit 1)
	@command -v cocotb-config >/dev/null 2>&1 || (echo "ERROR: cocotb-config not found (install cocotb or add ~/.local/bin to PATH)"; exit 1)
	@echo "make:        $$(command -v make)"
	@echo "python3:     $$(command -v python3)"
	@echo "iverilog:    $$(command -v iverilog)"
	@echo "vvp:         $$(command -v vvp)"
	@echo "pandoc:      $$(command -v pandoc)"
	@echo "cocotb-config:$$(command -v cocotb-config)"
	@echo "== Python/cocotb checks =="
	@python3 -c "import cocotb; print('cocotb import: OK (' + cocotb.__version__ + ')')" || (echo "ERROR: python3 cannot import cocotb"; exit 1)
	@python3 -c "import pytest; print('pytest import: OK (' + pytest.__version__ + ')')" 2>/dev/null || echo "pytest not installed (optional; improves cocotb assertion messages)"
	@echo "== Environment hints =="
	@echo "VIRTUAL_ENV=$${VIRTUAL_ENV:-<unset>}"
	@echo "PYTHONHOME=$${PYTHONHOME:-<unset>}"
	@echo "Doctor check passed."
