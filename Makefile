.PHONY: all test docs clean doctor waves gtkwave

all: test docs

test:
	$(MAKE) -C test clean
	$(MAKE) -C test

docs:
	$(MAKE) -C docs

waves:
	$(MAKE) -C test waves

gtkwave:
	$(MAKE) -C test gtkwave

clean:
	$(MAKE) -C test clean
	$(MAKE) -C docs clean
	rm -f results.xml

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
	@echo "== Environment hints =="
	@echo "VIRTUAL_ENV=$${VIRTUAL_ENV:-<unset>}"
	@echo "PYTHONHOME=$${PYTHONHOME:-<unset>}"
	@echo "Doctor check passed."
