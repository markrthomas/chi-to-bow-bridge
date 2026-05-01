#!/usr/bin/env bash
# OSS-only regression: same spirit as CI jobs `test` + `vlate-bench`.
# Optional: OSS_COVERAGE=1 or argv --coverage — also run Verilator instrumentation + write vlate_coverage.info.
# Requires: make, iverilog, vvp, pandoc, cocotb, python3; verilator (+ verilator_coverage) for vlate_bench.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

COV=0
for arg in "$@"; do
  if [[ "$arg" == "--coverage" ]]; then
    COV=1
  fi
done
if [[ "${OSS_COVERAGE:-0}" == "1" ]] || [[ "${OSS_COVERAGE:-}" == "true" ]]; then
  COV=1
fi

VLATE_MODE="run"
if [[ "$COV" == "1" ]]; then VLATE_MODE="coverage"; fi

echo "== oss-regress: doctor + make (Icarus cocotb + docs) =="
make doctor
make

if ! command -v verilator >/dev/null 2>&1; then
  echo "ERROR: verilator not on PATH; install it to match CI vlate-bench (or run \`make\` only)." >&2
  exit 1
fi

echo "== oss-regress: verilator lint + vlate_bench (${VLATE_MODE}) =="
make -C vlate_bench lint
if [[ "$COV" == "1" ]]; then
  if ! command -v verilator_coverage >/dev/null 2>&1; then
    echo "ERROR: verilator_coverage not on PATH (install Verilator)." >&2
    exit 1
  fi
  make -C vlate_bench coverage
else
  make -C vlate_bench run
fi

echo "== oss-regress: PASS =="
