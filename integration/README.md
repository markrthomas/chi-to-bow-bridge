# Integration simulation

- **DUT:** `chi_to_bow_integration_top` (bridge + burst-capable `bow_link_partner_bfm`). **`bow_inj_*`** ports mux testbench-supplied BoW RX flits into the bridge (**`bow_inj_en` low** ignores them; **`bow_inj_valid`/`bow_inj_ready`/`bow_inj_data_{hi,lo}`** implement the handshake).
- **Run:** from repo root, `make integration-test`, or here: `make`
- **Details:** [docs/integration.md](../docs/integration.md) (verification matrix: [docs/PLAN.md](../docs/PLAN.md))
