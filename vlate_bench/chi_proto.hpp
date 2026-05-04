//---------------------------------------------------------------------------
// Protocol hold checks — semantic twin of ../verification/chi_integration_protocol_chk.sv
// (valid must stay high until the matching ready completes the handshake).
//---------------------------------------------------------------------------
#ifndef VLATE_CHI_PROTO_HPP
#define VLATE_CHI_PROTO_HPP

#include <iostream>

namespace chi_proto {

class HoldChecker final {
public:
  void posedge_sample(bool rst_n, bool v, bool r, char const* tag, std::ostream& lg, bool& fatal_rc) {
    if (!rst_n) {
      waiting_ = false;
      return;
    }
    if (waiting_) {
      bool const hs = v && r;
      if (!hs && !v) {
        lg << "[PROTO] ERROR: " << tag << " valid dropped before ready\n";
        fatal_rc = true;
      }
    }
    waiting_ = v && !r;
  }

  // Matches chi_integration_protocol_chk.sv inj logic: enforce only while bow_inj_en; clear when inactive.
  void posedge_sample_inj(bool rst_n, bool en, bool v, bool r, char const* tag, std::ostream& lg,
      bool& fatal_rc) {
    if (!rst_n) {
      waiting_ = false;
      return;
    }
    if (!en) {
      waiting_ = false;
      return;
    }
    if (waiting_) {
      bool const hs = v && r;
      if (!hs && !v) {
        lg << "[PROTO] ERROR: " << tag << " valid dropped before ready\n";
        fatal_rc = true;
      }
    }
    waiting_ = v && !r;
  }

private:
  bool waiting_{false};
};

}  // namespace chi_proto

#endif
