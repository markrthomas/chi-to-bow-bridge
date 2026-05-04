// Invoke from repo root or uvm_bench; paths are relative to uvm_bench/.
+incdir+tb
+incdir+uvm

// RTL / integration hierarchy
../src/chi_to_bow_bridge.v
../integration/bow_link_partner_bfm.v
../integration/chi_to_bow_integration_top.v
../verification/chi_integration_protocol_chk.sv

// UVM TB
tb/chi_integration_if.sv
uvm/chi_tb_pkg.sv
tb/tb_top.sv
