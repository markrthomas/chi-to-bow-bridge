//----------------------------------------------------------------------
// Minimal UVM testbench for chi_to_bow_integration_top (Synopsys VCS compatible).
//----------------------------------------------------------------------
package chi_tb_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum logic [1:0] {
    CHI_RD = 2'b00,
    CHI_WR = 2'b01
  } chi_op_ty;

  localparam logic [1:0] CHI_RSP_READ = 2'b10;
  localparam logic [1:0] CHI_RSP_WACK  = 2'b11;

  // Mirror bow_link_partner_bfm deterministic read_payload (DATA_WIDTH == 64).
  function automatic logic [63:0] exp_read_data(input logic [7:0] txnid);
    return {32'hA5A5_A5A5, 8'd0, txnid[7:0], 8'd0, txnid[7:0]};
  endfunction

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
      if (!uvm_config_db#(virtual chi_integration_if)::get(this, "", "vif", vif)) begin
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
      if (!uvm_config_db#(virtual chi_integration_if)::get(this, "", "vif", vif)) begin
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

  //----------------------------------------------------------------------
  class chi_agent extends uvm_agent;
    `uvm_component_utils(chi_agent)

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

    chi_agent        agent;
    chi_scoreboard   sb;

    function new(string name = "chi_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = chi_agent::type_id::create("agent", this);
      sb    = chi_scoreboard::type_id::create("sb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.drv.ap_exp.connect(sb.exp_imp);
      agent.mon.ap.connect(sb.obs_imp);
    endfunction
  endclass

  //----------------------------------------------------------------------
  class chi_smoke_seq extends uvm_sequence #(chi_seq_item);
    `uvm_object_utils(chi_smoke_seq)

    function new(string name = "chi_smoke_seq");
      super.new(name);
    endfunction

    virtual task body();
      chi_seq_item w;
      chi_seq_item r;

      w = chi_seq_item::type_id::create("w");
      w.op = CHI_WR;
      w.addr = 64'h1234_5678_9ABC_DEF0;
      w.data = 64'hDEAD_BEEF_CAFE_BABE;
      w.txnid = 8'h3C;
      w.beats = 8'd1;
      start_item(w);
      finish_item(w);

      // Give bow_link_partner_bfm time to return to IDLE between transactions.
      #(500ns);

      r = chi_seq_item::type_id::create("r");
      r.op = CHI_RD;
      r.addr = 64'h1000;
      r.data = 64'h0;
      r.txnid = 8'h2A;
      r.beats = 8'd1;
      start_item(r);
      finish_item(r);
    endtask
  endclass

  //----------------------------------------------------------------------
  class chi_burst_smoke_seq extends uvm_sequence #(chi_seq_item);
    `uvm_object_utils(chi_burst_smoke_seq)

    function new(string name = "chi_burst_smoke_seq");
      super.new(name);
    endfunction

    virtual task body();
      chi_seq_item w;
      chi_seq_item r;

      w = chi_seq_item::type_id::create("bw");
      w.op = CHI_WR;
      w.addr = 64'h3000_4000_5000_6000;
      w.data = 64'hBAD0_C0DE_1111_2222;
      w.txnid = 8'h71;
      w.beats = 8'd3;
      start_item(w);
      finish_item(w);

      #(1us);

      r = chi_seq_item::type_id::create("br");
      r.op = CHI_RD;
      r.addr = 64'h5000;
      r.data = 64'h0;
      r.txnid = 8'h72;
      r.beats = 8'd4;
      start_item(r);
      finish_item(r);
    endtask
  endclass

  //----------------------------------------------------------------------
  class chi_burst_test extends uvm_test;
    `uvm_component_utils(chi_burst_test)

    chi_env env;

    function new(string name = "chi_burst_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = chi_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
      chi_burst_smoke_seq seq_h;
      phase.raise_objection(this);
      seq_h = chi_burst_smoke_seq::type_id::create("seq_h");
      seq_h.start(env.agent.seqr);
      #(8us);
      phase.drop_objection(this);
    endtask
  endclass

  //----------------------------------------------------------------------
  class chi_smoke_test extends uvm_test;
    `uvm_component_utils(chi_smoke_test)

    chi_env env;

    function new(string name = "chi_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = chi_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
      chi_smoke_seq seq_h;
      phase.raise_objection(this);
      seq_h = chi_smoke_seq::type_id::create("seq_h");
      seq_h.start(env.agent.seqr);
      // Req acceptance finishes before responses; allow BFM + bridge to drain.
      #(5us);
      phase.drop_objection(this);
    endtask
  endclass

endpackage : chi_tb_pkg
