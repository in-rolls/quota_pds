# Do Women Pradhans Reduce Corruption in the PDS?

India's Public Distribution System moves subsidized grain to roughly 800 million people through village-level Fair Price Shops, and gram panchayat (GP) heads, called pradhans or sarpanches, sit at the last mile of its administration. Rajasthan reserves a rotating subset of pradhan seats for women. This repository asks whether the GPs those women run show less PDS leakage, measured not by survey but by forensics on the 2021 ration-card census itself: 16 million rural cards, their 63 million member rosters, their photographs, and 200 million offtake transactions, joined to GP reservation histories and to the 2018 electoral rolls.

**Author**: Gaurav Sood

## Key findings

**Leakage is real, large, and unrelated to who runs the panchayat.**

The forensic base rates, over 13.6 million cards in 4,166 bridged GPs:

| Marker | Share of cards |
|---|---|
| Duplicate identity (same applicant + father + village on more than one card) | 6.4% |
| Photograph shared across cards with 3+ different applicant names | 0.03% |
| Household lists a member aged 85 or older | 1.2% |
| No recorded transaction, ever | 27% |

The causal test comes back a precise null. The pradhan in office at the 2021 snapshot was chosen in the 2020 cycle, and reservation of that seat for a woman is assigned by rotation within samiti and caste stratum. Regressing standardized leakage outcomes on reservation (samiti fixed effects, caste-stratum controls, SEs clustered by samiti, randomization inference within stratum):

| Outcome (standardized) | ITT estimate | p | RI p |
|---|---|---|---|
| Corruption index (Anderson, 8 components) | −0.026 | .54 | .54 |
| Duplicate identities | +0.019 | .49 | .51 |
| Photo reuse | −0.022 | .52 | |
| Excess cross-register ghosts | +0.005 | .85 | |
| Dead souls (85+) | +0.003 | .94 | |
| Targeting discretion | −0.022 | .59 | |
| Irregular delivery | +0.037 | .27 | .20 |
| Ghost offtake per card | +0.011 | .67 | |
| Subsidised cards with no transactions | +0.002 | .96 | |

Nothing moves. The confidence interval on the index rules out effects larger than about a tenth of a standard deviation in either direction. Reservation history (2005-2015) without the sitting pradhan is equally flat, so the null is not a story about effects taking longer than one term. The second arm, women who *won* open (non-reserved) 2020 seats, is identified only conditional on observables and says the same thing: no outcome is significant, and the coefficients barely move as controls are added.

Two placebo outcomes say the design would have caught an effect if one existed. APL classification is set by state rules and leaves the pradhan no discretion; reservation does not predict it (p = .47). The benchmark absence rate, which would flag selection in the rolls linkage, is also flat (p = .91).

Estimates live in `data/audit/04a_itt_estimates.csv`, `04b_open_seat_estimates.csv`, and `04c_placebo_estimates.csv`; formatted tables in `tabs/`.

## Research design

**Treatment.** Two arms, honestly labeled. Arm 1 is intent-to-treat: the GP's pradhan seat was reserved for a woman in 2020, an assignment rotated within samiti and caste stratum, so the comparison is as good as random conditional on those strata. Arm 2 restricts to open seats and compares GPs where a woman won to GPs where a man did; women win 12% of open seats, and who wins is not random, so this arm is conditional on observables (census covariates, full reservation history, seat caste category) and is reported with coefficient-stability checks across control sets. A legacy-dose term (reservations 2005-2015) separates the sitting pradhan from persistence of past exposure.

**Outcomes.** All are built from administrative data, at the GP level, standardized, and combined into an Anderson inverse-covariance-weighted index:

| Outcome | Construction |
|---|---|
| Duplicate identities | Cards sharing applicant name + father name + village code (fire2 logic from [jaali](https://github.com/in-rolls/jaali)) |
| Photo reuse | Card photo md5 appearing on cards with 3+ distinct applicant names; zero-byte images excluded |
| Excess ghosts | Card adults (25-70) with no counterpart in the 2018 electoral rolls via the [milaan_raj](../milaan_raj) person linkage, minus the same GP's absence rate for male household heads (30-60), which nets out linkage recall |
| Dead souls | Cards listing a member aged 85+ |
| Targeting discretion | Absolute residual of the GP's BPL/AAY share on census poverty predictors within block |
| Delivery regularity | Share of subsidised cards served in 10+ of the last 12 months (reversed) |
| Ghost offtake | Grain drawn by duplicate- or photo-flagged subsidised cards, per card |
| No-transaction cards | Subsidised cards with no bills at all |

**Geography.** PDS panchayats map to LGD GP codes through the transliteration-and-skeleton cascade built in milaan_raj (85% of cards bridge cleanly); reservation histories attach via the [quota_raj](https://github.com/in-rolls/quota_raj) panels.

## Data

Nothing large is committed; only `data/audit/` (aggregate audit CSVs, no personal data) is under version control.

| Source | Contents | How to obtain |
|---|---|---|
| Harvard Dataverse [doi:10.7910/DVN/FIFZEX](https://doi.org/10.7910/DVN/FIFZEX) | 2021 Rajasthan PDS: transactions (9.5 GB, five parts) | `Rscript scripts/01a_download_transactions.R` |
| [in-rolls/jaali](https://github.com/in-rolls/jaali) | Card CSVs, photo-hash manifest, forensic outputs | Clone as a sibling directory |
| milaan_raj | Panchayat-to-GP bridge; ration-to-rolls person links | Sibling directory; see its README |
| [in-rolls/quota_raj](https://github.com/in-rolls/quota_raj) | GP reservation panels 2005-2020 on LGD codes | Snapshotted via the quota_shaadi sibling |

Scale: 15.97M rural cards, 62.8M members, 13.6M cards bridged to 4,166 analysis GPs (49% reserved in 2020), 12.9M cards with transactions collapsed from 200M+ bills to card-month and card level (`data/transactions/bills.parquet` retains bill dates and grain quantities for month-level work, such as testing for electoral cycles in offtake).

## Reproduction

```bash
git clone https://github.com/in-rolls/pds_pradhan
cd pds_pradhan && Rscript -e 'renv::restore()'
export DATAVERSE_KEY=<your token>   # optional, files are public
Rscript scripts/99_run_all.R
```

Sibling directories expected at `../jaali`, `../milaan_raj`, `../quota_shaadi` (paths overridable via `JAALI_DIR`, `MILAAN_DIR`, `QUOTA_SHAADI_DIR`). Budget roughly 30 GB of transient disk and an hour, most of it the transaction download and scan. Every matching and construction stage writes an audit CSV to `data/audit/`.

## Caveats

- The PDS snapshot is from 2021 and the treatment cohort took office in 2020, so the design estimates roughly one year of a pradhan's influence on stock measures (card composition accumulates over years) and one year of flow measures (transactions).
- Transaction-period outcomes overlap COVID-era free-grain schemes; month fixed effects and the audited month series (`data/audit/02a_month_series.csv`) address levels, and the 2019-only regularity measure is available as robustness.
- The ghost outcome exists only for the 2,895 GPs that bridge to both the PDS and the electoral rolls; its benchmark-differencing removes GP-level linkage recall but not member-level idiosyncrasies.
- Arm 2 (open-seat winners) is not experimental. It is reported because the conditional-on-observables comparison is the question many readers will ask; its nulls are consistent with Arm 1's.

## Related work

Chattopadhyay and Duflo (2004, *Econometrica*) established that women pradhans change public-goods allocation; Beaman et al. (2012, *Science*) argued that exposure to them changes aspirations. This repository asks the governance-integrity question at administrative scale and finds that on PDS leakage, at least in Rajasthan circa 2021, the gender of the pradhan makes no detectable difference, while the leakage itself is easy to detect.
