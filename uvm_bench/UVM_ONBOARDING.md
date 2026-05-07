# UVM bench onboarding

**Audience:** You already know **design verification** and **UVM** (agents, env, sequences, `config_db`, phasing). You are **new to this repository** and need to run or extend the Synopsys **VCS** integration testbench under **`uvm_bench/`**.

| Doc | Use when you need |
|-----|-------------------|
| **This file** | Mental model, diagrams, "where do I look?" |
| **[`README.md`](README.md)** | Full narrative, OSS parity table, coverage, manual `vcs` lines |
| **[`UVM_QUICKREF.md`](UVM_QUICKREF.md)** | One-screen commands, tests, paths, `config_db` keys |
| **[`docs/PLAN.md`](../docs/PLAN.md)** | Scenario matrix and parity policy vs Cocotb / Verilator |

---

## 1. Repository slice (integration verification)

```
repo root
|-- src/chi_to_bow_bridge.v           # Bridge RTL (also used by Cocotb / Verilator)
|-- integration/
|   |-- chi_to_bow_integration_top.v # DUT wrapper: bridge + mux + BFM tie-offs
|   +-- bow_link_partner_bfm.v        # Deterministic BoW link partner
|-- verification/
|   +-- chi_integration_protocol_chk.sv   # Bind: REQ/RSP/bow_inj valid-hold checks
+-- uvm_bench/                        # <-- You are here (VCS + UVM only)
    |-- sim.f
    |-- tb/tb_top.sv
    |-- tb/chi_integration_if.sv
    +-- uvm/chi_tb_pkg.sv             # Package: env, agent, tests, sequences
```

**Takeaway:** The **same integration RTL** that Cocotb drives under **`integration/`** is what UVM elaborates; parity is intentional.

---

## 2. DUT boundary (what the TB sees)

The top instantiated from **`tb_top`** is **`chi_to_bow_integration_top`**. Conceptually:

```
                    chi_to_bow_integration_top
 +---------------------------^---------------------------+
 |                           |                           |
 |    +----------------------+----------------------+    |
 |    |            chi_to_bow_bridge                |    |
 |    |   CHI REQ slave          BoW TX/RX master   |    |
 |    +----------------------^----------------------+    |
 |                           |                           |
 |              bow_inj mux (when bow_inj_en)            |
 |                           |                           |
 |    +----------------------+----------------------+    |
 |    |      bow_link_partner_bfm (in-repo)        |    |
 |    +---------------------------------------------+    |
 +---------------------------------------------------------+
        ^ CHI REQ/RSP              BoW flits (inside DUT)
        |                             ^
        | chi_integration_if          | (BFM + inject path)
```

Your **`chi_integration_if`** mirrors the CHI valid/ready nets, **`bow_inj_*`**, and **`err_*`** observability exported on the integration top.

---

## 3. UVM hierarchy (this bench)

All components below live in **`chi_tb_pkg`** unless noted.

```
tb_top (SV module)
  |
  +-- chi_integration_if (instance)
  |
  +-- uvm_test_top (from +UVM_TESTNAME)
        |
        +-- chi_*_test : chi_base_test
                  |
                  +-- chi_env
                        |-- chi_agent
                        |     |-- chi_driver       <- REQ stimulus, bow_inj tasks
                        |     |-- chi_sequencer
                        |     +-- chi_rsp_monitor  <- samples CHI RSP handshakes
                        |
                        |-- chi_scoreboard        <- expects vs observed RSP
                        +-- chi_integration_cov   <- functional cov (chi_tb_cov.svh)
```

| Component | Typical responsibility |
|-----------|------------------------|
| **`chi_driver`** | Drive **`chi_req_*`** until accepted; tasks **`inject_unknown_txn_rsp_hdr`**, **`drive_illegal_req_phase`** |
| **`chi_rsp_monitor`** | Detect completed responses (**`chi_rsp_valid && chi_rsp_ready`**) |
| **`chi_scoreboard`** | Match reads/writes to expected opcode / txnid / data (**`exp_read_data()`**) |
| **`chi_integration_cov`** | Sample REQ/RSP handshake bins on **`vif`** |

---

## 4. UVM phases (what runs where)

| UVM phase | Typical activity in this bench |
|-----------|--------------------------------|
| **`build_phase`** | **`tb_top`** sets **`vif`** in **`config_db`**; test builds **`chi_tb_cfg`** (default or override); **`chi_env`** creates agent, scoreboard, **`cov`**. |
| **`connect_phase`** | TLM ports not heavily custom here; agent internally wired in **`chi_agent`**. |
| **`run_phase`** | Sequences start on **`chi_sequencer`**; driver/monitor/scoreboard **`run_phase`** threads sample **`vif`**. |
| **`report_phase`** | **`chi_integration_cov`** prints **`[COV]`** handshake percentages to **`sim.log`**. |

---

## 5. Configuration flow (`config_db`)

```
tb_top (initial)
    |
    |  uvm_config_db#(virtual chi_integration_if)::set(null, "*", "vif", chi_if);
    |
    v
chi_base_test::build_phase
    |  default chi_tb_cfg; optional override via config_db#(chi_tb_cfg)::set(this,"", "chi_tb_cfg", cfg);
    |  publishes cfg to env.agent.seqr path (see chi_tb_pkg.sv)
    v
chi_env / chi_agent / driver / monitor / cov
    |  get virtual interface via get(this, "", "vif", vif)
    v
run_phase stimulus from sequences bound to chi_sequencer
```

Key string literals are **`chi_tb_pkg::CHI_DB_KEY_VIF`**, **`CHI_DB_KEY_TBCFG`**, **`CHI_DB_SCOPE_ALL`** - summarized again in **`UVM_QUICKREF.md`**.

---

## 6. Stimulus and checking flow (happy path)

| Step | Where | What happens |
|------|-------|----------------|
| 1 | Sequence (`chi_smoke_seq`, etc.) | Builds **`chi_seq_item`** → **`start_item`/`finish_item`** |
| 2 | Driver | Waits **`chi_req_ready`**, asserts **`chi_req_valid`** until handshake |
| 3 | DUT + BFM | BoW choreography completes; CHI RSP appears |
| 4 | Monitor | On RSP handshake, sends observation to scoreboard |
| 5 | Scoreboard | Compares against expectation queued at REQ acceptance |

Illegal / inject scenarios bypass scoreboard expectations where documented (**`chi_illegal_req_test`** checks **`err_*`** pins instead).

---

## 7. Parity with non-UVM lanes (same scenarios)

| Lane | Entry point | Role |
|------|-------------|------|
| **Integration Cocotb** | **`integration/test_integration.py`** | Primary OSS behavioral reference |
| **Verilator C++** | **`vlate_bench/tb_main.cpp`** | Fast parity regression |
| **UVM (this bench)** | **`+UVM_TESTNAME=...`** | Licensed VCS sign-off |

When you change stimulus or expectations, update **both** the mapping table in **`README.md`** and rows here **conceptually** stay aligned - **`docs/PLAN.md`** is the formal matrix owner.

---

## 8. Where to edit (quick decisions)

| Goal | Likely files |
|------|----------------|
| New directed scenario | **`uvm/chi_tb_pkg.sv`** - new sequence + test class; register test |
| Pacing / idle gaps | **`chi_tb_cfg`** defaults or per-test **`config_db`** override |
| New CHI-side checker | Scoreboard / monitor in **`chi_tb_pkg.sv`**; update **`chi_tb_cov.svh`** if observable bins matter |
| New integration-net exposure | **`tb/chi_integration_if.sv`**, **`tb/tb_top.sv`**, driver/monitor |
| RTL-facing bind checks | **`verification/chi_integration_protocol_chk.sv`** |

---

## 9. First commands

From **`uvm_bench/`** (requires **`vcs`**):

```bash
make run                              # default chi_smoke_test
make run UVM_TEST=chi_full_integration_test
```

PDF bundle for offline reading (Pandoc):

```bash
make pdf                              # README + QUICKREF + ONBOARDING (see Makefile)
```

---

## 10. Related specs

| Document | Content |
|----------|---------|
| **`docs/design_spec.md`** | CHI/BoW simplifications |
| **`docs/integration.md`** | Integration topology narrative |
| **`verification/golden_payloads.py`** | Opcode / txnid / payload constants (cross-check SV/C++) |
