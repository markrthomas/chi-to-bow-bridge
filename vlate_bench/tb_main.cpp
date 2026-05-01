//---------------------------------------------------------------------------
// Parallel to uvm_bench chi_driver / chi_rsp_monitor / chi_smoke_seq /
// chi_burst_smoke_seq / chi_illegal_req_test. Verilator C++ TB drives tb_top.
//---------------------------------------------------------------------------
#include <verilated.h>
#include "Vtb_top.h"

#include "chi_tb.hpp"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>

#if VM_COVERAGE
#include <verilated_cov.h>
#endif

namespace {

inline void clk_set(Vtb_top& t, unsigned level) {
  t.clk = level ? 1U : 0U;
  t.eval();
}

void apply_idle_chi_inputs(Vtb_top& t, bool rst_low) {
  t.rst_n           = rst_low ? 0U : 1U;
  t.chi_req_valid   = 0;
  t.chi_req_opcode  = chi_tb::OP_READ_U8 & 3;
  t.chi_req_addr    = 0;
  t.chi_req_data    = 0;
  t.chi_req_beats   = 1;
  t.chi_req_txnid   = 0;
  t.chi_rsp_ready   = 1;
}

// Rising-edge hook — chi_rsp_monitor::run_phase (subset).
bool sampling_posedge_rsp(Vtb_top& t, chi_tb::scoreboard& sb, std::ostream& lg) {
  if ((t.rst_n & 1U) == 0U) {
    return true;
  }
  if (t.chi_rsp_valid && t.chi_rsp_ready) {
    chi_tb::chi_obs_item ob{};
    ob.rsp_op   = static_cast<std::uint8_t>(t.chi_rsp_opcode) & 3;
    ob.txnid    = static_cast<std::uint8_t>(t.chi_rsp_txnid);
    ob.rsp_data = static_cast<std::uint64_t>(t.chi_rsp_data);
    lg << "[MON] CHI_RSP op=" << int(ob.rsp_op)
       << " txn=" << int(ob.txnid) << " data=0x"
       << std::hex << ob.rsp_data << std::dec << '\n';
    std::string err;
    if (!sb.write_obs(ob, lg, &err)) {
      (void)err;
      return false;
    }
  }
  return true;
}

// Mirrors chi_driver::drive_until_accept + exp_ap.write ordering in chi_tb_pkg.sv.
bool drive_until_accept(Vtb_top& t, chi_tb::chi_op_ty op,
    std::uint64_t addr, std::uint64_t data,
    std::uint8_t beats, std::uint8_t txnid,
    chi_tb::scoreboard& sb, std::ostream& lg) {

  apply_idle_chi_inputs(t, /*rst_low=*/false);
  t.chi_rsp_ready = 1;

  while (!t.rst_n) {
    clk_set(t, 0);
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
  }

  clk_set(t, 1);
  if (!sampling_posedge_rsp(t, sb, lg)) {
    return false;
  }
  clk_set(t, 0);

  t.chi_req_opcode = static_cast<unsigned>(op) & 3U;
  t.chi_req_addr   = addr;
  t.chi_req_data   = data;
  t.chi_req_beats  = beats;
  t.chi_req_txnid  = txnid;
  t.chi_req_valid  = 1;

  bool accepted = false;
  while (!accepted) {
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    if (t.chi_req_valid && t.chi_req_ready) {
      accepted = true;
    }
    if (!accepted) {
      clk_set(t, 0);
    }
  }

  chi_tb::chi_exp_item ex{};
  ex.op = op;
  ex.txnid = txnid;
  sb.write_exp(ex);

  clk_set(t, 0);
  t.chi_req_valid = 0;
  clk_set(t, 1);
  if (!sampling_posedge_rsp(t, sb, lg)) {
    return false;
  }
  clk_set(t, 0);

  lg << "[DRV] accepted CHI REQ op=" << int(static_cast<unsigned>(op))
     << " txn=" << int(txnid) << '\n';
  return true;
}

void run_clock_only(Vtb_top& t, chi_tb::scoreboard& sb, int cycles, std::ostream& lg) {
  for (int i = 0; i < cycles; ++i) {
    clk_set(t, 1);
    (void)sampling_posedge_rsp(t, sb, lg);
    clk_set(t, 0);
  }
}

// integration/test_integration.py + uvm chi_illegal_req_test / drive_illegal_req_phase
bool drive_illegal_req_phase(Vtb_top& t, std::uint8_t opc2, std::uint8_t txnid,
    std::uint32_t ctr_exp, chi_tb::scoreboard& sb, std::ostream& lg) {

  apply_idle_chi_inputs(t, /*rst_low=*/false);
  t.chi_rsp_ready   = 1;
  t.chi_req_opcode  = opc2 & 3U;
  t.chi_req_addr    = 0;
  t.chi_req_data    = 0;
  t.chi_req_beats   = 1;
  t.chi_req_txnid   = txnid;
  t.chi_req_valid   = 1;

  bool accepted = false;
  while (!accepted) {
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    if ((t.chi_req_valid != 0) && (t.chi_req_ready != 0)) {
      accepted = true;
    }
    if (!accepted) {
      clk_set(t, 0);
    }
  }

  // Handshake completes with CLK high — negedge Cocotb uses to sample err_pulse (valid still high).
  clk_set(t, 0);
  if ((t.err_pulse & 1U) == 0U) {
    lg << "[CHK] ERROR: err_pulse expected for illegal CHI REQ opcode\n";
    return false;
  }

  t.chi_req_valid = 0;
  clk_set(t, 1);
  if (!sampling_posedge_rsp(t, sb, lg)) {
    return false;
  }
  clk_set(t, 0);

  auto const ctr = static_cast<std::uint32_t>(t.err_illegal_req_hdr);
  if (ctr != ctr_exp) {
    lg << "[CHK] ERROR: err_illegal_req_hdr exp=" << ctr_exp << " obs=" << ctr << '\n';
    return false;
  }
  lg << "[CHK] illegal REQ opcode txn=" << int(txnid)
     << " err_illegal_req_hdr=" << ctr << '\n';
  return true;
}

}  // namespace

static void sim_shutdown(Vtb_top& top, std::ostream& lg) {
  top.final();
#if VM_COVERAGE
  const char* covpath = std::getenv("VL_COV_FILENAME");
  if (covpath && covpath[0] != '\0') {
    VerilatedCov::write(covpath);
    lg << "[COV] wrote " << covpath << '\n';
  } else {
    VerilatedCov::write();
    lg << "[COV] wrote " << VerilatedCov::defaultFilename() << '\n';
  }
#endif
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  auto top = std::make_unique<Vtb_top>();

  chi_tb::scoreboard sb;
  std::ostream&      lg = std::cout;
  int                rc  = 0;

  apply_idle_chi_inputs(*top, /*rst_low=*/true);
  top->eval();

  // Reset & release (align with uvm_bench/tb_top.sv pacing).
  for (int i = 0; i < 14; ++i) {
    clk_set(*top, 0);
    clk_set(*top, 1);
    (void)sampling_posedge_rsp(*top, sb, lg);
  }
  top->rst_n = 1;
  for (int i = 0; i < 4; ++i) {
    clk_set(*top, 0);
    clk_set(*top, 1);
    (void)sampling_posedge_rsp(*top, sb, lg);
  }

  // --- single-beat smoke (chi_smoke_seq / chi_smoke_test; integration Cocotb order)
  if (!drive_until_accept(*top, chi_tb::chi_op_ty::RD,
          static_cast<std::uint64_t>(0x1000), std::uint64_t{0},
          1, 0x2A, sb, lg)) {
    rc = 1;
    goto done;
  }

  run_clock_only(*top, sb, /*50 cycles ≈500 ns*/ 50, lg);

  if (!drive_until_accept(*top, chi_tb::chi_op_ty::WR,
          static_cast<std::uint64_t>(0x2000),
          static_cast<std::uint64_t>(0xDEAD'BEEF'0000'0099ULL),
          1, 0x2B, sb, lg)) {
    rc = 1;
    goto done;
  }

  run_clock_only(*top, sb, /*pacing between smoke and burst */ 200, lg);

  // --- multi-beat (chi_burst_smoke_seq / integration/cocotb parity)
  if (!drive_until_accept(*top, chi_tb::chi_op_ty::WR,
          static_cast<std::uint64_t>(0x3000'4000'5000'6000),
          static_cast<std::uint64_t>(0xBAD0C0DE11112222),
          3, 0x71, sb, lg)) {
    rc = 1;
    goto done;
  }

  run_clock_only(*top, sb, 150, lg);

  if (!drive_until_accept(*top, chi_tb::chi_op_ty::RD,
          static_cast<std::uint64_t>(0x5000), std::uint64_t{0},
          4, 0x72, sb, lg)) {
    rc = 1;
    goto done;
  }

  run_clock_only(*top, sb, 100, lg);

  // Illegal READ_RESP then WRITE_ACK on CHI REQ (chi_illegal_req_test / integration Cocotb)
  {
    auto const base0 = static_cast<std::uint32_t>(top->err_illegal_req_hdr);
    if (!drive_illegal_req_phase(*top, chi_tb::CHI_RSP_READ, 0x01, base0 + 1U, sb, lg)) {
      rc = 1;
      goto done;
    }
    auto const base1 = static_cast<std::uint32_t>(top->err_illegal_req_hdr);
    if (!drive_illegal_req_phase(*top, chi_tb::CHI_RSP_WACK, 0x02, base1 + 1U, sb, lg)) {
      rc = 1;
      goto done;
    }
  }

  // Drain long enough for bursts + smoke tail (chi_burst_test objection scale)
  run_clock_only(*top, sb, 2500, lg);

  if (sb.pending() != 0U) {
    lg << "[SB] ERROR: " << sb.pending() << " unmatched expected responses at end-of-test.\n";
    rc = 1;
    goto done;
  }

  lg << "TB: PASS\n";

done:
  sim_shutdown(*top, lg);
  return rc;
}
