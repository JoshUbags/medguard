import xml.etree.ElementTree as ET
import pandas as pd
import os
import sys

NS = "{http://www.drugbank.ca}"


def parse_drugbank(xml_path):
    print("Loading DrugBank XML... (this may take a few minutes)")
    tree = ET.parse(xml_path)
    root = tree.getroot()

    drugs_list = []
    synonyms_list = []
    interactions_list = []
    enzymes_list = []
    categories_list = []

    all_drugs = root.findall(f"{NS}drug")
    total = len(all_drugs)
    print(f"Found {total} drugs. Parsing...")

    for i, drug in enumerate(all_drugs):
        if (i + 1) % 500 == 0:
            print(f"  Processing drug {i + 1}/{total}...")

        drug_type = drug.attrib.get("type", "unknown")

        # Primary DrugBank ID
        dbid = drug.find(f"{NS}drugbank-id")
        if dbid is None:
            continue
        drugbank_id = dbid.text

        # Secondary IDs
        all_ids = drug.findall(f"{NS}drugbank-id")
        secondary_ids = [d.text for d in all_ids[1:] if d.text]

        # Name
        name_el = drug.find(f"{NS}name")
        name = name_el.text if name_el is not None else None
        if not name:
            continue

        # Description
        desc_el = drug.find(f"{NS}description")
        description = desc_el.text.strip() if (desc_el is not None and desc_el.text) else None

        # CAS number
        cas_el = drug.find(f"{NS}cas-number")
        cas_number = cas_el.text if cas_el is not None else None

        # Average mass
        mass_el = drug.find(f"{NS}average-mass")
        avg_mass = mass_el.text if mass_el is not None else None

        # State
        state_el = drug.find(f"{NS}state")
        state = state_el.text if state_el is not None else None

        # Indication
        ind_el = drug.find(f"{NS}indication")
        indication = ind_el.text.strip() if (ind_el is not None and ind_el.text) else None

        # Pharmacodynamics
        pd_el = drug.find(f"{NS}pharmacodynamics")
        pharmacodynamics = pd_el.text.strip() if (pd_el is not None and pd_el.text) else None

        # Mechanism of action
        moa_el = drug.find(f"{NS}mechanism-of-action")
        mechanism_of_action = moa_el.text.strip() if (moa_el is not None and moa_el.text) else None

        # Absorption
        abs_el = drug.find(f"{NS}absorption")
        absorption = abs_el.text.strip() if (abs_el is not None and abs_el.text) else None

        # Half life
        hl_el = drug.find(f"{NS}half-life")
        half_life = hl_el.text.strip() if (hl_el is not None and hl_el.text) else None

        # Toxicity
        tox_el = drug.find(f"{NS}toxicity")
        toxicity = tox_el.text.strip() if (tox_el is not None and tox_el.text) else None

        # Food interactions
        food_el = drug.find(f"{NS}food-interactions")
        food_interactions = []
        if food_el is not None:
            for fi in food_el.findall(f"{NS}food-interaction"):
                if fi.text:
                    food_interactions.append(fi.text.strip())

        # ATC codes
        atc_codes_el = drug.find(f"{NS}atc-codes")
        atc_codes = []
        if atc_codes_el is not None:
            for atc in atc_codes_el.findall(f"{NS}atc-code"):
                code = atc.attrib.get("code")
                if code:
                    atc_codes.append(code)
        primary_atc = atc_codes[0] if atc_codes else None

        # Groups
        groups_el = drug.find(f"{NS}groups")
        groups = []
        if groups_el is not None:
            groups = [g.text for g in groups_el.findall(f"{NS}group") if g.text]

        # ── CATEGORIES ──
        categories_el = drug.find(f"{NS}categories")
        drug_class = None
        if categories_el is not None:
            for cat_el in categories_el.findall(f"{NS}category"):
                cat_name_el = cat_el.find(f"{NS}category")
                mesh_id_el = cat_el.find(f"{NS}mesh-id")
                if cat_name_el is not None and cat_name_el.text:
                    cat_name = cat_name_el.text
                    if drug_class is None:
                        drug_class = cat_name
                    categories_list.append({
                        "drugbank_id": drugbank_id,
                        "drug_name": name,
                        "category": cat_name,
                        "mesh_id": mesh_id_el.text if mesh_id_el is not None else None,
                    })

        # ── ENZYMES, CARRIERS, TRANSPORTERS, TARGETS ──
        for enzyme_type in ["enzymes", "carriers", "transporters", "targets"]:
            container = drug.find(f"{NS}{enzyme_type}")
            if container is None:
                continue

            if enzyme_type == "enzymes":
                tag = "enzyme"
            elif enzyme_type == "carriers":
                tag = "carrier"
            elif enzyme_type == "transporters":
                tag = "transporter"
            else:
                tag = "target"

            for entity in container.findall(f"{NS}{tag}"):
                ent_name_el = entity.find(f"{NS}name")
                ent_id_el = entity.find(f"{NS}id")
                gene_el = entity.find(f"{NS}gene-name")

                actions_el = entity.find(f"{NS}actions")
                actions = []
                if actions_el is not None:
                    actions = [a.text for a in actions_el.findall(f"{NS}action") if a.text]

                known_action_el = entity.find(f"{NS}known-action")
                known_action = known_action_el.text if known_action_el is not None else None

                if ent_name_el is not None and ent_name_el.text:
                    enzymes_list.append({
                        "drugbank_id": drugbank_id,
                        "drug_name": name,
                        "enzyme_type": enzyme_type,
                        "enzyme_name": ent_name_el.text,
                        "enzyme_id": ent_id_el.text if ent_id_el is not None else None,
                        "gene_name": gene_el.text if gene_el is not None else None,
                        "actions": "|".join(actions) if actions else None,
                        "known_action": known_action,
                    })

        # ── DRUGS TABLE ──
        drugs_list.append({
            "drugbank_id": drugbank_id,
            "secondary_ids": "|".join(secondary_ids) if secondary_ids else None,
            "name": name,
            "drug_type": drug_type,
            "description": description,
            "cas_number": cas_number,
            "average_mass": avg_mass,
            "state": state,
            "indication": indication,
            "pharmacodynamics": pharmacodynamics,
            "mechanism_of_action": mechanism_of_action,
            "absorption": absorption,
            "half_life": half_life,
            "toxicity": toxicity,
            "food_interactions": "|".join(food_interactions) if food_interactions else None,
            "atc_code": primary_atc,
            "all_atc_codes": "|".join(atc_codes) if atc_codes else None,
            "drug_class": drug_class,
            "groups": "|".join(groups),
        })

        # ── SYNONYMS ──
        synonyms_el = drug.find(f"{NS}synonyms")
        if synonyms_el is not None:
            for syn in synonyms_el.findall(f"{NS}synonym"):
                if syn.text:
                    synonyms_list.append({
                        "drugbank_id": drugbank_id,
                        "drug_name": name,
                        "synonym": syn.text,
                        "source": "drugbank_synonym",
                    })

        # International brands
        brands_el = drug.find(f"{NS}international-brands")
        if brands_el is not None:
            for brand in brands_el.findall(f"{NS}international-brand"):
                brand_name = brand.find(f"{NS}name")
                if brand_name is not None and brand_name.text:
                    synonyms_list.append({
                        "drugbank_id": drugbank_id,
                        "drug_name": name,
                        "synonym": brand_name.text,
                        "source": "drugbank_brand",
                    })

        # Products
        products_el = drug.find(f"{NS}products")
        if products_el is not None:
            seen = set()
            for product in products_el.findall(f"{NS}product"):
                prod_name = product.find(f"{NS}name")
                if prod_name is not None and prod_name.text:
                    pname = prod_name.text.strip()
                    if pname.lower() not in seen:
                        seen.add(pname.lower())
                        synonyms_list.append({
                            "drugbank_id": drugbank_id,
                            "drug_name": name,
                            "synonym": pname,
                            "source": "drugbank_product",
                        })

        # Mixtures
        mixtures_el = drug.find(f"{NS}mixtures")
        if mixtures_el is not None:
            for mixture in mixtures_el.findall(f"{NS}mixture"):
                mix_name = mixture.find(f"{NS}name")
                if mix_name is not None and mix_name.text:
                    synonyms_list.append({
                        "drugbank_id": drugbank_id,
                        "drug_name": name,
                        "synonym": mix_name.text,
                        "source": "drugbank_mixture",
                    })

        # Secondary IDs as synonyms
        for sid in secondary_ids:
            synonyms_list.append({
                "drugbank_id": drugbank_id,
                "drug_name": name,
                "synonym": sid,
                "source": "drugbank_secondary_id",
            })

        # ── DRUG-DRUG INTERACTIONS ──
        ints_el = drug.find(f"{NS}drug-interactions")
        if ints_el is not None:
            for interaction in ints_el.findall(f"{NS}drug-interaction"):
                partner_id_el = interaction.find(f"{NS}drugbank-id")
                partner_name_el = interaction.find(f"{NS}name")
                int_desc_el = interaction.find(f"{NS}description")

                if partner_id_el is not None:
                    interactions_list.append({
                        "drug_a_id": drugbank_id,
                        "drug_a_name": name,
                        "drug_b_id": partner_id_el.text,
                        "drug_b_name": partner_name_el.text if partner_name_el is not None else None,
                        "description": int_desc_el.text.strip() if (int_desc_el is not None and int_desc_el.text) else None,
                    })

    # Build DataFrames
    drugs_df = pd.DataFrame(drugs_list)
    synonyms_df = pd.DataFrame(synonyms_list)
    interactions_df = pd.DataFrame(interactions_list)
    enzymes_df = pd.DataFrame(enzymes_list)
    categories_df = pd.DataFrame(categories_list)

    print("\nParsing complete:")
    print(f"  Drugs:                {len(drugs_df)}")
    print(f"  Synonyms/brands:      {len(synonyms_df)}")
    print(f"  Interaction entries:  {len(interactions_df)}")
    print(f"  Enzymes/transporters: {len(enzymes_df)}")
    print(f"  Categories:           {len(categories_df)}")

    return drugs_df, synonyms_df, interactions_df, enzymes_df, categories_df


if __name__ == "__main__":
    xml_path = "ml_pipeline/data/raw/drugbank_all_full_database.xml"

    if not os.path.exists(xml_path):
        print(f"ERROR: File not found at {xml_path}")
        sys.exit(1)

    drugs_df, synonyms_df, interactions_df, enzymes_df, categories_df = parse_drugbank(xml_path)

    out_dir = "ml_pipeline/data/processed"
    os.makedirs(out_dir, exist_ok=True)

    drugs_df.to_csv(f"{out_dir}/drugs_raw.csv", index=False)
    synonyms_df.to_csv(f"{out_dir}/synonyms_raw.csv", index=False)
    interactions_df.to_csv(f"{out_dir}/interactions_raw.csv", index=False)
    enzymes_df.to_csv(f"{out_dir}/enzymes_raw.csv", index=False)
    categories_df.to_csv(f"{out_dir}/categories_raw.csv", index=False)

    print(f"\nSaved 5 files to {out_dir}/:")
    print(f"  1. drugs_raw.csv          ({len(drugs_df)} rows)")
    print(f"  2. synonyms_raw.csv       ({len(synonyms_df)} rows)")
    print(f"  3. interactions_raw.csv    ({len(interactions_df)} rows)")
    print(f"  4. enzymes_raw.csv        ({len(enzymes_df)} rows)")
    print(f"  5. categories_raw.csv     ({len(categories_df)} rows)")

    # Stats
    print("\n--- Stats ---")
    approved_count = drugs_df["groups"].str.contains("approved", case=False, na=False).sum()
    print(f"  Approved drugs: {approved_count}")
    print(f"  With ATC code: {drugs_df['atc_code'].notna().sum()}")
    print(f"  With food interactions: {drugs_df['food_interactions'].notna().sum()}")
    print(f"  With indication: {drugs_df['indication'].notna().sum()}")

    print("\n  Enzyme type breakdown:")
    print(f"  {enzymes_df['enzyme_type'].value_counts().to_dict()}")

    cyp = enzymes_df[enzymes_df['enzyme_name'].str.contains('Cytochrome|CYP', case=False, na=False)]
    print(f"  CYP450 entries: {len(cyp)}")

    print(f"\n  Unique categories: {categories_df['category'].nunique()}")