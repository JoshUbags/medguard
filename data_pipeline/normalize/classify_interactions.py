"""Severity, mechanism and clinical-effect classification for DrugBank pairs.

Severity is derived from the clinical EFFECT named in each interaction
description, scanned in priority order (most dangerous first). DrugBank's free
descriptions are templated ("The risk or severity of <EFFECT> can be increased
when X is combined with Y"), and the effect is the clinically meaningful part.

This replaces an earlier classifier that matched a short, brittle keyword list
and defaulted ~96% of pairs to "moderate" -- which mislabelled genuinely
serious effects (CNS depression, QTc prolongation, bleeding, hyperkalemia,
serotonin syndrome) as moderate. Those now map to "major".

`classify_severity` returns the label; `severity_provenance` returns how the
label was decided (serious_kw / minor_kw / named_effect / pharmacokinetic /
default) so the labelling is transparent and auditable in the methodology
chapter. Where DDInter 2.0 expert ratings are available for a pair, they should
override this heuristic (see scripts/merge_ddinter.py).
"""

import re

import pandas as pd

# --- Severity keyword sets, scanned in priority order (most severe first) ---

_CONTRA = [
    "contraindicated", "must not be used", "do not use together",
    "should not be combined", "fatal", "life-threatening", "life threatening",
    "lethal", " death", "deadly",
]

_MAJOR = [
    # neuro / serotonergic
    "serotonin syndrome", "serotonin", "serotonergic", "neuroleptic malignant",
    "malignant hyperthermia", "seizure", "convuls", "extrapyramidal",
    # cardiac
    "qt prolong", "qtc prolong", "qt interval", "torsade", "ventricular",
    "arrhythmia", "cardiac arrest",
    # bleeding
    "bleed", "hemorrhag", "haemorrhag",
    # respiratory / CNS
    "cns depression", "central nervous system depression", "respiratory depression",
    # haematologic
    "methemoglobin", "methaemoglobin", "agranulocytosis", "neutropenia",
    "thrombocytopenia", "pancytopenia", "bone marrow", "aplastic",
    # renal / hepatic / metabolic
    "hyperkalemia", "hyperkalaemia", "nephrotox", "renal failure",
    "acute kidney", "kidney injury", "hepatotox", "liver failure",
    "hepatic failure", "lactic acidosis", "pancreatitis",
    # musculoskeletal
    "rhabdomyolysis", "myoglobinuria", "myopathy", "neuromuscular blockade",
    # vascular / immune
    "thrombosis", "thromboembol", "embolism", "stroke", "angioedema",
    "anaphyl", "immunosuppress", "hypertensive crisis", "hypertensive emergency",
    "ototox",
]

_MINOR = [
    "mild", "slight", "minor", "minimal", "negligible", "weak", "marginal",
    "trivial", "clinically insignificant", "not clinically significant",
    "no clinically significant",
]

_EFFECT_RE = re.compile(r"the risk or severity of (.+?) can be (?:increased|decreased) when")
_PK_MARKERS = (
    "serum concentration", "metabolism", "excretion", "therapeutic efficacy",
    "absorption", "activities of",
)

SEVERITY_MAP = {"minor": 0, "moderate": 1, "major": 2, "contraindicated": 3}


def classify_severity(description) -> str:
    """Return one of: minor, moderate, major, contraindicated."""
    if not description or not isinstance(description, str):
        return "moderate"
    text = description.lower()
    for kw in _CONTRA:
        if kw in text:
            return "contraindicated"
    for kw in _MAJOR:
        if kw in text:
            return "major"
    for kw in _MINOR:
        if kw in text:
            return "minor"
    return "moderate"


def severity_provenance(description) -> str:
    """How the severity label was decided (for auditability)."""
    if not description or not isinstance(description, str):
        return "default"
    text = description.lower()
    if any(kw in text for kw in _CONTRA):
        return "serious_kw"
    if any(kw in text for kw in _MAJOR):
        return "serious_kw"
    if any(kw in text for kw in _MINOR):
        return "minor_kw"
    if _EFFECT_RE.search(text):
        return "named_effect"
    if any(m in text for m in _PK_MARKERS):
        return "pharmacokinetic"
    return "default"


def extract_mechanism(description):
    if not description or not isinstance(description, str):
        return "Pharmacological interaction"

    text = description.lower()

    mechanisms = {
        "CYP enzyme inhibition": ["inhibit", "cyp"],
        "CYP enzyme induction": ["induc", "cyp"],
        "Increased serum concentration": ["increase", "serum concentration"],
        "Decreased serum concentration": ["decrease", "serum concentration"],
        "Increased risk of bleeding": ["bleed"],
        "QT prolongation": ["qt", "prolong"],
        "Serotonin syndrome risk": ["serotonin"],
        "CNS depression": ["cns", "depress"],
        "Nephrotoxicity risk": ["nephrotox"],
        "Hepatotoxicity risk": ["hepatotox"],
        "Electrolyte imbalance": ["potassium", "electrolyte", "hypokalemia"],
        "Altered absorption": ["absorpt"],
    }

    for mechanism, keywords in mechanisms.items():
        if all(re.search(kw, text) for kw in keywords):
            return mechanism

    if "increase" in text and ("effect" in text or "concentration" in text or "level" in text or "activity" in text):
        return "Increased effect/concentration"
    if "decrease" in text and ("effect" in text or "concentration" in text or "level" in text or "activity" in text):
        return "Decreased effect/concentration"
    if "enhance" in text:
        return "Enhanced effect"
    if "reduce" in text or "diminish" in text:
        return "Reduced effect"
    if "additive" in text or "synergist" in text:
        return "Additive effect"
    if "antagoni" in text:
        return "Antagonistic effect"

    return "Pharmacological interaction"


def extract_clinical_effect(description):
    """Extract a short plain-English clinical effect for the app's result screen."""
    if not description or not isinstance(description, str):
        return None

    text = description.lower()

    effects = {
        "Increased risk of bleeding": ["bleed", "hemorrhag"],
        "Risk of serotonin syndrome": ["serotonin syndrome"],
        "Risk of QT prolongation and cardiac arrhythmia": ["qt prolong"],
        "Excessive sedation and CNS depression": ["cns depress", "sedat"],
        "Risk of kidney damage": ["nephrotox", "renal"],
        "Risk of liver damage": ["hepatotox", "liver"],
        "Dangerously low blood pressure": ["hypotension"],
        "Risk of seizures": ["seizure"],
        "Dangerously low blood sugar": ["hypoglycemia", "blood sugar"],
        "Muscle damage (rhabdomyolysis)": ["rhabdomyolysis"],
        "Electrolyte imbalance": ["hypokalemia", "hyperkalemia", "electrolyte"],
        "Reduced drug effectiveness": ["decrease.*effect", "reduce.*efficacy", "diminish"],
        "Increased drug toxicity": ["toxic", "increase.*concentration"],
    }

    for effect, keywords in effects.items():
        for kw in keywords:
            if re.search(kw, text):
                return effect

    return "Potential interaction — consult pharmacist"


def deduplicate_interactions(df):
    df["pair_key"] = df.apply(
        lambda row: tuple(sorted([str(row["drug_a_id"]), str(row["drug_b_id"])])),
        axis=1
    )
    df["desc_len"] = df["description"].fillna("").str.len()
    deduped = df.sort_values("desc_len", ascending=False).drop_duplicates(
        subset="pair_key", keep="first"
    )
    deduped = deduped.drop(columns=["pair_key", "desc_len"])
    return deduped.reset_index(drop=True)


if __name__ == "__main__":
    processed_dir = "ml_pipeline/data/processed"

    print("Loading raw interactions...")
    interactions = pd.read_csv(f"{processed_dir}/interactions_raw.csv")
    print(f"  Raw entries: {len(interactions)}")

    print("Deduplicating (removing A-B / B-A mirrors)...")
    interactions = deduplicate_interactions(interactions)
    print(f"  Unique pairs: {len(interactions)}")

    print("Classifying severity (clinical effect mapping)...")
    interactions["severity"] = interactions["description"].apply(classify_severity)
    interactions["severity_provenance"] = interactions["description"].apply(severity_provenance)
    interactions["mechanism"] = interactions["description"].apply(extract_mechanism)
    interactions["clinical_effect"] = interactions["description"].apply(extract_clinical_effect)
    interactions["severity_int"] = interactions["severity"].map(SEVERITY_MAP)

    print("\nSeverity distribution:")
    print(interactions["severity"].value_counts().to_string())
    print("\nLabel provenance:")
    print(interactions["severity_provenance"].value_counts().to_string())

    interactions.to_csv(f"{processed_dir}/interactions_classified.csv", index=False)
    print(f"\nSaved to {processed_dir}/interactions_classified.csv ({len(interactions)} rows)")
