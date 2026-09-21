import pandas as pd
import requests
import time


def get_coreport_count(drug_a, drug_b):
    try:
        query = f'patient.drug.openfda.generic_name:"{drug_a}"+AND+patient.drug.openfda.generic_name:"{drug_b}"'
        r = requests.get(f"https://api.fda.gov/drug/event.json?search={query}&limit=1", timeout=15)
        if r.status_code == 200:
            return r.json().get("meta", {}).get("results", {}).get("total", 0)
        return 0
    except Exception:
        return 0


if __name__ == "__main__":
    processed_dir = "ml_pipeline/data/processed"

    print("Loading classified interactions...")
    interactions = pd.read_csv(f"{processed_dir}/interactions_classified.csv")

    # Query a sample (top 500 by severity)
    interactions = interactions.sort_values("severity_int", ascending=False)
    sample = interactions.head(500).copy()

    print(f"Querying OpenFDA for {len(sample)} pairs...")

    counts = []
    for i, row in sample.iterrows():
        if (len(counts) + 1) % 50 == 0:
            print(f"  Processing {len(counts) + 1}/{len(sample)}...")
        counts.append(get_coreport_count(row["drug_a_name"], row["drug_b_name"]))
        time.sleep(0.3)

    sample["openfda_coreport_count"] = counts

    interactions = interactions.merge(
        sample[["drug_a_id", "drug_b_id", "openfda_coreport_count"]],
        on=["drug_a_id", "drug_b_id"],
        how="left"
    )
    interactions["openfda_coreport_count"] = interactions["openfda_coreport_count"].fillna(0).astype(int)

    interactions.to_csv(f"{processed_dir}/interactions_enriched.csv", index=False)

    enriched = (interactions["openfda_coreport_count"] > 0).sum()
    print(f"\nDone. {enriched} pairs had OpenFDA co-reports.")
    print(f"Saved to {processed_dir}/interactions_enriched.csv")