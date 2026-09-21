"""Mechanistic feature engineering for the MedGuard severity model.

Rebuilds the interaction-severity feature matrix with a richer, clinically
grounded feature set, all computable from the *bundled* data (so on-device
parity holds), plus explicit missing-data indicators. It also produces TWO
evaluation regimes so generalisation can be reported honestly:

  * ``random``    — stratified 70/15/15 split of pairs (transductive; a drug can
                    appear in train and test — matches the original pipeline).
  * ``coldstart`` — drug-disjoint split: 15% of *drugs* are held out; test pairs
                    involve >=1 held-out drug (inductive; the "new drug" case).

Drug-level risk features are computed from each regime's TRAIN split only.

Output dir is taken from env RETRAIN_OUT (default: ml_pipeline/data/interim/retrain).
Run one regime per process (memory-frugal on small boxes)::

    RETRAIN_OUT=/path python3 ml_pipeline/src/features/build_features.py random
    RETRAIN_OUT=/path python3 ml_pipeline/src/features/build_features.py coldstart
"""

from __future__ import annotations

import gc
import json
import os
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[3]
PROCESSED = ROOT / "ml_pipeline" / "data" / "processed"
OUT = Path(os.environ.get("RETRAIN_OUT", str(ROOT / "ml_pipeline" / "data" / "interim" / "retrain")))
OUT.mkdir(parents=True, exist_ok=True)

RANDOM_STATE = 42
SMOOTHING = 20
HIGH_TIER_INTS = {2, 3}
TOP_ENZYMES_K = 24

NTI_NAMES = {
    "warfarin", "digoxin", "lithium", "phenytoin", "carbamazepine",
    "theophylline", "levothyroxine", "cyclosporine", "ciclosporin",
    "tacrolimus", "sirolimus", "everolimus", "valproic", "valproate",
    "gentamicin", "tobramycin", "amikacin", "vancomycin", "procainamide",
    "quinidine", "flecainide", "clozapine", "phenobarbital", "primidone",
    "aminophylline", "acenocoumarol",
}

PD_ATC_PREFIXES: dict[str, tuple[str, ...]] = {
    "anticoagulant":  ("B01AA", "B01AB", "B01AE", "B01AF", "B01AX"),
    "antiplatelet":   ("B01AC",),
    "nsaid":          ("M01A", "N02BA"),
    "qt_prolong":     ("C01BA", "C01BC", "C01BD", "J01FA", "J01MA",
                       "N05AA", "N05AH", "A04AA", "N07BC02"),
    "serotonergic":   ("N06AB", "N06AA", "N06AF", "N06AG", "N06AX",
                       "N02CC", "N02AX02", "J01XX08"),
    "cns_depressant": ("N02A", "N05BA", "N05CD", "N05CF", "N05CA", "N03AA",
                       "R06AA", "R06AD", "N05A", "N01AH"),
    "nephrotoxic":    ("J01GB", "M01A", "L04AD", "A07AA09"),
}
PD_NAME_KEYWORDS: dict[str, tuple[str, ...]] = {
    "serotonergic": ("tramadol", "linezolid", "sumatriptan", "fluoxetine",
                     "sertraline", "paroxetine", "venlafaxine", "duloxetine"),
    "cns_depressant": ("morphine", "oxycodone", "diazepam", "lorazepam",
                       "zolpidem", "phenobarbital", "codeine", "fentanyl"),
    "anticoagulant": ("warfarin", "heparin", "apixaban", "rivaroxaban",
                      "dabigatran", "enoxaparin"),
    "antiplatelet": ("aspirin", "clopidogrel", "ticagrelor", "prasugrel"),
    "nephrotoxic": ("gentamicin", "tobramycin", "amikacin", "vancomycin",
                    "cisplatin", "tenofovir"),
}
PD_GROUPS = list(PD_ATC_PREFIXES.keys())


def _half_life_hours(raw: object) -> float | None:
    if not isinstance(raw, str) or not raw:
        return None
    text = raw.lower()
    m = re.search(r"(\d+(?:\.\d+)?)(?:\s*[-–]\s*(\d+(?:\.\d+)?))?", text)
    if not m:
        return None
    low = float(m.group(1))
    high = float(m.group(2)) if m.group(2) else low
    avg = (low + high) / 2
    if "min" in text:
        return avg / 60
    if "day" in text:
        return avg * 24
    return avg


def _popcount(arr: np.ndarray, bits: int) -> np.ndarray:
    out = np.zeros(len(arr), dtype=np.int16)
    a = arr.astype(np.int64)
    for i in range(bits):
        out += ((a >> i) & 1).astype(np.int16)
    return out


def load_base_pairs() -> pd.DataFrame:
    cols = ["drug_a_id", "drug_b_id", "severity_int"]
    parts = [pd.read_csv(PROCESSED / f"{n}.csv", usecols=cols) for n in ("train", "val", "test")]
    df = pd.concat(parts, ignore_index=True)
    df["severity_int"] = df["severity_int"].fillna(1).astype(int)
    return df


def build_drug_tables() -> dict:
    drugs = pd.read_csv(PROCESSED / "drugs_normalized.csv", low_memory=False)
    enzymes = pd.read_csv(PROCESSED / "enzymes_raw.csv", low_memory=False)
    categories = pd.read_csv(PROCESSED / "categories_raw.csv", low_memory=False)

    drugs["name_l"] = drugs["name"].fillna("").str.lower()
    atc_all = drugs.set_index("drugbank_id")["all_atc_codes"].fillna("").to_dict()
    atc_primary = drugs.set_index("drugbank_id")["atc_code"].fillna("").to_dict()
    dtype = drugs.set_index("drugbank_id")["drug_type"].fillna("").to_dict()
    half_life = drugs.set_index("drugbank_id")["half_life"].map(_half_life_hours).to_dict()
    name_l = drugs.set_index("drugbank_id")["name_l"].to_dict()

    metab = enzymes[enzymes["enzyme_type"] == "enzymes"].copy()
    metab["enz"] = metab["gene_name"].fillna(metab["enzyme_name"]).fillna("")
    top = metab["enz"].value_counts().head(TOP_ENZYMES_K).index.tolist()
    enz_bit = {e: i for i, e in enumerate(top)}
    sub, inh, ind = {}, {}, {}
    for db, e, acts in zip(metab["drugbank_id"], metab["enz"], metab["actions"].fillna("")):
        if e not in enz_bit:
            continue
        bit = 1 << enz_bit[e]
        acts = str(acts)
        if "substrate" in acts:
            sub[db] = sub.get(db, 0) | bit
        if "inhibitor" in acts:
            inh[db] = inh.get(db, 0) | bit
        if "inducer" in acts:
            ind[db] = ind.get(db, 0) | bit

    cats = {db: set(g["category"].dropna().astype(str)) for db, g in categories.groupby("drugbank_id")}

    def atc_list(db: str) -> list[str]:
        codes = []
        if atc_primary.get(db):
            codes.append(atc_primary[db])
        allc = atc_all.get(db, "")
        if allc:
            codes.extend(c for c in re.split(r"[|,;\s]+", allc) if c)
        return codes

    pd_mask = {}
    for db in drugs["drugbank_id"]:
        codes = atc_list(db)
        nm = name_l.get(db, "")
        mask = 0
        for gi, g in enumerate(PD_GROUPS):
            hit = any(c.startswith(pref) for c in codes for pref in PD_ATC_PREFIXES[g])
            if not hit and g in PD_NAME_KEYWORDS:
                hit = any(kw in nm for kw in PD_NAME_KEYWORDS[g])
            if hit:
                mask |= (1 << gi)
        pd_mask[db] = mask

    nti = {db: int(any(k in name_l.get(db, "") for k in NTI_NAMES)) for db in drugs["drugbank_id"]}
    return {"atc_primary": atc_primary, "dtype": dtype, "half_life": half_life,
            "cats": cats, "sub": sub, "inh": inh, "ind": ind,
            "enz_bit": enz_bit, "pd_mask": pd_mask, "nti": nti}


def compute_features(pairs: pd.DataFrame, T: dict) -> pd.DataFrame:
    a = pairs["drug_a_id"].to_numpy()
    b = pairs["drug_b_id"].to_numpy()
    df = pairs[["drug_a_id", "drug_b_id", "severity_int"]].copy()

    atc = T["atc_primary"]
    atc_a = np.array([atc.get(x, "") for x in a])
    atc_b = np.array([atc.get(x, "") for x in b])
    for n in (1, 3, 4, 5):
        pa = np.array([s[:n] if len(s) >= n else "" for s in atc_a])
        pb = np.array([s[:n] if len(s) >= n else "" for s in atc_b])
        df[f"atc_overlap_{n}"] = ((pa == pb) & (pa != "")).astype(np.int8)
    df["atc_missing_either"] = (((atc_a == "") | (atc_b == ""))).astype(np.int8)

    sub, inh, ind = T["sub"], T["inh"], T["ind"]
    sa = np.array([sub.get(x, 0) for x in a]); sb = np.array([sub.get(x, 0) for x in b])
    ia = np.array([inh.get(x, 0) for x in a]); ib = np.array([inh.get(x, 0) for x in b])
    da = np.array([ind.get(x, 0) for x in a]); dbb = np.array([ind.get(x, 0) for x in b])
    K = len(T["enz_bit"])
    df["shared_cyp_count"] = _popcount(sa & sb, K)
    df["inhibitor_substrate_count"] = (_popcount(ia & sb, K) + _popcount(ib & sa, K)).astype(np.int16)
    df["inducer_substrate_count"] = (_popcount(da & sb, K) + _popcount(dbb & sa, K)).astype(np.int16)
    df["both_substrates"] = (df["shared_cyp_count"] > 0).astype(np.int8)
    df["inhibitor_substrate"] = (df["inhibitor_substrate_count"] > 0).astype(np.int8)
    df["inducer_substrate"] = (df["inducer_substrate_count"] > 0).astype(np.int8)

    cats = T["cats"]
    df["category_overlap"] = np.array(
        [len(cats.get(x, set()) & cats.get(y, set())) for x, y in zip(a, b)], dtype=np.int16)

    dt = T["dtype"]
    ta = np.array([dt.get(x, "") for x in a]); tb = np.array([dt.get(x, "") for x in b])
    df["drug_type_match"] = (((ta == tb) & (ta != ""))).astype(np.int8)

    hl = T["half_life"]
    ha = np.array([hl.get(x, np.nan) for x in a], dtype=float)
    hb = np.array([hl.get(x, np.nan) for x in b], dtype=float)
    ratio = np.zeros(len(df), dtype=np.float32)
    mask = np.isfinite(ha) & np.isfinite(hb) & (ha > 0) & (hb > 0)
    ratio[mask] = np.log(np.maximum(ha[mask], hb[mask]) / np.minimum(ha[mask], hb[mask])).astype(np.float32)
    df["half_life_ratio"] = ratio
    df["half_life_missing"] = (~mask).astype(np.int8)

    pdm = T["pd_mask"]
    ma = np.array([pdm.get(x, 0) for x in a]); mb = np.array([pdm.get(x, 0) for x in b])
    gi = {g: i for i, g in enumerate(PD_GROUPS)}
    def both(g): return (((ma >> gi[g]) & 1) & ((mb >> gi[g]) & 1)).astype(np.int8)
    df["both_qt_prolong"] = both("qt_prolong")
    df["both_serotonergic"] = both("serotonergic")
    df["both_cns_depressant"] = both("cns_depressant")
    df["both_nephrotoxic"] = both("nephrotoxic")
    bleed_a = ((ma >> gi["anticoagulant"]) & 1) + ((ma >> gi["antiplatelet"]) & 1) + ((ma >> gi["nsaid"]) & 1)
    bleed_b = ((mb >> gi["anticoagulant"]) & 1) + ((mb >> gi["antiplatelet"]) & 1) + ((mb >> gi["nsaid"]) & 1)
    df["bleeding_risk_combo"] = (((bleed_a >= 1) & (bleed_b >= 1))).astype(np.int8)

    nti = T["nti"]
    na = np.array([nti.get(x, 0) for x in a]); nb = np.array([nti.get(x, 0) for x in b])
    df["nti_either"] = ((na | nb)).astype(np.int8)
    df["nti_both"] = ((na & nb)).astype(np.int8)
    return df


def risk_lookup(train_df, out_dir: Path):
    y = train_df["severity_int"].isin(HIGH_TIER_INTS).astype(int).values
    global_rate = float(y.mean())
    stacked = pd.DataFrame({
        "id": np.concatenate([train_df["drug_a_id"].values, train_df["drug_b_id"].values]),
        "y": np.concatenate([y, y]),
    })
    agg = stacked.groupby("id")["y"].agg(["sum", "count"])
    risk = ((agg["sum"] + SMOOTHING * global_rate) / (agg["count"] + SMOOTHING)).to_dict()
    payload = {"global_high_rate": round(global_rate, 6), "global_dangerous_rate": round(global_rate, 6),
               "smoothing": SMOOTHING, "drug_risk": {k: round(float(v), 6) for k, v in risk.items()}}
    (out_dir / "drug_risk_lookup.json").write_text(json.dumps(payload))
    return risk, global_rate


def write_split(feats, index, risk, global_rate, path):
    part = feats.iloc[index].copy()
    ra = part["drug_a_id"].map(risk).fillna(global_rate).to_numpy(dtype=np.float32)
    rb = part["drug_b_id"].map(risk).fillna(global_rate).to_numpy(dtype=np.float32)
    part["drug_risk_a"] = ra
    part["drug_risk_b"] = rb
    part["drug_risk_prod"] = (ra * rb).astype(np.float32)
    part["drug_risk_max"] = np.maximum(ra, rb)
    part["drug_risk_min"] = np.minimum(ra, rb)
    part.to_parquet(path)
    n = len(part)
    del part
    gc.collect()
    return n


def main(regime: str) -> None:
    print(f"[{regime}] loading…", flush=True)
    pairs = load_base_pairs()
    T = build_drug_tables()
    print(f"pairs={len(pairs):,} enzymes={len(T['enz_bit'])} pd_groups={len(PD_GROUPS)}", flush=True)
    feats = compute_features(pairs, T)
    del pairs
    gc.collect()
    feat_only = [c for c in feats.columns if c not in ("drug_a_id", "drug_b_id", "severity_int")]
    print("base_features:", len(feat_only), feat_only, flush=True)

    rng = np.random.RandomState(RANDOM_STATE)
    sev = feats["severity_int"].values
    reg = OUT / regime
    reg.mkdir(parents=True, exist_ok=True)

    if regime == "random":
        order = np.arange(len(feats))
        tr, va, te = [], [], []
        for lbl in np.unique(sev):
            g = order[sev == lbl].copy(); rng.shuffle(g)
            n = len(g); a = int(n * 0.70); b = int(n * 0.85)
            tr.append(g[:a]); va.append(g[a:b]); te.append(g[b:])
        tr, va, te = np.concatenate(tr), np.concatenate(va), np.concatenate(te)
    elif regime == "coldstart":
        drugs_all = pd.unique(feats[["drug_a_id", "drug_b_id"]].values.ravel())
        held = set(rng.choice(drugs_all, size=int(len(drugs_all) * 0.15), replace=False))
        both_seen = (~feats["drug_a_id"].isin(held).values) & (~feats["drug_b_id"].isin(held).values)
        seen = np.where(both_seen)[0]; new = np.where(~both_seen)[0]
        rng.shuffle(seen)
        cut = int(len(seen) * 0.9)
        tr, va, te = seen[:cut], seen[cut:], new
        (reg / "held_drugs.json").write_text(json.dumps(sorted(held)))
    else:
        raise SystemExit(f"unknown regime {regime}")

    risk, gr = risk_lookup(feats.iloc[tr], reg)
    n_tr = write_split(feats, tr, risk, gr, reg / "train.parquet")
    n_va = write_split(feats, va, risk, gr, reg / "val.parquet")
    n_te = write_split(feats, te, risk, gr, reg / "test.parquet")
    print(f"[{regime}] train={n_tr:,} val={n_va:,} test={n_te:,}", flush=True)

    feature_cols = feat_only + ["drug_risk_a", "drug_risk_b", "drug_risk_prod", "drug_risk_max", "drug_risk_min"]
    (reg / "feature_columns.json").write_text(json.dumps(feature_cols))
    (OUT / "enzyme_index.json").write_text(json.dumps(T["enz_bit"]))
    (OUT / "pd_class_meta.json").write_text(json.dumps({"groups": PD_GROUPS, "atc_prefixes": PD_ATC_PREFIXES, "name_keywords": PD_NAME_KEYWORDS}))
    (OUT / "nti_list.json").write_text(json.dumps(sorted(NTI_NAMES)))
    print(f"DONE [{regime}] features={len(feature_cols)}", flush=True)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "random")
