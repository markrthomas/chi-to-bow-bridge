## Summary

- What does this PR change?
- Why is this change needed?

## Verification

- [ ] `make doctor`
- [ ] `make test`
- [ ] `make docs`
- [ ] **`make oss-regress`** (or equivalently **`make`** + **`vlate_bench` lint/run), if Integration / `vlate_bench` behavior changed; use **`make oss-regress-coverage`** if Verilator coverage path or `tb_main` shutdown/cov dump changed

## Checklist

- [ ] Documentation updated (if behavior/interfaces changed)
- [ ] **UVM parity:** If Integration Cocotb (`integration/test_integration.py`) or **`vlate_bench/tb_main.cpp`** scenarios changed or **`docs/PLAN.md`** gained new integration matrix coverage → update **`uvm_bench/uvm/chi_tb_pkg.sv`**, **`uvm_bench/uvm/chi_tb_cov.svh`** (functional bins/crosses) **and** the mapping table in **`uvm_bench/README.md`** (same PR preferred), or leave a checklist note + tracked issue linking the gap.
- [ ] New tests added or existing tests updated (if needed)
- [ ] No generated artifacts committed (`sim_build/`, `results.xml`, PDFs, etc.)
