import sqlite3
import pandas as pd
import os


def create_tables(conn):
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS drugs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            drugbank_id TEXT UNIQUE NOT NULL,
            rxcui TEXT,
            name TEXT NOT NULL,
            generic_name TEXT,
            drug_type TEXT,
            description TEXT,
            indication TEXT,
            mechanism_of_action TEXT,
            absorption TEXT,
            half_life TEXT,
            toxicity TEXT,
            atc_code TEXT,
            all_atc_codes TEXT,
            drug_class TEXT,
            cas_number TEXT,
            average_mass TEXT,
            groups TEXT
        );

        CREATE TABLE IF NOT EXISTS drug_synonyms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            drug_id INTEGER NOT NULL,
            synonym TEXT NOT NULL,
            source TEXT,
            FOREIGN KEY (drug_id) REFERENCES drugs(id)
        );

        CREATE TABLE IF NOT EXISTS interactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            drug_a_id INTEGER NOT NULL,
            drug_b_id INTEGER NOT NULL,
            severity TEXT NOT NULL DEFAULT 'moderate',
            severity_int INTEGER NOT NULL DEFAULT 1,
            mechanism TEXT,
            clinical_effect TEXT,
            description TEXT,
            openfda_coreport_count INTEGER DEFAULT 0,
            FOREIGN KEY (drug_a_id) REFERENCES drugs(id),
            FOREIGN KEY (drug_b_id) REFERENCES drugs(id)
        );

        CREATE TABLE IF NOT EXISTS food_interactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            drug_id INTEGER NOT NULL,
            description TEXT NOT NULL,
            FOREIGN KEY (drug_id) REFERENCES drugs(id)
        );

        CREATE TABLE IF NOT EXISTS drug_categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            drug_id INTEGER NOT NULL,
            category TEXT NOT NULL,
            mesh_id TEXT,
            FOREIGN KEY (drug_id) REFERENCES drugs(id)
        );

        CREATE TABLE IF NOT EXISTS drug_enzymes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            drug_id INTEGER NOT NULL,
            enzyme_type TEXT,
            enzyme_name TEXT,
            gene_name TEXT,
            actions TEXT,
            known_action TEXT,
            FOREIGN KEY (drug_id) REFERENCES drugs(id)
        );

        CREATE TABLE IF NOT EXISTS allergies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            drug_id INTEGER NOT NULL,
            note TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (drug_id) REFERENCES drugs(id)
        );

        CREATE TABLE IF NOT EXISTS user_medications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            drug_id INTEGER NOT NULL,
            dosage TEXT,
            added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (drug_id) REFERENCES drugs(id)
        );

        CREATE TABLE IF NOT EXISTS check_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            drug_ids TEXT,
            predicted_severity TEXT,
            source TEXT DEFAULT 'rule_based',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS idx_drugs_name ON drugs(name);
        CREATE INDEX IF NOT EXISTS idx_drugs_rxcui ON drugs(rxcui);
        CREATE INDEX IF NOT EXISTS idx_drugs_drugbank_id ON drugs(drugbank_id);
        CREATE INDEX IF NOT EXISTS idx_drugs_atc ON drugs(atc_code);
        CREATE INDEX IF NOT EXISTS idx_synonyms_synonym ON drug_synonyms(synonym);
        CREATE INDEX IF NOT EXISTS idx_synonyms_drug_id ON drug_synonyms(drug_id);
        CREATE INDEX IF NOT EXISTS idx_interactions_a ON interactions(drug_a_id);
        CREATE INDEX IF NOT EXISTS idx_interactions_b ON interactions(drug_b_id);
        -- Step 41: compound index so paired lookups hit a single B-tree scan
        -- instead of intersecting two single-column indexes.
        CREATE INDEX IF NOT EXISTS idx_interactions_pair
            ON interactions(drug_a_id, drug_b_id);
        CREATE INDEX IF NOT EXISTS idx_food_drug ON food_interactions(drug_id);
        CREATE INDEX IF NOT EXISTS idx_cat_drug ON drug_categories(drug_id);
        CREATE INDEX IF NOT EXISTS idx_cat_name ON drug_categories(category);
        CREATE INDEX IF NOT EXISTS idx_enz_drug ON drug_enzymes(drug_id);
        CREATE INDEX IF NOT EXISTS idx_user_meds ON user_medications(user_id);

        -- Step 43: bundled-database metadata for the app's About card and
        -- future differential-update logic.
        CREATE TABLE IF NOT EXISTS db_metadata (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        -- Step 41: FTS5 indexes for autocomplete-fast name + synonym search.
        -- 'contentless_unindexed' would be too restrictive here — we want the
        -- rowid match plus the literal name for ranking, so we use external
        -- content tables to avoid duplicating storage.
        CREATE VIRTUAL TABLE IF NOT EXISTS drugs_fts USING fts5(
            name,
            content='drugs',
            content_rowid='id',
            tokenize='unicode61 remove_diacritics 2'
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS drug_synonyms_fts USING fts5(
            synonym,
            content='drug_synonyms',
            content_rowid='id',
            tokenize='unicode61 remove_diacritics 2'
        );
    """)
    print("Tables, indexes, and FTS5 virtual tables created.")


if __name__ == "__main__":
    processed_dir = "ml_pipeline/data/processed"
    db_path = "mobile/assets/db/medguard.db"
    os.makedirs("mobile/assets/db", exist_ok=True)

    if os.path.exists(db_path):
        os.remove(db_path)

    print(f"Building database at {db_path}...")
    conn = sqlite3.connect(db_path)
    create_tables(conn)
    cursor = conn.cursor()

    # ── LOAD DATA ──
    print("\nLoading processed data...")

    if os.path.exists(f"{processed_dir}/drugs_normalized.csv"):
        drugs = pd.read_csv(f"{processed_dir}/drugs_normalized.csv")
        print(f"  Drugs (normalized): {len(drugs)}")
    else:
        drugs = pd.read_csv(f"{processed_dir}/drugs_raw.csv")
        # Filter to approved drugs only
        drugs = drugs[drugs["groups"].str.contains("approved", case=False, na=False)].copy()
        print(f"  Drugs (approved, raw): {len(drugs)}")

    synonyms = pd.read_csv(f"{processed_dir}/synonyms_raw.csv")
    print(f"  Synonyms: {len(synonyms)}")

    if os.path.exists(f"{processed_dir}/interactions_enriched.csv"):
        interactions = pd.read_csv(f"{processed_dir}/interactions_enriched.csv")
    elif os.path.exists(f"{processed_dir}/interactions_classified.csv"):
        interactions = pd.read_csv(f"{processed_dir}/interactions_classified.csv")
    else:
        interactions = pd.read_csv(f"{processed_dir}/interactions_raw.csv")
    print(f"  Interactions: {len(interactions)}")

    enzymes = pd.read_csv(f"{processed_dir}/enzymes_raw.csv") if os.path.exists(f"{processed_dir}/enzymes_raw.csv") else pd.DataFrame()
    categories = pd.read_csv(f"{processed_dir}/categories_raw.csv") if os.path.exists(f"{processed_dir}/categories_raw.csv") else pd.DataFrame()
    print(f"  Enzymes: {len(enzymes)}")
    print(f"  Categories: {len(categories)}")

    # ── POPULATE DRUGS ──
    print("\nPopulating drugs...")
    drug_count = 0
    for _, row in drugs.iterrows():
        try:
            cursor.execute("""
                INSERT OR IGNORE INTO drugs
                (drugbank_id, rxcui, name, generic_name, drug_type, description,
                 indication, mechanism_of_action, absorption, half_life, toxicity,
                 atc_code, all_atc_codes, drug_class, cas_number, average_mass, groups)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, (
                row.get("drugbank_id"),
                row.get("rxcui") if pd.notna(row.get("rxcui")) else None,
                row.get("name"),
                row.get("name"),
                row.get("drug_type"),
                row.get("description") if pd.notna(row.get("description")) else None,
                row.get("indication") if pd.notna(row.get("indication")) else None,
                row.get("mechanism_of_action") if pd.notna(row.get("mechanism_of_action")) else None,
                row.get("absorption") if pd.notna(row.get("absorption")) else None,
                row.get("half_life") if pd.notna(row.get("half_life")) else None,
                row.get("toxicity") if pd.notna(row.get("toxicity")) else None,
                row.get("atc_code") if pd.notna(row.get("atc_code")) else None,
                row.get("all_atc_codes") if pd.notna(row.get("all_atc_codes")) else None,
                row.get("drug_class") if pd.notna(row.get("drug_class")) else None,
                row.get("cas_number") if pd.notna(row.get("cas_number")) else None,
                row.get("average_mass") if pd.notna(row.get("average_mass")) else None,
                row.get("groups"),
            ))
            drug_count += 1
        except Exception:
            pass
    conn.commit()
    print(f"  Inserted {drug_count} drugs.")

    # ── POPULATE SYNONYMS ──
    print("Populating synonyms...")
    syn_count = 0
    for _, row in synonyms.iterrows():
        cursor.execute("SELECT id FROM drugs WHERE drugbank_id = ?", (row["drugbank_id"],))
        result = cursor.fetchone()
        if result:
            try:
                cursor.execute("INSERT INTO drug_synonyms (drug_id, synonym, source) VALUES (?,?,?)",
                               (result[0], row["synonym"], row.get("source")))
                syn_count += 1
            except Exception:
                pass
    conn.commit()
    print(f"  Inserted {syn_count} synonyms.")

    # ── POPULATE INTERACTIONS ──
    print("Populating interactions...")
    int_count = 0
    for _, row in interactions.iterrows():
        cursor.execute("SELECT id FROM drugs WHERE drugbank_id = ?", (row["drug_a_id"],))
        a = cursor.fetchone()
        cursor.execute("SELECT id FROM drugs WHERE drugbank_id = ?", (row["drug_b_id"],))
        b = cursor.fetchone()
        if a and b:
            try:
                coreport = int(row.get("openfda_coreport_count", 0)) if pd.notna(row.get("openfda_coreport_count")) else 0
                cursor.execute("""
                    INSERT INTO interactions
                    (drug_a_id, drug_b_id, severity, severity_int, mechanism, clinical_effect, description, openfda_coreport_count)
                    VALUES (?,?,?,?,?,?,?,?)
                """, (
                    a[0], b[0],
                    row.get("severity", "moderate"),
                    int(row.get("severity_int", 1)),
                    row.get("mechanism") if pd.notna(row.get("mechanism")) else None,
                    row.get("clinical_effect") if pd.notna(row.get("clinical_effect")) else None,
                    row.get("description") if pd.notna(row.get("description")) else None,
                    coreport,
                ))
                int_count += 1
            except Exception:
                pass
    conn.commit()
    print(f"  Inserted {int_count} interactions.")

    # ── POPULATE FOOD INTERACTIONS ──
    print("Populating food interactions...")
    food_count = 0
    for _, row in drugs.iterrows():
        food = row.get("food_interactions")
        if not food or not isinstance(food, str) or pd.isna(food):
            continue
        cursor.execute("SELECT id FROM drugs WHERE drugbank_id = ?", (row["drugbank_id"],))
        result = cursor.fetchone()
        if not result:
            continue
        for fi in food.split("|"):
            fi = fi.strip()
            if fi:
                try:
                    cursor.execute("INSERT INTO food_interactions (drug_id, description) VALUES (?,?)",
                                   (result[0], fi))
                    food_count += 1
                except Exception:
                    pass
    conn.commit()
    print(f"  Inserted {food_count} food interactions.")

    # ── POPULATE CATEGORIES ──
    print("Populating drug categories...")
    cat_count = 0
    if len(categories) > 0:
        for _, row in categories.iterrows():
            cursor.execute("SELECT id FROM drugs WHERE drugbank_id = ?", (row["drugbank_id"],))
            result = cursor.fetchone()
            if result:
                try:
                    cursor.execute("INSERT INTO drug_categories (drug_id, category, mesh_id) VALUES (?,?,?)",
                                   (result[0], row["category"],
                                    row.get("mesh_id") if pd.notna(row.get("mesh_id")) else None))
                    cat_count += 1
                except Exception:
                    pass
        conn.commit()
    print(f"  Inserted {cat_count} categories.")

    # ── POPULATE ENZYMES ──
    print("Populating enzymes...")
    enz_count = 0
    if len(enzymes) > 0:
        for _, row in enzymes.iterrows():
            cursor.execute("SELECT id FROM drugs WHERE drugbank_id = ?", (row["drugbank_id"],))
            result = cursor.fetchone()
            if result:
                try:
                    cursor.execute("""
                        INSERT INTO drug_enzymes (drug_id, enzyme_type, enzyme_name, gene_name, actions, known_action)
                        VALUES (?,?,?,?,?,?)
                    """, (
                        result[0],
                        row.get("enzyme_type"),
                        row.get("enzyme_name"),
                        row.get("gene_name") if pd.notna(row.get("gene_name")) else None,
                        row.get("actions") if pd.notna(row.get("actions")) else None,
                        row.get("known_action") if pd.notna(row.get("known_action")) else None,
                    ))
                    enz_count += 1
                except Exception:
                    pass
        conn.commit()
    print(f"  Inserted {enz_count} enzymes.")

    # ── REBUILD FTS5 INDEXES ──
    print("Rebuilding FTS5 indexes (drugs_fts, drug_synonyms_fts)...")
    cursor.execute("INSERT INTO drugs_fts(drugs_fts) VALUES('rebuild')")
    cursor.execute(
        "INSERT INTO drug_synonyms_fts(drug_synonyms_fts) VALUES('rebuild')"
    )
    conn.commit()

    # ── DB METADATA ──
    print("Recording db_metadata…")
    from datetime import datetime, timezone
    metadata_rows = [
        ("schema_version", "1"),
        ("drugbank_version", "6.0"),
        ("built_at", datetime.now(timezone.utc).isoformat()),
    ]
    for table in [
        "drugs",
        "drug_synonyms",
        "interactions",
        "food_interactions",
        "drug_categories",
        "drug_enzymes",
    ]:
        cursor.execute(f"SELECT COUNT(*) FROM {table}")
        metadata_rows.append((f"count_{table}", str(cursor.fetchone()[0])))
    for key, value in metadata_rows:
        cursor.execute(
            "INSERT OR REPLACE INTO db_metadata(key, value) VALUES (?, ?)",
            (key, value),
        )
    conn.commit()

    # ── SUMMARY ──
    print(f"\n{'='*50}")
    print("DATABASE SUMMARY — medguard.db")
    print(f"{'='*50}")
    for table in ["drugs", "drug_synonyms", "interactions", "food_interactions", "drug_categories", "drug_enzymes"]:
        cursor.execute(f"SELECT COUNT(*) FROM {table}")
        print(f"  {table}: {cursor.fetchone()[0]}")

    print("\n  Severity breakdown:")
    cursor.execute("SELECT severity, COUNT(*) FROM interactions GROUP BY severity ORDER BY COUNT(*) DESC")
    for row in cursor.fetchall():
        print(f"    {row[0]}: {row[1]}")

    db_size = os.path.getsize(db_path) / (1024 * 1024)
    print(f"\n  Database size: {db_size:.1f} MB")

    conn.close()
    print("\nDone!")