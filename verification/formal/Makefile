.PHONY: all bmc cover_write cover_read clean

SBY ?= sby

all: bmc cover_write cover_read

bmc:
	@if command -v $(SBY) >/dev/null 2>&1; then \
		$(SBY) -f chi_bow.sby; \
	else \
		echo "[FORMAL] sby not found; install SymbiYosys (OSS CAD Suite) to run formal"; \
		exit 0; \
	fi

cover_write:
	@if command -v $(SBY) >/dev/null 2>&1; then \
		$(SBY) -f chi_bow_cover_write.sby; \
	else \
		echo "[FORMAL] sby not found; install SymbiYosys (OSS CAD Suite) to run formal"; \
		exit 0; \
	fi

cover_read:
	@if command -v $(SBY) >/dev/null 2>&1; then \
		$(SBY) -f chi_bow_cover_read.sby; \
	else \
		echo "[FORMAL] sby not found; install SymbiYosys (OSS CAD Suite) to run formal"; \
		exit 0; \
	fi

clean:
	rm -rf chi_bow chi_bow_cover_write chi_bow_cover_read
