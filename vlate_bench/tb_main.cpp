//---------------------------------------------------------------------------
// Parallel to uvm_bench chi_driver / chi_rsp_monitor / chi_sequence_base +
// chi_smoke_seq / chi_burst_smoke_seq / chi_illegal_req_test and chi_tb_cfg
// pacing defaults (see chi_tb.hpp timing::). Verilator C++ TB drives tb_top.
//---------------------------------------------------------------------------
#include <verilated.h>
#include "Vtb_top.h"

#include "chi_tb.hpp"
#include "chi_proto.hpp"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>

#if VM_COVERAGE
#include <verilated_cov.h>
#endif

namespace {

template <std::size_t N>
inline bool bit_is_set(const VlWide<N>& signal, int bit_idx) {
  return (signal[bit_idx / 32] & (1U << (bit_idx % 32))) != 0;
}

inline void clk_set(Vtb_top& t, unsigned level) {
  t.clk = level ? 1U : 0U;
  t.eval();
}

bool                     g_proto_fail = false;
chi_proto::HoldChecker   g_chk_req;
chi_proto::HoldChecker   g_chk_rsp;
chi_proto::HoldChecker   g_chk_inj;

void apply_idle_chi_inputs(Vtb_top& t, bool rst_low) {
  t.rst_n           = rst_low ? 0U : 1U;
  t.chi_req_valid   = 0;
  t.chi_req_opcode  = chi_tb::OP_READ_U8 & 3;
  t.chi_req_addr    = 0;
  t.chi_req_data    = 0;
  t.chi_req_beats   = 1;
  t.chi_req_txnid   = 0;
  t.chi_rsp_ready   = 1;
  t.bow_inj_en      = 0;
  t.bow_inj_valid   = 0;
  t.bow_inj_data_hi = 0;
  t.bow_inj_data_lo = 0;
}

// Rising-edge hook — chi_rsp_monitor::run_phase (subset) + protocol hold checks (chi_proto.hpp).
bool sampling_posedge_rsp(Vtb_top& t, chi_tb::scoreboard& sb, std::ostream& lg) {
  bool const rn = (t.rst_n & 1U) != 0;

  g_chk_req.posedge_sample(rn, t.chi_req_valid != 0, t.chi_req_ready != 0, "CHI_REQ", lg, g_proto_fail);
  g_chk_rsp.posedge_sample(rn, t.chi_rsp_valid != 0, t.chi_rsp_ready != 0, "CHI_RSP", lg, g_proto_fail);
  g_chk_inj.posedge_sample_inj(rn, (t.bow_inj_en & 1U) != 0, (t.bow_inj_valid & 1U) != 0,
      (t.bow_inj_ready & 1U) != 0, "BOW_INJ", lg, g_proto_fail);

  if (g_proto_fail) {
    return false;
  }
  if (!rn) {
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

bool run_clock_only(Vtb_top& t, chi_tb::scoreboard& sb, int cycles, std::ostream& lg) {
  for (int i = 0; i < cycles; ++i) {
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    clk_set(t, 0);
  }
  return true;
}

// Mirrors integration/test_integration unknown-txn rsp_hdr via bow_inj_*.
bool inject_unknown_txn_rsp_hdr(Vtb_top& t, chi_tb::scoreboard& sb, std::ostream& lg) {
  apply_idle_chi_inputs(t, /*rst_low=*/false);
  auto const base_unknown =
      static_cast<std::uint32_t>(t.err_unknown_txn_rsp_hdr);

  t.chi_rsp_ready = 1;
  // Same 128-bit flit as Cocotb (PKT_RSP_HDR<<124)|(CHI_WACK<<122)|(0xfe<<114).
  t.bow_inj_en      = 1;
  t.bow_inj_data_hi = UINT64_C(0x3ff8000000000000);
  t.bow_inj_data_lo = 0;
  t.bow_inj_valid   = 1;

  bool accepted = false;
  while (!accepted) {
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    if ((t.bow_inj_valid != 0U) && (t.bow_inj_ready != 0U)) {
      accepted = true;
    }
    if (!accepted) {
      clk_set(t, 0);
    }
  }

  t.bow_inj_valid = 0;
  clk_set(t, 0);
  clk_set(t, 1);
  if (!sampling_posedge_rsp(t, sb, lg)) {
    return false;
  }
  clk_set(t, 0);
  t.bow_inj_en = 0;

  bool bumped = false;
  for (int cy = 0; cy < 64; ++cy) {
    if (static_cast<std::uint32_t>(t.err_unknown_txn_rsp_hdr) ==
        base_unknown + 1U) {
      bumped = true;
      break;
    }
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    clk_set(t, 0);
  }

  if (!bumped) {
    lg << "[CHK] ERROR: err_unknown_txn_rsp_hdr failed to bump after inject\n";
    return false;
  }

  lg << "[CHK] unknown txn BoW RSP_HDR via bow_inj err_unknown_txn_rsp_hdr="
     << (base_unknown + 1U) << '\n';

  auto fail = [&](char const* n, std::uint32_t v, std::uint32_t e) -> bool {
    lg << "[CHK] ERROR: " << n << " obs=" << v << " exp=" << e << '\n';
    return false;
  };
  if (static_cast<std::uint32_t>(t.err_unknown_txn_rsp_hdr) !=
      base_unknown + 1U) {
    return fail("err_unknown_txn_rsp_hdr",
        static_cast<std::uint32_t>(t.err_unknown_txn_rsp_hdr), base_unknown + 1U);
  }
  if (static_cast<std::uint32_t>(t.err_unknown_txn_rsp_data) != 0U) {
    return fail(
        "err_unknown_txn_rsp_data", static_cast<std::uint32_t>(t.err_unknown_txn_rsp_data), 0U);
  }
  if (static_cast<std::uint32_t>(t.err_dup_rsp_hdr) != 0U) {
    return fail(
        "err_dup_rsp_hdr", static_cast<std::uint32_t>(t.err_dup_rsp_hdr), 0U);
  }
  if (static_cast<std::uint32_t>(t.err_orphan_rsp_data) != 0U) {
    return fail("err_orphan_rsp_data",
        static_cast<std::uint32_t>(t.err_orphan_rsp_data), 0U);
  }
  if (static_cast<std::uint32_t>(t.err_illegal_req_hdr) != 0U) {
    return fail(
        "err_illegal_req_hdr", static_cast<std::uint32_t>(t.err_illegal_req_hdr), 0U);
  }
  if (static_cast<std::uint32_t>(t.err_illegal_rsp_hdr) != 0U) {
    return fail(
        "err_illegal_rsp_hdr", static_cast<std::uint32_t>(t.err_illegal_rsp_hdr), 0U);
  }
  return true;
}

bool inject_duplicate_rsp_hdr(Vtb_top& t, chi_tb::scoreboard& sb, std::ostream& lg) {
  apply_idle_chi_inputs(t, /*rst_low=*/false);
  auto const base_dup = static_cast<std::uint32_t>(t.err_dup_rsp_hdr);
  std::uint8_t const txnid = 0x55;

  t.chi_rsp_ready = 1;
  t.bow_inj_en    = 1;

  // Drive CHI read request manually (no scoreboard expectation added, since it gets aborted)
  t.chi_req_opcode = static_cast<unsigned>(chi_tb::chi_op_ty::RD) & 3U;
  t.chi_req_addr   = 0x5000;
  t.chi_req_data   = 0;
  t.chi_req_beats  = 1;
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

  clk_set(t, 0);
  t.chi_req_valid = 0;
  clk_set(t, 1);
  if (!sampling_posedge_rsp(t, sb, lg)) {
    return false;
  }
  clk_set(t, 0);

  // Wait for the transaction to be pending
  bool is_pending = false;
  for (int cy = 0; cy < 64; ++cy) {
    if (bit_is_set(t.dbg_pending_txn, txnid)) {
      is_pending = true;
      break;
    }
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    clk_set(t, 0);
  }
  if (!is_pending) {
    lg << "[CHK] ERROR: txn 0x55 never became pending\n";
    return false;
  }

  // Inject first RSP_HDR: PKT_TYPE_RSP_HDR (3), CHI_OP_READ_RESP (2), has_data = 1
  std::uint64_t const inj_hdr_hi = (3ULL << 60) | (2ULL << 58) | (static_cast<std::uint64_t>(txnid) << 50) | (1ULL << 49);
  
  t.bow_inj_data_hi = inj_hdr_hi;
  t.bow_inj_data_lo = 0;
  t.bow_inj_valid   = 1;

  accepted = false;
  while (!accepted) {
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    if (t.bow_inj_valid && t.bow_inj_ready) {
      accepted = true;
    }
    if (!accepted) {
      clk_set(t, 0);
    }
  }

  // Clear valid to make it discrete
  t.bow_inj_valid = 0;
  clk_set(t, 0);
  clk_set(t, 1);
  if (!sampling_posedge_rsp(t, sb, lg)) {
    return false;
  }
  clk_set(t, 0);

  // Inject duplicate RSP_HDR
  t.bow_inj_valid = 1;
  accepted = false;
  while (!accepted) {
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    if (t.bow_inj_valid && t.bow_inj_ready) {
      accepted = true;
    }
    if (!accepted) {
      clk_set(t, 0);
    }
  }

  t.bow_inj_valid = 0;
  clk_set(t, 0);
  clk_set(t, 1);
  if (!sampling_posedge_rsp(t, sb, lg)) {
    return false;
  }
  clk_set(t, 0);
  t.bow_inj_en = 0;

  // Wait for duplicate counter to increment
  bool bumped = false;
  for (int cy = 0; cy < 64; ++cy) {
    if (static_cast<std::uint32_t>(t.err_dup_rsp_hdr) == base_dup + 1U) {
      bumped = true;
      break;
    }
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    clk_set(t, 0);
  }

  if (!bumped) {
    lg << "[CHK] ERROR: err_dup_rsp_hdr failed to bump after duplicate inject\n";
    return false;
  }

  lg << "[CHK] duplicate read-response header via bow_inj err_dup_rsp_hdr="
     << (base_dup + 1U) << '\n';

  return true;
}

bool inject_orphan_rsp_data(Vtb_top& t, chi_tb::scoreboard& sb, std::ostream& lg) {
  apply_idle_chi_inputs(t, /*rst_low=*/false);
  auto const base_orphan = static_cast<std::uint32_t>(t.err_orphan_rsp_data);
  std::uint8_t const txnid = 0x33;

  t.chi_rsp_ready = 1;
  t.bow_inj_en    = 1;
  // RSP_DATA packet for txnid 0x33: PKT_TYPE_RSP_DATA (4) at [127:124], txnid at [123:116] (hi [59:52])
  t.bow_inj_data_hi = (4ULL << 60) | (static_cast<std::uint64_t>(txnid) << 52);
  t.bow_inj_data_lo = UINT64_C(0x1234);
  t.bow_inj_valid   = 1;

  bool accepted = false;
  while (!accepted) {
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    if (t.bow_inj_valid && t.bow_inj_ready) {
      accepted = true;
    }
    if (!accepted) {
      clk_set(t, 0);
    }
  }

  t.bow_inj_valid = 0;
  clk_set(t, 0);
  clk_set(t, 1);
  if (!sampling_posedge_rsp(t, sb, lg)) {
    return false;
  }
  clk_set(t, 0);
  t.bow_inj_en = 0;

  bool bumped = false;
  for (int cy = 0; cy < 64; ++cy) {
    if (static_cast<std::uint32_t>(t.err_orphan_rsp_data) == base_orphan + 1U) {
      bumped = true;
      break;
    }
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    clk_set(t, 0);
  }

  if (!bumped) {
    lg << "[CHK] ERROR: err_orphan_rsp_data failed to bump after orphan inject\n";
    return false;
  }

  lg << "[CHK] orphan response data via bow_inj err_orphan_rsp_data="
     << (base_orphan + 1U) << '\n';

  return true;
}

bool inject_illegal_rsp_hdr(Vtb_top& t, chi_tb::scoreboard& sb, std::ostream& lg) {
  apply_idle_chi_inputs(t, /*rst_low=*/false);
  auto const base_illegal = static_cast<std::uint32_t>(t.err_illegal_rsp_hdr);
  std::uint8_t const w_txn = 0x61;
  std::uint8_t const r_txn = 0x62;

  t.chi_rsp_ready = 0;
  t.bow_inj_en    = 1;

  // 1) WRITE_ACK with has_data=1
  // Add expectation to scoreboard since we will complete this cleanly later
  chi_tb::chi_exp_item ex_wr{};
  ex_wr.op = chi_tb::chi_op_ty::WR;
  ex_wr.txnid = w_txn;
  sb.write_exp(ex_wr);

  // Drive CHI write request manually
  t.chi_req_opcode = static_cast<unsigned>(chi_tb::chi_op_ty::WR) & 3U;
  t.chi_req_addr   = 0x6100;
  t.chi_req_data   = 0xFEEDFACE;
  t.chi_req_beats  = 1;
  t.chi_req_txnid  = w_txn;
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

  clk_set(t, 0);
  t.chi_req_valid = 0;
  clk_set(t, 1);
  if (!sampling_posedge_rsp(t, sb, lg)) {
    return false;
  }
  clk_set(t, 0);

  // Wait for txn to be pending
  bool is_pending = false;
  for (int cy = 0; cy < 64; ++cy) {
    if (bit_is_set(t.dbg_pending_txn, w_txn)) {
      is_pending = true;
      break;
    }
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    clk_set(t, 0);
  }
  if (!is_pending) {
    lg << "[CHK] ERROR: WRITE txn 0x61 never pending\n";
    return false;
  }

  // Inject illegal WRITE_ACK (has_data=1)
  t.bow_inj_data_hi = (3ULL << 60) | (3ULL << 58) | (static_cast<std::uint64_t>(w_txn) << 50) | (1ULL << 49);
  t.bow_inj_data_lo = 0;
  t.bow_inj_valid   = 1;

  accepted = false;
  while (!accepted) {
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    if (t.bow_inj_valid && t.bow_inj_ready) {
      accepted = true;
    }
    if (!accepted) {
      clk_set(t, 0);
    }
  }

  t.bow_inj_valid = 0;
  clk_set(t, 0);
  clk_set(t, 1);
  if (!sampling_posedge_rsp(t, sb, lg)) {
    return false;
  }
  clk_set(t, 0);

  // Verify err_illegal_rsp_hdr bumped
  bool bumped = false;
  for (int cy = 0; cy < 64; ++cy) {
    if (static_cast<std::uint32_t>(t.err_illegal_rsp_hdr) == base_illegal + 1U) {
      bumped = true;
      break;
    }
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    clk_set(t, 0);
  }
  if (!bumped) {
    lg << "[CHK] ERROR: err_illegal_rsp_hdr failed to bump for illegal WRITE_ACK\n";
    return false;
  }

  // Quarantine checks
  if (!bit_is_set(t.dbg_pending_txn, w_txn)) {
    lg << "[CHK] ERROR: txn 0x61 cleared after illegal WRITE_ACK\n";
    return false;
  }
  if (bit_is_set(t.dbg_rsp_need_data, w_txn)) {
    lg << "[CHK] ERROR: rsp_need_data set for txn 0x61 after illegal WRITE_ACK\n";
    return false;
  }
  if (t.chi_rsp_valid != 0) {
    lg << "[CHK] ERROR: chi_rsp_valid asserted after illegal WRITE_ACK\n";
    return false;
  }

  // Complete with valid WRITE_ACK
  t.chi_rsp_ready = 1;
  t.bow_inj_data_hi = (3ULL << 60) | (3ULL << 58) | (static_cast<std::uint64_t>(w_txn) << 50) | (0ULL << 49);
  t.bow_inj_data_lo = 0;
  t.bow_inj_valid   = 1;

  accepted = false;
  while (!accepted) {
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    if (t.bow_inj_valid && t.bow_inj_ready) {
      accepted = true;
    }
    if (!accepted) {
      clk_set(t, 0);
    }
  }

  t.bow_inj_valid = 0;
  clk_set(t, 0);
  t.bow_inj_en    = 0;

  // Let valid WRITE_ACK retire (monitor/scoreboard checks it)
  bool response_seen = false;
  for (int cy = 0; cy < 64; ++cy) {
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    if (t.chi_rsp_valid && (t.chi_rsp_txnid == w_txn)) {
      response_seen = true;
    }
    clk_set(t, 0);
  }
  if (!response_seen) {
    lg << "[CHK] ERROR: valid WRITE_ACK failed to complete txn 0x61\n";
    return false;
  }

  // 2) READ_RESP with has_data=0
  t.chi_rsp_ready = 0;
  t.bow_inj_en    = 1;

  // Add expectation to scoreboard since we will complete this cleanly later
  chi_tb::chi_exp_item ex_rd{};
  ex_rd.op = chi_tb::chi_op_ty::RD;
  ex_rd.txnid = r_txn;
  sb.write_exp(ex_rd);

  // Drive CHI read request manually
  t.chi_req_opcode = static_cast<unsigned>(chi_tb::chi_op_ty::RD) & 3U;
  t.chi_req_addr   = 0x6200;
  t.chi_req_data   = 0;
  t.chi_req_beats  = 1;
  t.chi_req_txnid  = r_txn;
  t.chi_req_valid  = 1;

  accepted = false;
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

  clk_set(t, 0);
  t.chi_req_valid = 0;
  clk_set(t, 1);
  if (!sampling_posedge_rsp(t, sb, lg)) {
    return false;
  }
  clk_set(t, 0);

  // Wait for txn to be pending
  is_pending = false;
  for (int cy = 0; cy < 64; ++cy) {
    if (bit_is_set(t.dbg_pending_txn, r_txn)) {
      is_pending = true;
      break;
    }
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    clk_set(t, 0);
  }
  if (!is_pending) {
    lg << "[CHK] ERROR: READ txn 0x62 never pending\n";
    return false;
  }

  // Inject illegal READ_RESP (has_data=0)
  t.bow_inj_data_hi = (3ULL << 60) | (2ULL << 58) | (static_cast<std::uint64_t>(r_txn) << 50) | (0ULL << 49);
  t.bow_inj_data_lo = 0;
  t.bow_inj_valid   = 1;

  accepted = false;
  while (!accepted) {
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    if (t.bow_inj_valid && t.bow_inj_ready) {
      accepted = true;
    }
    if (!accepted) {
      clk_set(t, 0);
    }
  }

  t.bow_inj_valid = 0;
  clk_set(t, 0);
  clk_set(t, 1);
  if (!sampling_posedge_rsp(t, sb, lg)) {
    return false;
  }
  clk_set(t, 0);

  // Verify err_illegal_rsp_hdr bumped to base_illegal + 2
  bumped = false;
  for (int cy = 0; cy < 64; ++cy) {
    if (static_cast<std::uint32_t>(t.err_illegal_rsp_hdr) == base_illegal + 2U) {
      bumped = true;
      break;
    }
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    clk_set(t, 0);
  }
  if (!bumped) {
    lg << "[CHK] ERROR: err_illegal_rsp_hdr failed to bump to 2 for illegal READ_RESP\n";
    return false;
  }

  // Quarantine checks
  if (!bit_is_set(t.dbg_pending_txn, r_txn)) {
    lg << "[CHK] ERROR: txn 0x62 cleared after illegal READ_RESP\n";
    return false;
  }
  if (bit_is_set(t.dbg_rsp_need_data, r_txn)) {
    lg << "[CHK] ERROR: rsp_need_data set for txn 0x62 after illegal READ_RESP\n";
    return false;
  }
  if (t.chi_rsp_valid != 0) {
    lg << "[CHK] ERROR: chi_rsp_valid asserted after illegal READ_RESP\n";
    return false;
  }

  // Complete via BFM by disabling bow_inj_en and setting chi_rsp_ready = 1
  t.chi_rsp_ready = 1;
  clk_set(t, 1);
  if (!sampling_posedge_rsp(t, sb, lg)) {
    return false;
  }
  clk_set(t, 0);
  t.bow_inj_en = 0;

  // Let valid response from BFM retire and be checked by scoreboard
  response_seen = false;
  for (int cy = 0; cy < 64; ++cy) {
    clk_set(t, 1);
    if (!sampling_posedge_rsp(t, sb, lg)) {
      return false;
    }
    if (t.chi_rsp_valid && (t.chi_rsp_txnid == r_txn)) {
      response_seen = true;
    }
    clk_set(t, 0);
  }
  if (!response_seen) {
    lg << "[CHK] ERROR: BFM failed to complete txn 0x62\n";
    return false;
  }

  lg << "[CHK] illegal BoW response headers via bow_inj err_illegal_rsp_hdr="
     << (base_illegal + 2U) << '\n';

  return true;
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
    if (!sampling_posedge_rsp(*top, sb, lg)) {
      rc = 1;
      goto done;
    }
  }
  top->rst_n = 1;
  for (int i = 0; i < 4; ++i) {
    clk_set(*top, 0);
    clk_set(*top, 1);
    if (!sampling_posedge_rsp(*top, sb, lg)) {
      rc = 1;
      goto done;
    }
  }

  // --- single-beat smoke (chi_smoke_seq / chi_smoke_test; integration Cocotb order)
  if (!drive_until_accept(*top, chi_tb::chi_op_ty::RD,
          static_cast<std::uint64_t>(0x1000), std::uint64_t{0},
          1, 0x2A, sb, lg)) {
    rc = 1;
    goto done;
  }

  if (!run_clock_only(*top, sb, chi_tb::timing::cycles_for_ns(chi_tb::timing::SMOKE_GAP_RD_WR_NS), lg)) {
    rc = 1;
    goto done;
  }

  if (!drive_until_accept(*top, chi_tb::chi_op_ty::WR,
          static_cast<std::uint64_t>(0x2000),
          static_cast<std::uint64_t>(0xDEAD'BEEF'0000'0099ULL),
          1, 0x2B, sb, lg)) {
    rc = 1;
    goto done;
  }

  if (!run_clock_only(*top, sb,
          chi_tb::timing::cycles_for_ns(chi_tb::timing::SMOKE_DRAIN_NS), lg)) {
    rc = 1;
    goto done;
  }

  // --- multi-beat (chi_burst_smoke_seq / integration/cocotb parity)
  if (!drive_until_accept(*top, chi_tb::chi_op_ty::WR,
          static_cast<std::uint64_t>(0x3000'4000'5000'6000),
          static_cast<std::uint64_t>(0xBAD0C0DE11112222),
          3, 0x71, sb, lg)) {
    rc = 1;
    goto done;
  }

  if (!run_clock_only(*top, sb,
          chi_tb::timing::cycles_for_ns(chi_tb::timing::BURST_MID_NS), lg)) {
    rc = 1;
    goto done;
  }

  if (!drive_until_accept(*top, chi_tb::chi_op_ty::RD,
          static_cast<std::uint64_t>(0x5000), std::uint64_t{0},
          4, 0x72, sb, lg)) {
    rc = 1;
    goto done;
  }

  if (!run_clock_only(*top, sb,
          chi_tb::timing::cycles_for_ns(chi_tb::timing::BURST_MID_NS), lg)) {
    rc = 1;
    goto done;
  }

  // integration/test_integration :: test_integration_unknown_txnid_bow_rsp_hdr_via_inj
  // (runs before illegal-REQ bumps so isolation checks stay valid).
  if (!inject_unknown_txn_rsp_hdr(*top, sb, lg)) {
    rc = 1;
    goto done;
  }

  if (!inject_duplicate_rsp_hdr(*top, sb, lg)) {
    rc = 1;
    goto done;
  }

  if (!inject_orphan_rsp_data(*top, sb, lg)) {
    rc = 1;
    goto done;
  }

  if (!inject_illegal_rsp_hdr(*top, sb, lg)) {
    rc = 1;
    goto done;
  }

  // Illegal READ_RESP then WRITE_ACK on CHI REQ (chi_illegal_req_test / integration Cocotb)
  if (!run_clock_only(*top, sb, chi_tb::timing::ILLEGAL_SETTLE_CLKS, lg)) {
    rc = 1;
    goto done;
  }

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

  if (!run_clock_only(*top, sb,
          chi_tb::timing::cycles_for_ns(chi_tb::timing::ILLEGAL_TAIL_NS), lg)) {
    rc = 1;
    goto done;
  }

  // Long drain so stitched phases retire all responses (>= chi_tb_cfg::burst_drain_ns intent).
  if (!run_clock_only(*top, sb,
          chi_tb::timing::cycles_for_ns(chi_tb::timing::BURST_DRAIN_NS)
              + chi_tb::timing::COMBINED_FINAL_MARGIN_CYCLES,
          lg)) {
    rc = 1;
    goto done;
  }

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
