#!/usr/bin/env bash
# OSS-only regression: same spirit as CI jobs `test` + `vlate-bench`.
# Requires: make, iverilog, vvp, pandoc, cocotb, python3; and `verilator` for vlate_bench.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== oss-regress: doctor + make (Icarus cocotb + docs) =="
make doctor
make

if ! command -v verilator >/dev/null 2>&1; then
  echo "ERROR: verilator not on PATH; install it to match CI vlate-bench (or run \`make\` only)." >&2
  exit 1
fi

echo "== oss-regress: verilator lint + vlate_bench run =="
make -C vlate_bench lint
make -C vlate_bench run

echo "== oss-regress: PASS =="
