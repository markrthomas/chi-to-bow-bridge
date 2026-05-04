  //----------------------------------------------------------------------
  // Functional coverage on CHI handshakes (integration-facing interface).
  // Structural RTL coverage: optional Synopsys VCS -cm* flags (see Makefile coverage target).
  //----------------------------------------------------------------------
  class chi_integration_cov extends uvm_component;
    `uvm_component_utils(chi_integration_cov)

    virtual chi_integration_if vif;

    bit               sample_req;
    logic [1:0]       req_opc_s;
    logic [7:0]       req_txn_s;
    logic [7:0]       req_beats_s;

    bit               sample_rsp;
    logic [1:0]       rsp_opc_s;
    logic [7:0]       rsp_txn_s;

    covergroup cg_req_handshake;
      req_opc_cp: coverpoint req_opc_s iff (sample_req) {
        bins legal_rd = {2'b00};
        bins legal_wr = {2'b01};
        bins illegal_on_req_chan[] = {CHI_RSP_READ, CHI_RSP_WACK};
      }
      req_txn_cp: coverpoint req_txn_s iff (sample_req) {
        bins smoke_rd = {8'h2A};
        bins smoke_wr = {8'h2B};
        bins burst_wr = {8'h71};
        bins burst_rd = {8'h72};
        bins ill_01 = {8'h01};
        bins ill_02 = {8'h02};
        bins other = default;
      }
      req_beats_cp: coverpoint req_beats_s iff (sample_req) {
        bins single = {8'd1};
        bins burst_w_beats = {8'd3};
        bins burst_r_beats = {8'd4};
      }
      cross_opc_txn: cross req_opc_cp, req_txn_cp;
      cross_opc_beats: cross req_opc_cp, req_beats_cp;
    endgroup

    covergroup cg_rsp_handshake;
      rsp_opc_cp: coverpoint rsp_opc_s iff (sample_rsp) {
        bins read_rsp = {CHI_RSP_READ};
        bins write_ack = {CHI_RSP_WACK};
      }
      rsp_txn_cp: coverpoint rsp_txn_s iff (sample_rsp) {
        bins smoke_rd = {8'h2A};
        bins smoke_wr = {8'h2B};
        bins burst_wr = {8'h71};
        bins burst_rd = {8'h72};
        bins other = default;
      }
      cross_rsp_opc_txn: cross rsp_opc_cp, rsp_txn_cp;
    endgroup

    function new(string name = "chi_integration_cov", uvm_component parent = null);
      super.new(name, parent);
      cg_req_handshake = new();
      cg_rsp_handshake = new();
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual chi_integration_if)::get(this, "", CHI_DB_KEY_VIF, vif)) begin
        `uvm_fatal("COV", "virtual chi_integration_if not set for chi_integration_cov")
      end
    endfunction

    virtual task run_phase(uvm_phase phase);
      forever @(posedge vif.clk) begin
        sample_req = 1'b0;
        sample_rsp = 1'b0;
        if (vif.rst_n === 1'b1) begin
          if (vif.chi_req_valid && vif.chi_req_ready) begin
            sample_req   = 1'b1;
            req_opc_s    = vif.chi_req_opcode;
            req_txn_s    = vif.chi_req_txnid;
            req_beats_s  = vif.chi_req_beats;
          end
          if (vif.chi_rsp_valid && vif.chi_rsp_ready) begin
            sample_rsp = 1'b1;
            rsp_opc_s  = vif.chi_rsp_opcode;
            rsp_txn_s  = vif.chi_rsp_txnid;
          end
        end
        cg_req_handshake.sample();
        cg_rsp_handshake.sample();
      end
    endtask

    virtual function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("COV",
        $sformatf("Functional cg_req_handshake %0.2f%% cg_rsp_handshake %0.2f%%",
          cg_req_handshake.get_coverage(),
          cg_rsp_handshake.get_coverage()),
        UVM_LOW)
    endfunction
  endclass
