//---------------------------------------------------------------------------
// chi_tb.hpp — parallels uvm_bench/uvm/chi_tb_pkg.sv (no UVM): types + scoreboard.
//---------------------------------------------------------------------------
#ifndef VLATE_CHI_TB_HPP
#define VLATE_CHI_TB_HPP

#include <cstdint>
#include <deque>
#include <iostream>
#include <string>

namespace chi_tb {

constexpr std::uint8_t OP_READ_U8   = 0x0;
constexpr std::uint8_t OP_WRITE_U8  = 0x1;

enum class chi_op_ty : std::uint8_t { RD = OP_READ_U8, WR = OP_WRITE_U8 };

constexpr std::uint8_t CHI_RSP_READ = 0x2;
constexpr std::uint8_t CHI_RSP_WACK = 0x3;

// bow_link_partner_bfm read_payload — must match DATA_WIDTH == 64 in RTL/BFM.
inline std::uint64_t exp_read_data(std::uint8_t txnid) {
  return (static_cast<std::uint64_t>(0xA5A5A5A5) << 32) |
         (static_cast<std::uint64_t>(0) << 24) |
         (static_cast<std::uint64_t>(txnid) << 16) |
         (static_cast<std::uint64_t>(0) << 8) | static_cast<std::uint64_t>(txnid);
}

struct chi_exp_item {
  chi_op_ty    op{};
  std::uint8_t txnid{0};
};

struct chi_obs_item {
  std::uint8_t rsp_op{0};  // 2 bits used
  std::uint8_t txnid{0};
  std::uint64_t rsp_data{0};
};

// Mirrors chi_scoreboard in chi_tb_pkg (analysis imp style: exp queue vs obs arrivals).
class scoreboard final {
public:
  void write_exp(chi_exp_item const& e) { exp_fifo_.push_back(e); }

  bool write_obs(chi_obs_item const& o, std::ostream& lg, std::string* err_out = nullptr) {
    std::string err;
    if (exp_fifo_.empty()) {
      err = "CHI response with no preceding expected request.";
      lg << "[SB] ERROR: " << err << '\n';
      if (err_out) {
        *err_out = std::move(err);
      }
      return false;
    }

    chi_exp_item const exp = exp_fifo_.front();
    exp_fifo_.pop_front();

    if (exp.txnid != o.txnid) {
      err = "txn mismatch exp=" + std::to_string(exp.txnid) + " obs=" + std::to_string(o.txnid);
      lg << "[SB] ERROR: " << err << '\n';
      if (err_out) {
        *err_out = std::move(err);
      }
      return false;
    }

    switch (exp.op) {
      case chi_op_ty::WR: {
        if (o.rsp_op != CHI_RSP_WACK) {
          err = "write expected WACK rsp_op";
          lg << "[SB] ERROR: " << err << '\n';
          if (err_out) {
            *err_out = std::move(err);
          }
          return false;
        }
        break;
      }
      case chi_op_ty::RD: {
        if (o.rsp_op != CHI_RSP_READ) {
          err = "read expected READ_RSP rsp_op";
          lg << "[SB] ERROR: " << err << '\n';
          if (err_out) {
            *err_out = std::move(err);
          }
          return false;
        }
        auto const wants = exp_read_data(o.txnid);
        if (o.rsp_data != wants) {
          err = "read data mismatch";
          lg << "[SB] ERROR: " << err << '\n';
          if (err_out) {
            *err_out = std::move(err);
          }
          return false;
        }
        break;
      }
    }

    lg << "[SB] OBS rsp_op=" << int(o.rsp_op) << " txn=" << int(o.txnid) << " data=0x" << std::hex
       << o.rsp_data << std::dec << " OK\n";
    return true;
  }

  bool empty() const { return exp_fifo_.empty(); }

  std::size_t pending() const { return exp_fifo_.size(); }

private:
  std::deque<chi_exp_item> exp_fifo_;
};

}  // namespace chi_tb

#endif
