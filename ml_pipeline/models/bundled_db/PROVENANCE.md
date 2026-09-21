# Model retrained from the bundled database (2026-09-20)

Trained by `export_from_bundled_db` → `build_features random` →
`train_model random`, entirely from `mobile/assets/db/medguard.db`. No licensed
download was involved.

It exists because the backend needs *a* model to serve `/api/v1/predict`, and
the original training corpus (built from the full DrugBank XML) was lost. It is
**not** the model the dissertation reports — those metrics are untouched in
`../test_metrics.json`.

## How it differs from the original

| | Original (DrugBank XML corpus) | This retrain (bundled DB) |
| --- | --- | --- |
| Training rows | 1,019,738 | 596,306 |
| Test rows | 218,518 | 127,782 |
| Winning algorithm | RandomForest | HistGradientBoosting |
| Accuracy | 0.8625 | 0.9120 |
| Macro F1 | 0.5938 | 0.6164 |
| AUC (macro OvR) | 0.9433 | 0.9834 |
| High-tier recall | 0.9104 | 0.9418 |
| **High-tier precision** | **0.6583** | **0.2544** |
| High-tier share of test set | 23.7% | 3.1% |
| Majority-class baseline accuracy | 0.7609 | 0.9685 |

**The headline numbers flatter it, and should not be quoted as an
improvement.** Accuracy and AUC rose because the shipped database is dominated
by moderate-tier pairs (825,030 of 851,868): guessing "moderate" alone scores
96.9%, which this model does not beat. What matters clinically is the last two
rows — high-tier precision fell from 0.66 to 0.25, so roughly three of every
four high-risk calls are false alarms, against a base rate of 3.1% rather than
the original 23.7%.

Two caveats worth carrying:

- The filename says `rf_` for compatibility with the deployed path, but the
  selected algorithm here is HistGradientBoosting.
- Spot check: Warfarin + Ibuprofen scores `moderate`, P(high) = 0.28. The rule
  database already grades that pair as high, and the rule database always wins,
  so the app is unaffected — but it shows this model is weaker at the tier that
  matters.

Everything in this directory belongs to the same run: the model, its
`feature_columns.json`, `drug_risk_lookup.json`, `enzyme_index.json`,
`pd_class_meta.json` and `nti_list.json`. Mixing them with the files in `../`
would silently score pairs against the wrong feature space.
