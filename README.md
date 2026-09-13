# Do Women Pradhans Reduce Corruption in the PDS?

India's Public Distribution System moves subsidized grain to roughly 800 million people through village-level Fair Price Shops, and gram panchayat (GP) heads, called pradhans or sarpanches, sit at the last mile of its administration. Rajasthan reserves a rotating subset of pradhan seats for women. This repository asks whether the GPs those women run show less PDS leakage, measured not by survey but by forensics on the 2021 ration-card census itself: 16 million rural cards, their 63 million member rosters, their photographs, and 200 million offtake transactions, joined to GP reservation histories and to the 2018 electoral rolls.

**Author**: Gaurav Sood

## Key findings

**Leakage is real, large, and unrelated to who runs the panchayat.**

The forensic base rates, over 13.6 million cards in 4,165 bridged GPs:

| Marker | Share of cards |
|---|---|
| Duplicate identity (same applicant + father + village on more than one card) | 6.4% |
| Photograph shared across cards with 3+ different applicant names | 0.03% |
| Household lists a member aged 85 or older | 1.2% |
| No recorded transaction, ever | 27% |

The causal test comes back a precise null. The pradhan in office at the 2021 snapshot was chosen in the 2020 cycle, and reservation of that seat for a woman is assigned by rotation within samiti and caste stratum. Regressing standardized leakage outcomes on reservation (samiti fixed effects, caste-stratum controls, SEs clustered by samiti, randomization inference within stratum):

| Outcome (standardized) | ITT estimate | p | RI p |
|---|---|---|---|
| Corruption index (Anderson, 8 components) | −0.026 | .54 | .52 |
| Duplicate identities | +0.019 | .49 | .55 |
| Photo reuse | −0.022 | .52 |  |
| Excess cross-register ghosts | +0.005 | .85 |  |
| Dead souls (85+) | +0.003 | .94 |  |
| Targeting discretion | −0.021 | .59 |  |
| Irregular delivery | +0.037 | .28 | .21 |
| Ghost offtake per card | +0.011 | .66 |  |
| Subsidised cards with no transactions | +0.001 | .96 |  |

Nothing moves. The confidence interval on the index rules out effects larger than about a tenth of a standard deviation in either direction. Reservation history (2005-2015) without the sitting pradhan is equally flat, so the null is not a story about effects taking longer than one term. The second arm, women who *won* open (non-reserved) 2020 seats, is identified only conditional on observables and says the same thing: no outcome is significant, and the coefficients barely move as controls are added.

Two placebo outcomes say the design would have caught an effect if one existed. APL classification is set by state rules and leaves the pradhan no discretion; reservation does not predict it (p = .47). The benchmark absence rate, which would flag selection in the rolls linkage, is also flat (p = .91).

### Access and generosity

The same machinery answers the benefit-side questions: do women pradhans deliver more grain, or get more families onto the rolls of the PDS itself? The measurement checks out almost embarrassingly well: subsidised households draw 5.01 kg per member-month against the NFSA entitlement of exactly 5 kg. The answers are again null:

| Outcome (standardized) | ITT estimate | p |
|---|---|---|
| Grain per member-month, subsidised cards | −0.038 | .20 |
| Same, 2019 only (pre-PMGKAY) | −0.034 | .31 |
| Grain per card-month, all cards | −0.003 | .94 |
| Cards per 100 electoral-roll households | −0.039 | .42 |
| Share of roll households holding a card | −0.015 | .55 |

In kilograms, the grain estimate is −0.02 kg per member-month on a 5.01 kg base, with a confidence interval that excludes changes beyond about 1%. Reservation history (2005-2015) shows nothing either, so this is not a lag story. The coverage outcomes come in two flavors because the linkage-based one (share of roll households with a matched card) conflates coverage with linkage recall; the count ratio (cards per 100 roll households) needs no person linkage at all, and both are flat. One nominal hit appears in the non-experimental open-seat arm (grain per card, p = .005); it has no counterpart in the ITT and we read it as noise.

Estimates live in `data/audit/04a_itt_estimates.csv`, `04b_open_seat_estimates.csv`, `04c_placebo_estimates.csv`, and `04c_component_qvalues.csv`; formatted tables in `tabs/` (leakage: `itt_main.tex`, access: `access_main.tex`).

## Research design

**Treatment.** Two arms, honestly labeled. Arm 1 is intent-to-treat: the GP's pradhan seat was reserved for a woman in 2020, an assignment rotated within samiti and caste stratum, so the comparison is as good as random conditional on those strata. Arm 2 restricts to open seats and compares GPs where a woman won to GPs where a man did; women win 12% of open seats, and who wins is not random, so this arm is conditional on observables (census covariates, full reservation history, seat caste category) and is reported with coefficient-stability checks across control sets. A legacy-dose term (reservations 2005-2015) separates the sitting pradhan from persistence of past exposure.

**Outcomes.** All are built from administrative data, at the GP level, standardized, and combined into an Anderson inverse-covariance-weighted index:

| Outcome | Construction |
|---|---|
| Duplicate identities | +0.019 | .49 | .55 |
| Photo reuse | −0.022 | .52 |  |
| Excess ghosts | Card adults (25-70) with no counterpart in the 2018 electoral rolls via the [milaan_raj](../milaan_raj) person linkage, minus the same GP's absence rate for male household heads (30-60), which nets out linkage recall |
| Dead souls | Cards listing a member aged 85+ |
| Targeting discretion | −0.021 | .59 |  |
| Delivery regularity | Share of subsidised cards served in 10+ of the last 12 months (reversed) |
| Ghost offtake | Grain drawn by duplicate- or photo-flagged subsidised cards, per card |
| No-transaction cards | Subsidised cards with no bills at all |

**Geography.** PDS panchayats map to LGD GP codes through the transliteration-and-skeleton cascade built in milaan_raj (85% of cards bridge cleanly); reservation histories and election-to-LGD links come directly from [local_elections_rajasthan](https://github.com/in-rolls/local_elections_rajasthan).

## Data

Nothing large is committed; `data/audit/` holds aggregate audit CSVs without personal data, and `data/sources.json` pins the shared inputs.

| Source | Contents | How to obtain |
|---|---|---|
| Harvard Dataverse [doi:10.7910/DVN/FIFZEX](https://doi.org/10.7910/DVN/FIFZEX) | 2021 Rajasthan PDS: transactions (9.5 GB, five parts) | `Rscript scripts/01a_download_transactions.R` |
| [in-rolls/jaali](https://github.com/in-rolls/jaali) | Card CSVs, photo-hash manifest, forensic outputs | Clone as a sibling directory |
| milaan_raj | Panchayat-to-GP bridge; ration-to-rolls person links | Sibling directory; see its README |
| [local_elections_rajasthan](https://github.com/in-rolls/local_elections_rajasthan) | Canonical 2005–2020 election panel and LGD bridge | Immutable revision and SHA-256 in `data/sources.json` |
| [quota_raj](https://github.com/in-rolls/quota_raj) | Census covariates by LGD code | Pinned `50fbe05` reference; only Census columns are read |

Scale: 15.97M rural cards, 62.8M members, 13.6M cards bridged to 4,165 analysis GPs (49% reserved in 2020), 12.9M cards with transactions collapsed from 200M+ bills to card-month and card level (`data/transactions/bills.parquet` retains bill dates and grain quantities for month-level work, such as testing for electoral cycles in offtake).

## Reproduction

```bash
git clone https://github.com/in-rolls/pds_pradhan
cd pds_pradhan && Rscript -e 'renv::restore()'
export DATAVERSE_KEY=<your token>   # optional, files are public
Rscript scripts/99_run_all.R
```

Sibling directories expected at `../jaali` and `../milaan_raj` (paths overridable via `JAALI_DIR` and `MILAAN_DIR`). The provenance stage also compares vendored utility functions with `../quota_shaadi` (`QUOTA_SHAADI_DIR`); election data do not depend on its snapshots. Shared inputs resolve to `INDIA_DATA_HOME/{provider}/{ref}/{relative_path}`, with `INDIA_DATA_HOME` defaulting to `~/data`. A sibling file is used only if its SHA-256 matches; otherwise the immutable GitHub revision is downloaded, verified, and installed in the cache. Budget roughly 30 GB of transient disk and an hour, most of it the transaction download and scan. Every matching and construction stage writes an audit CSV to `data/audit/`.

The canonical-input migration removes LGD 42097: its election name tied with a competing GP in the geographic match, so the shared bridge leaves that link unresolved. This drops 1,490 cards and one analysis GP. Among the 4,728 shared treatment GPs, 57 previously unknown 2020 winner-sex values become observed. The pinned Census reference also supplies mean village-to-town distance; the earlier snapshot summed distances, changing this control in 3,967 GPs. Reservation histories and the other model controls are unchanged for shared GPs. Rebuilding outcomes and all models gives a corruption-index ITT of −0.0262 (p = .539; 1,879 observations; 1,000-draw RI p = .519) and a fully controlled open-seat estimate of 0.1449 (p = .126; 921 observations).

After preparing inputs, run `Rscript scripts/98_validate.R` for source checks and join invariants, and `Rscript -e 'lintr::lint_dir("scripts")'` for correctness linting. The full runner includes validation.

## Caveats

- The PDS snapshot is from 2021 and the treatment cohort took office in 2020, so the design estimates roughly one year of a pradhan's influence on stock measures (card composition accumulates over years) and one year of flow measures (transactions).
- Transaction-period outcomes overlap COVID-era free-grain schemes; month fixed effects and the audited month series (`data/audit/02a_month_series.csv`) address levels, and the 2019-only regularity measure is available as robustness.
- The ghost outcome exists only for the 2,894 GPs that bridge to both the PDS and the electoral rolls; its benchmark-differencing removes GP-level linkage recall but not member-level idiosyncrasies.
- Arm 2 (open-seat winners) is not experimental. It is reported because the conditional-on-observables comparison is the question many readers will ask; its nulls are consistent with Arm 1's.

## Related work

Chattopadhyay and Duflo (2004, *Econometrica*) established that women pradhans change public-goods allocation; Beaman et al. (2012, *Science*) argued that exposure to them changes aspirations. This repository asks the governance-integrity question at administrative scale and finds that on PDS leakage, at least in Rajasthan circa 2021, the gender of the pradhan makes no detectable difference, while the leakage itself is easy to detect.
