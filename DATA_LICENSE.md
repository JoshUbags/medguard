# Data licence

The clinical data in this repository, and the models trained on it, are
licensed under the
[Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-nc-sa/4.0/)
licence (CC BY-NC-SA 4.0). The source code is under the Apache License 2.0 —
see [LICENSE](LICENSE).

## What this covers

| Path | What it is |
| --- | --- |
| `mobile/assets/db/medguard.db` | The bundled clinical database |
| `mobile/assets/ml/` | The on-device severity model |
| `ml_pipeline/models/` | Trained models and their metadata |
| `ml_pipeline/data/external/ddinter/` | DDInter 2.0 source files |

It also covers the app release builds on the GitHub Releases page, which
contain the bundled database.

## What you may do

- **Share** — copy and redistribute the material in any medium or format.
- **Adapt** — remix, transform and build upon it.

Under these conditions:

- **Attribution** — credit MedGuard and the upstream sources below, and
  indicate if changes were made.
- **NonCommercial** — no commercial use.
- **ShareAlike** — adaptations must be distributed under this same licence.

## Why this licence

It is the most permissive licence the upstream data allows:

| Source | Licence | Citation |
| --- | --- | --- |
| DrugBank 6.0 | CC BY-NC 4.0 | Knox C, *et al.* *Nucleic Acids Res* 52(D1):D1265–D1275, 2024. [doi:10.1093/nar/gkad976](https://doi.org/10.1093/nar/gkad976) |
| DDInter 2.0 | CC BY-NC-SA 4.0 | Tian Y, *et al.* *Nucleic Acids Res* 53(D1):D1356–D1362, 2025. [doi:10.1093/nar/gkae726](https://doi.org/10.1093/nar/gkae726) |
| RxNorm | U.S. National Library of Medicine | Drug identifiers, via the RxNav API |
| openFDA | Public domain | U.S. Food and Drug Administration |

DDInter's ShareAlike term carries through to the combined database, and
DrugBank's NonCommercial term rules out commercial use. A commercial product
would need a commercial licence from each upstream provider.
