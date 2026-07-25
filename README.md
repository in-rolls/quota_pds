# pds_pradhan: Do Women Pradhans Reduce PDS Leakage?

GP-level test of whether women-led gram panchayats in Rajasthan show less
Public Distribution System corruption, using the 2021 PDS census (~16M rural
cards, member rosters, bill-level transactions), forensic ghost markers, and
the cross-register linkage to the 2018 electoral rolls.

## Design

- **Arm 1 (ITT, causal anchor):** reservation for women in the 2020 cycle —
  the pradhan in office at the PDS snapshot — is rotation-assigned.
  Samiti FE, caste-stratum controls, randomization inference.
- **Arm 2 (conditional on observables):** women *elected* in open 2020 seats,
  with block FE, census covariates, reservation history, seat caste, and
  winner affidavit controls; coefficient-stability sensitivity reported.
- Legacy vs current: 2005–2015 reservation history without 2020 separates
  persistence from the sitting pradhan.

## Outcomes (2021, GP level; headline = Anderson corruption index)

Duplicate identities (same applicant+father+village, multiple cards); photo
reuse across differently-named cards; cross-register ghosts (card adults with
no elector counterpart, differenced against a within-GP benchmark);
dead souls (85+); targeting discretion (BPL share unexplained by census
poverty); transaction outcomes (delivery regularity, ghost offtake, quantity
heaping). Placebo outcome: APL share (state-set, no GP discretion).

## Dependencies (referenced in place, md5-manifested)

| Source | What |
|---|---|
| `../jaali` | card CSVs, `out_full/fire*` forensics, photo `manifest.parquet` |
| `../milaan_raj` | panchayat→LGD-GP bridge, person links (ghost detection) |
| `../quota_shaadi/data/external/quota_raj/` | 2005–2020 treatment panel with `lgd_gp_code` |
| Dataverse doi:10.7910/DVN/FIFZEX | `rural_rationcardtransaction.csv.gz` (5 parts, 9.5 GB) |

Run: `Rscript scripts/99_run_all.R`. Audits in `data/audit/` (committed).
