// Integration sim (bridge + in-repo BoW link partner BFM)
// From repository root:  iverilog -g2012 -f integration/files.f
+incdir+.
./src/chi_to_bow_bridge.v
./integration/bow_link_partner_bfm.v
./integration/chi_to_bow_integration_top.v
