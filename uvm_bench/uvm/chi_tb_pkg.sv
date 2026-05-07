//----------------------------------------------------------------------
// Minimal UVM testbench for chi_to_bow_integration_top (Synopsys VCS compatible).
//
// OSS parity: Integration scenarios MUST track:
//   - integration/test_integration.py (authoritative Cocotb)
//   - vlate_bench/tb_main.cpp (Verilator / C++)
//   - verification/golden_payloads.py + chi_tb.hpp (constants / read payloads)
// bow_inj_* BoW RX inject mux is wired through tb/chi_integration_if.sv (parity with Cocotb / vlate_bench).
// Mapping table: uvm_bench/README.md § "Stay synchronized with OSS"
// Coverage: uvm/chi_tb_cov.svh (chi_integration_cov: REQ/RSP, bow_inj handshake, err_pulse snapshots).
//----------------------------------------------------------------------
package chi_tb_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // config_db names — CHI_DB_SCOPE_ALL is for top-level `set(null, ...)`. Components still `get(this, "", ...)`.
  localparam string CHI_DB_SCOPE_ALL = "*";
  localparam string CHI_DB_KEY_VIF   = "vif";
  localparam string CHI_DB_KEY_TBCFG = "chi_tb_cfg";

  typedef enum logic [1:0] {
    CHI_RD = 2'b00,
    CHI_WR = 2'b01
  } chi_op_ty;

  localparam logic [1:0] CHI_RSP_READ = 2'b10;
  localparam logic [1:0] CHI_RSP_WACK  = 2'b11;

  // Unknown-txn RSP_HDR inject flit (128b hi/lo). Matches integration/test_integration.py `bad_hdr`
  // construction and vlate_bench/tb_main.cpp `inject_unknown_txn_rsp_hdr` (golden_payloads.py).
  localparam logic [63:0] BOW_INJ_UNKNOWN_HDR_HI = 64'h3FF8_0000_0000_0000;
  localparam logic [63:0] BOW_INJ_UNKNOWN_HDR_LO = 64'h0;

  // Mirror bow_link_partner_bfm read_payload — keep numeric layout aligned with verification/golden_payloads.py (bfm_read_data_u64).
  function automatic logic [63:0] exp_read_data(input logic [7:0] txnid);
    return {32'hA5A5_A5A5, 8'd0, txnid[7:0], 8'd0, txnid[7:0]};
  endfunction

  //----------------------------------------------------------------------
  // Typed knobs for pacing / drains — override via config_db from `chi_base_test` subtree or top.
  // C++ twin defaults: vlate_bench/chi_tb.hpp `chi_tb::timing`.
  //----------------------------------------------------------------------
  class chi_tb_cfg extends uvm_object;
    `uvm_object_utils_begin(chi_tb_cfg)
      `uvm_field_int(smoke_gap_rd_wr_ns, UVM_DEFAULT)
      `uvm_field_int(smoke_drain_ns, UVM_DEFAULT)
      `uvm_field_int(burst_mid_ns, UVM_DEFAULT)
      `uvm_field_int(burst_drain_ns, UVM_DEFAULT)
      `uvm_field_int(illegal_tail_ns, UVM_DEFAULT)
      `uvm_field_int(illegal_settle_clks, UVM_DEFAULT)
      `uvm_field_int(stitched_final_ns, UVM_DEFAULT)
    `uvm_object_utils_end

    int unsigned smoke_gap_rd_wr_ns = 500;
    int unsigned smoke_drain_ns     = 5000;
    int unsigned burst_mid_ns       = 1000;
    int unsigned burst_drain_ns     = 8000;
    int unsigned illegal_tail_ns    = 500;
    int unsigned illegal_settle_clks = 10;
    // Post-illegal idle for stitched smoke+burst+inject+illegal flow (vlate_bench tail scale).
    int unsigned stitched_final_ns  = 25000;
    function new(string name = "chi_tb_cfg");
      super.new(name);
    endfunction
  endclass

  //----------------------------------------------------------------------
  class chi_seq_item extends uvm_sequence_item;
    rand chi_op_ty     op;
    rand logic [63:0] addr;
    rand logic [63:0] data;
    rand logic [7:0]  txnid;
    rand logic [7:0]  beats;

    constraint c_beats_integration {beats >= 8'd1 && beats <= 8'd16;}

    `uvm_object_utils_begin(chi_seq_item)
      `uvm_field_enum(chi_op_ty, op, UVM_ALL_ON)
      `uvm_field_int(addr, UVM_ALL_ON)
      `uvm_field_int(data, UVM_ALL_ON)
      `uvm_field_int(txnid, UVM_ALL_ON)
      `uvm_field_int(beats, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "chi_seq_item");
      super.new(name);
    endfunction
  endclass

  class chi_exp_item extends uvm_object;
    chi_op_ty     op;
    logic [7:0]   txnid;

    `uvm_object_utils_begin(chi_exp_item)
      `uvm_field_enum(chi_op_ty, op, UVM_ALL_ON)
      `uvm_field_int(txnid, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "chi_exp_item");
      super.new(name);
    endfunction
  endclass

  class chi_obs_item extends uvm_object;
    logic [1:0]  rsp_op;
    logic [7:0]  txnid;
    logic [63:0] rsp_data;

    `uvm_object_utils_begin(chi_obs_item)
      `uvm_field_int(rsp_op, UVM_ALL_ON)
      `uvm_field_int(txnid, UVM_ALL_ON)
      `uvm_field_int(rsp_data, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "chi_obs_item");
      super.new(name);
    endfunction
  endclass

  //----------------------------------------------------------------------
  class chi_sequencer extends uvm_sequencer #(chi_seq_item);
    `uvm_component_utils(chi_sequencer)
    function new(string name = "chi_sequencer", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass

  //----------------------------------------------------------------------
  class chi_driver extends uvm_driver #(chi_seq_item);
    `uvm_component_utils(chi_driver)
    virtual chi_integration_if vif;
    uvm_analysis_port #(chi_exp_item) ap_exp;

    function new(string name = "chi_driver", uvm_component parent = null);
      super.new(name, parent);
      ap_exp = new("ap_exp", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual chi_integration_if)::get(this, "", CHI_DB_KEY_VIF, vif)) begin
        `uvm_fatal("CHIDRV", "virtual chi_integration_if not set for driver")
      end
    endfunction

    virtual task reset_phase(uvm_phase phase);
      phase.raise_objection(this);
      vif.chi_req_valid <= 1'b0;
      vif.chi_req_opcode <= chi_op_ty'(CHI_RD);
      vif.chi_req_addr <= '0;
      vif.chi_req_data <= '0;
      vif.chi_req_beats <= 8'd1;
      vif.chi_req_txnid <= '0;
      vif.chi_rsp_ready <= 1'b1;
      vif.bow_inj_en <= 1'b0;
      vif.bow_inj_valid <= 1'b0;
      vif.bow_inj_data_hi <= '0;
      vif.bow_inj_data_lo <= '0;
      wait(vif.rst_n === 1'b1);
      repeat (2) @(posedge vif.clk);
      phase.drop_objection(this);
    endtask

    virtual task run_phase(uvm_phase phase);
      chi_seq_item tr;
      chi_exp_item ex;

      forever begin
        seq_item_port.get_next_item(tr);
        drive_until_accept(tr);
        ex = chi_exp_item::type_id::create("ex");
        ex.op = tr.op;
        ex.txnid = tr.txnid;
        ap_exp.write(ex);
        seq_item_port.item_done();
      end
    endtask

    task automatic drive_until_accept(chi_seq_item tr);
      wait(vif.rst_n === 1'b1);
      @(posedge vif.clk);
      vif.chi_req_opcode <= logic [1:0]'(tr.op);
      vif.chi_req_addr   <= tr.addr;
      vif.chi_req_data   <= tr.data;
      vif.chi_req_beats  <= tr.beats;
      vif.chi_req_txnid  <= tr.txnid;
      vif.chi_req_valid  <= 1'b1;
      forever @(posedge vif.clk) begin
        if (vif.chi_req_valid && vif.chi_req_ready) begin
          vif.chi_req_valid <= 1'b0;
          break;
        end
      end
    endtask

    // Illegal CHI REQ opcodes (response encodings on REQ channel). No scoreboard expectation.
    // Parity: integration/test_integration.py `test_integration_illegal_chi_req_opcodes_increment_err_counter`.
    task automatic drive_illegal_req_phase(logic [1:0] opc, logic [7:0] txnid);
      wait(vif.rst_n === 1'b1);
      vif.chi_req_opcode <= opc;
      vif.chi_req_addr   <= '0;
      vif.chi_req_data   <= '0;
      vif.chi_req_beats  <= 8'd1;
      vif.chi_req_txnid  <= txnid;
      vif.chi_req_valid  <= 1'b1;
      forever @(posedge vif.clk) begin
        if (vif.chi_req_valid && vif.chi_req_ready) begin
          break;
        end
      end
      @(negedge vif.clk);
      if (vif.err_pulse !== 1'b1) begin
        `uvm_error("CHK", "err_pulse expected for illegal CHI REQ opcode")
      end
      vif.chi_req_valid <= 1'b0;
      @(posedge vif.clk);
    endtask

    // Unknown-txnid BoW RSP_HDR on bow_inj_* — parity: integration `test_integration_unknown_txnid_bow_rsp_hdr_via_inj`,
    // vlate_bench `inject_unknown_txn_rsp_hdr`. Leaves REQ idle; no scoreboard expectation.
    task automatic inject_unknown_txn_rsp_hdr();
      logic [31:0] base_unknown;
      int cy;
      bit bumped;
      wait(vif.rst_n === 1'b1);

      base_unknown = vif.err_unknown_txn_rsp_hdr;

      vif.chi_req_valid <= 1'b0;
      vif.chi_rsp_ready <= 1'b1;

      vif.bow_inj_en <= 1'b1;
      vif.bow_inj_data_hi <= BOW_INJ_UNKNOWN_HDR_HI;
      vif.bow_inj_data_lo <= BOW_INJ_UNKNOWN_HDR_LO;
      vif.bow_inj_valid <= 1'b1;

      forever @(posedge vif.clk) begin
        if (vif.bow_inj_valid && vif.bow_inj_ready) begin
          break;
        end
      end

      @(negedge vif.clk);
      vif.bow_inj_valid <= 1'b0;
      @(posedge vif.clk);
      @(negedge vif.clk);
      vif.bow_inj_en <= 1'b0;

      bumped = 1'b0;
      for (cy = 0; cy < 64; cy++) begin
        @(posedge vif.clk);
        if (vif.err_unknown_txn_rsp_hdr == base_unknown + 32'd1) begin
          bumped = 1'b1;
          break;
        end
      end

      if (!bumped) begin
        `uvm_error("CHK", "err_unknown_txn_rsp_hdr failed to bump after bow_inj RSP_HDR")
      end

      if (vif.err_unknown_txn_rsp_hdr !== base_unknown + 32'd1) begin
        `uvm_error("CHK",
          $sformatf("err_unknown_txn_rsp_hdr exp=%0d obs=%0d",
                    base_unknown + 32'd1, vif.err_unknown_txn_rsp_hdr))
      end
      if (vif.err_unknown_txn_rsp_data !== 32'd0) begin
        `uvm_error("CHK", "err_unknown_txn_rsp_data expected 0 after isolated unknown hdr inject")
      end
      if (vif.err_dup_rsp_hdr !== 32'd0) begin
        `uvm_error("CHK", "err_dup_rsp_hdr expected 0")
      end
      if (vif.err_orphan_rsp_data !== 32'd0) begin
        `uvm_error("CHK", "err_orphan_rsp_data expected 0")
      end
      if (vif.err_illegal_req_hdr !== 32'd0) begin
        `uvm_error("CHK", "err_illegal_req_hdr expected 0 after isolated unknown hdr inject")
      end
      if (vif.err_illegal_rsp_hdr !== 32'd0) begin
        `uvm_error("CHK", "err_illegal_rsp_hdr expected 0")
      end

      `uvm_info("CHK",
        $sformatf("unknown txn BoW RSP_HDR via bow_inj err_unknown_txn_rsp_hdr=%0d",
                  vif.err_unknown_txn_rsp_hdr),
        UVM_MEDIUM)
    endtask
  endclass
  //----------------------------------------------------------------------
  class chi_rsp_monitor extends uvm_monitor;
    `uvm_component_utils(chi_rsp_monitor)
    virtual chi_integration_if vif;
    uvm_analysis_port #(chi_obs_item) ap;

    function new(string name = "chi_rsp_monitor", uvm_component parent = null);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual chi_integration_if)::get(this, "", CHI_DB_KEY_VIF, vif)) begin
        `uvm_fatal("CHIMON", "virtual chi_integration_if not set for monitor")
      end
    endfunction

    virtual task run_phase(uvm_phase phase);
      chi_obs_item ob;
      forever begin
        @(posedge vif.clk);
        if (vif.rst_n !== 1'b1)
          continue;
        if (vif.chi_rsp_valid && vif.chi_rsp_ready) begin
          ob = chi_obs_item::type_id::create("ob");
          ob.rsp_op   = vif.chi_rsp_opcode;
          ob.txnid    = vif.chi_rsp_txnid;
          ob.rsp_data = vif.chi_rsp_data;
          `uvm_info("CHIMON",
            $sformatf("CHI_RSP op=%02h txn=%02h data=%016h", ob.rsp_op, ob.txnid, ob.rsp_data),
            UVM_MEDIUM)
          ap.write(ob);
        end
      end
    endtask
  endclass

  //----------------------------------------------------------------------
  `uvm_analysis_imp_decl(_chi_exp_imp)
  `uvm_analysis_imp_decl(_chi_obs_imp)

  class chi_scoreboard extends uvm_component;
    `uvm_component_utils(chi_scoreboard)

    uvm_analysis_imp_chi_exp_imp #(chi_exp_item, chi_scoreboard) exp_imp;
    uvm_analysis_imp_chi_obs_imp #(chi_obs_item, chi_scoreboard) obs_imp;

    chi_exp_item exp_fifo[$];

    virtual function void write_chi_exp_imp(chi_exp_item t);
      exp_fifo.push_back(t);
    endfunction

    virtual function void write_chi_obs_imp(chi_obs_item o);
      chi_exp_item e;

      `uvm_info("SB",
        $sformatf("OBS rsp_op=%02h txn=%02h data=%016h", o.rsp_op, o.txnid, o.rsp_data),
        UVM_MEDIUM)

      if (!exp_fifo.size()) begin
        `uvm_error("SB", "CHI response with no preceding expected request.")
        return;
      end
      e = exp_fifo.pop_front();

      if (e.txnid !== o.txnid) begin
        `uvm_error("SB",
          $sformatf("txn mismatch exp=%02h obs=%02h", e.txnid, o.txnid))
      end

      case (e.op)
        CHI_WR: begin
          if (o.rsp_op !== CHI_RSP_WACK) begin
            `uvm_error("SB", $sformatf("write expected WACK rsp_op=%02h", o.rsp_op))
          end
        end
        CHI_RD: begin
          if (o.rsp_op !== CHI_RSP_READ) begin
            `uvm_error("SB", $sformatf("read expected READ_RSP rsp_op=%02h", o.rsp_op))
          end else if (o.rsp_data !== exp_read_data(o.txnid)) begin
            `uvm_error("SB",
              $sformatf("read data mismatch obs=%016h exp=%016h", o.rsp_data, exp_read_data(o.txnid)))
          end
        end
        default:
          `uvm_error("SB", "unsupported op in expectation")
      endcase
    endfunction

    function new(string name = "chi_scoreboard", uvm_component parent = null);
      super.new(name, parent);
      exp_imp = new("exp_imp", this);
      obs_imp = new("obs_imp", this);
    endfunction

    virtual function void final_phase(uvm_phase phase);
      super.final_phase(phase);
      if (exp_fifo.size() != 0) begin
        `uvm_error("SB",
          $sformatf("%0d unmatched expected responses at end-of-test.", exp_fifo.size()))
      end
    endfunction
  endclass

  `include "chi_tb_cov.svh"

  //----------------------------------------------------------------------
  class chi_agent extends uvm_agent;
    `uvm_component_utils(chi_agent)

    // Classic ACTIVE agent fold: driver + sequencer share REQ traffic; monitor observes RSP only.
    chi_driver        drv;
    chi_sequencer     seqr;
    chi_rsp_monitor   mon;

    function new(string name = "chi_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      drv  = chi_driver::type_id::create("drv", this);
      seqr = chi_sequencer::type_id::create("seqr", this);
      mon  = chi_rsp_monitor::type_id::create("mon", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
  endclass

  //----------------------------------------------------------------------
  class chi_env extends uvm_env;
    `uvm_component_utils(chi_env)

    chi_agent             agent;
    chi_scoreboard        sb;
    chi_integration_cov   cov;

    function new(string name = "chi_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = chi_agent::type_id::create("agent", this);
      sb    = chi_scoreboard::type_id::create("sb", this);
      cov   = chi_integration_cov::type_id::create("cov", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.drv.ap_exp.connect(sb.exp_imp);
      agent.mon.ap.connect(sb.obs_imp);
    endfunction
  endclass

  //----------------------------------------------------------------------
  // Boilerplate-shaving layer: typed sequencer handle + small stimulus helpers.
  //----------------------------------------------------------------------
  virtual class chi_sequence_base extends uvm_sequence #(chi_seq_item);
    `uvm_declare_p_sequencer(chi_sequencer)

    chi_tb_cfg m_cfg;

    function new(string name = "chi_sequence_base");
      super.new(name);
    endfunction

    virtual task pre_start();
      super.pre_start();
      if (!uvm_config_db#(chi_tb_cfg)::get(get_sequencer(), "", CHI_DB_KEY_TBCFG, m_cfg)) begin
        `uvm_info("CHISEQ",
          "chi_tb_cfg not found on sequencer; using defaults",
          UVM_FULL)
        m_cfg = chi_tb_cfg::type_id::create("m_cfg");
      end
    endtask

    task automatic pause_ns(int unsigned ns);
      #(ns * 1ns);
    endtask

    task automatic drive_read(logic [63:0] addr, logic [7:0] txnid,
                              logic [7:0] beats = 8'd1);
      chi_seq_item tr;
      tr = chi_seq_item::type_id::create($sformatf("rd_%02h", txnid));
      tr.op = CHI_RD;
      tr.addr = addr;
      tr.data = '0;
      tr.txnid = txnid;
      tr.beats = beats;
      start_item(tr);
      finish_item(tr);
    endtask

    task automatic drive_write(logic [63:0] addr, logic [63:0] data, logic [7:0] txnid,
                               logic [7:0] beats = 8'd1);
      chi_seq_item tr;
      tr = chi_seq_item::type_id::create($sformatf("wr_%02h", txnid));
      tr.op = CHI_WR;
      tr.addr = addr;
      tr.data = data;
      tr.txnid = txnid;
      tr.beats = beats;
      start_item(tr);
      finish_item(tr);
    endtask
  endclass

  //----------------------------------------------------------------------
  // integration/test_integration.py smoke order: read @0x1000 txnid 0x2A, then write @0x2000 txnid 0x2B.
  class chi_smoke_seq extends chi_sequence_base;
    `uvm_object_utils(chi_smoke_seq)

    function new(string name = "chi_smoke_seq");
      super.new(name);
    endfunction

    virtual task body();
      drive_read(64'h1000, 8'h2A);
      pause_ns(m_cfg.smoke_gap_rd_wr_ns);
      drive_write(64'h2000, 64'hDEAD_BEEF_0000_0099, 8'h2B);
    endtask
  endclass

  //----------------------------------------------------------------------
  // Integration burst parity — override `burst_traffic()` in a subclass for directed variants.
  class chi_burst_smoke_seq extends chi_sequence_base;
    `uvm_object_utils(chi_burst_smoke_seq)

    function new(string name = "chi_burst_smoke_seq");
      super.new(name);
    endfunction

    virtual task body();
      burst_traffic();
    endtask

    virtual task burst_traffic();
      drive_write(64'h3000_4000_5000_6000, 64'hBAD0_C0DE_1111_2222, 8'h71, 8'd3);
      pause_ns(m_cfg.burst_mid_ns);
      drive_read(64'h5000, 8'h72, 8'd4);
    endtask
  endclass

  //----------------------------------------------------------------------
  virtual class chi_base_test extends uvm_test;

    chi_env env;
    chi_tb_cfg cfg;
    virtual chi_integration_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual chi_integration_if)::get(this, "", CHI_DB_KEY_VIF,
                                                            vif)) begin
        `uvm_fatal("CFG", "virtual chi_integration_if not set for chi_base_test subtree")
      end

      if (!uvm_config_db#(chi_tb_cfg)::get(this, "", CHI_DB_KEY_TBCFG, cfg)) begin
        cfg = chi_tb_cfg::type_id::create("cfg");
      end
      uvm_config_db#(chi_tb_cfg)::set(this, "env.agent.seqr", CHI_DB_KEY_TBCFG, cfg);

      env = chi_env::type_id::create("env", this);
    endfunction

    // Shared checker for illegal REQ opcodes (parity with integration Cocotb).
    task automatic expect_illegal_req_inc(logic [1:0] opc, logic [7:0] txn);
      logic [31:0] base_cnt;
      base_cnt = vif.err_illegal_req_hdr;
      env.agent.drv.drive_illegal_req_phase(opc, txn);
      if (vif.err_illegal_req_hdr !== (base_cnt + 32'd1)) begin
        `uvm_error("CHK",
          $sformatf("err_illegal_req_hdr exp=%0d obs=%0d",
                    base_cnt + 32'd1, vif.err_illegal_req_hdr))
      end
    endtask
  endclass

  //----------------------------------------------------------------------
  class chi_burst_test extends chi_base_test;
    `uvm_component_utils(chi_burst_test)

    function new(string name = "chi_burst_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
      chi_burst_smoke_seq seq_h;
      phase.raise_objection(this);
      seq_h = chi_burst_smoke_seq::type_id::create("seq_h");
      seq_h.start(env.agent.seqr);
      #(cfg.burst_drain_ns * 1ns);
      phase.drop_objection(this);
    endtask
  endclass

  //----------------------------------------------------------------------
  class chi_illegal_req_test extends chi_base_test;
    `uvm_component_utils(chi_illegal_req_test)

    function new(string name = "chi_illegal_req_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
      phase.raise_objection(this);

      repeat (cfg.illegal_settle_clks) @(posedge vif.clk);

      expect_illegal_req_inc(CHI_RSP_READ, 8'h01);
      expect_illegal_req_inc(CHI_RSP_WACK, 8'h02);

      #(cfg.illegal_tail_ns * 1ns);
      phase.drop_objection(this);
    endtask
  endclass

  //----------------------------------------------------------------------
  class chi_smoke_test extends chi_base_test;
    `uvm_component_utils(chi_smoke_test)

    function new(string name = "chi_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
      chi_smoke_seq seq_h;
      phase.raise_objection(this);
      seq_h = chi_smoke_seq::type_id::create("seq_h");
      seq_h.start(env.agent.seqr);
      #(cfg.smoke_drain_ns * 1ns);
      phase.drop_objection(this);
    endtask
  endclass

  //----------------------------------------------------------------------
  // integration/test_integration.py `test_integration_unknown_txnid_bow_rsp_hdr_via_inj`
  class chi_unknown_txn_inj_test extends chi_base_test;
    `uvm_component_utils(chi_unknown_txn_inj_test)

    function new(string name = "chi_unknown_txn_inj_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      repeat (4) @(posedge vif.clk);
      env.agent.drv.inject_unknown_txn_rsp_hdr();
      #(cfg.illegal_tail_ns * 1ns);
      phase.drop_objection(this);
    endtask
  endclass

  //----------------------------------------------------------------------
  // Stitched ordering mirrors vlate_bench/tb_main.cpp `main()`: smoke → burst → inject → illegal REQ.
  class chi_full_integration_test extends chi_base_test;
    `uvm_component_utils(chi_full_integration_test)

    function new(string name = "chi_full_integration_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
      chi_smoke_seq smoke_h;
      chi_burst_smoke_seq burst_h;
      phase.raise_objection(this);

      smoke_h = chi_smoke_seq::type_id::create("smoke_h");
      smoke_h.start(env.agent.seqr);
      #(cfg.smoke_drain_ns * 1ns);

      burst_h = chi_burst_smoke_seq::type_id::create("burst_h");
      burst_h.start(env.agent.seqr);
      #(cfg.burst_mid_ns * 1ns);

      env.agent.drv.inject_unknown_txn_rsp_hdr();

      repeat (cfg.illegal_settle_clks) @(posedge vif.clk);

      expect_illegal_req_inc(CHI_RSP_READ, 8'h01);
      expect_illegal_req_inc(CHI_RSP_WACK, 8'h02);

      #(cfg.illegal_tail_ns * 1ns);
      #(cfg.stitched_final_ns * 1ns);
      phase.drop_objection(this);
    endtask
  endclass

endpackage : chi_tb_pkg
