import pandas as pd
import requests
import time
import os
import json

RXNORM_API = "https://rxnav.nlm.nih.gov/REST"


def get_rxcui(drug_name, cache):
    if drug_name in cache:
        return cache[drug_name]

    try:
        r = requests.get(f"{RXNORM_API}/rxcui.json", params={"name": drug_name}, timeout=10)
        if r.status_code == 200:
            ids = r.json().get("idGroup", {}).get("rxnormId", [])
            if ids:
                cache[drug_name] = ids[0]
                return ids[0]

        r2 = requests.get(f"{RXNORM_API}/approximateTerm.json", params={"term": drug_name, "maxEntries": 1}, timeout=10)
        if r2.status_code == 200:
            candidates = r2.json().get("approximateGroup", {}).get("candidate", [])
            if candidates:
                rxcui = candidates[0].get("rxcui")
                if rxcui:
                    cache[drug_name] = rxcui
                    return rxcui
    except Exception:
        pass

    cache[drug_name] = None
    return None


if __name__ == "__main__":
    processed_dir = "ml_pipeline/data/processed"
    cache_file = f"{processed_dir}/rxnorm_cache.json"

    print("Loading parsed drugs...")
    drugs = pd.read_csv(f"{processed_dir}/drugs_raw.csv")

    # Only normalize approved drugs
    approved = drugs[drugs["groups"].str.contains("approved", case=False, na=False)].copy()
    print(f"Approved drugs to normalize: {len(approved)}")

    # Load cache
    cache = {}
    if os.path.exists(cache_file):
        with open(cache_file, "r") as f:
            cache = json.load(f)
        print(f"Loaded {len(cache)} cached lookups")

    found = 0
    rxcuis = []

    for i, row in approved.iterrows():
        name = row["name"]

        if (i + 1) % 100 == 0:
            print(f"  Processing {len(rxcuis)}/{len(approved)}... (found: {found})")
            with open(cache_file, "w") as f:
                json.dump(cache, f)

        rxcui = get_rxcui(name, cache)
        rxcuis.append(rxcui)
        if rxcui:
            found += 1

        time.sleep(0.06)

    approved["rxcui"] = rxcuis

    with open(cache_file, "w") as f:
        json.dump(cache, f, indent=2)

    approved.to_csv(f"{processed_dir}/drugs_normalized.csv", index=False)

    print("\nRxNorm normalization complete:")
    print(f"  Total: {len(approved)}")
    print(f"  Matched: {found} ({100 * found / len(approved):.1f}%)")
    print(f"  Unmatched: {len(approved) - found}")
    print(f"Saved to {processed_dir}/drugs_normalized.csv")