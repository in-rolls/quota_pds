#!/bin/zsh
cd /Users/soodoku/Documents/GitHub/pds_pradhan
for s in 01b_snapshot_inputs 02a_transactions_to_parquet 02b_card_flags 03a_gp_outcomes 03b_treatment_table 04a_itt 04b_open_seats 04c_index_and_placebos 05a_tables; do
  echo "== $s start $(date +%H:%M:%S)"
  Rscript scripts/$s.R >> logs/chain.log 2>&1 || { echo "$s" > logs/CHAIN_FAILED; exit 1; }
  echo "== $s done $(date +%H:%M:%S)"
done
touch logs/CHAIN_DONE
