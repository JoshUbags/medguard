import sqlite3

db_path = "mobile/assets/db/medguard.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

print("=" * 50)
print("MEDGUARD DATABASE VERIFICATION")
print("=" * 50)

# Table counts
for table in ["drugs", "drug_synonyms", "interactions", "food_interactions", "drug_categories", "drug_enzymes", "allergies", "user_medications", "check_logs"]:
    cursor.execute(f"SELECT COUNT(*) FROM {table}")
    print(f"  {table}: {cursor.fetchone()[0]}")

# DDI test: Warfarin + Aspirin
print("\n--- DDI Test: Warfarin ---")
cursor.execute("""
    SELECT d2.name, i.severity, i.clinical_effect
    FROM interactions i
    JOIN drugs d1 ON i.drug_a_id = d1.id
    JOIN drugs d2 ON i.drug_b_id = d2.id
    WHERE LOWER(d1.name) = 'warfarin'
    LIMIT 5
""")
for r in cursor.fetchall():
    print(f"  + {r[0]}: {r[1]} — {r[2]}")

# Food interaction test
print("\n--- Food Interaction Test ---")
cursor.execute("""
    SELECT d.name, f.description
    FROM food_interactions f
    JOIN drugs d ON f.drug_id = d.id
    LIMIT 5
""")
for r in cursor.fetchall():
    print(f"  {r[0]}: {r[1][:80]}...")

# Duplicate therapy test
print("\n--- Duplicate Therapy Test (same category) ---")
cursor.execute("""
    SELECT dc.category, COUNT(DISTINCT dc.drug_id) as cnt
    FROM drug_categories dc
    GROUP BY dc.category
    HAVING cnt > 3
    ORDER BY cnt DESC
    LIMIT 5
""")
for r in cursor.fetchall():
    print(f"  {r[0]}: {r[1]} drugs")

# Synonym search test
print("\n--- Synonym Search: 'Tylenol' ---")
cursor.execute("""
    SELECT d.name, ds.synonym
    FROM drug_synonyms ds
    JOIN drugs d ON ds.drug_id = d.id
    WHERE ds.synonym LIKE '%Tylenol%'
    LIMIT 3
""")
results = cursor.fetchall()
if results:
    for r in results:
        print(f"  {r[1]} -> {r[0]}")
else:
    print("  Not found")

# Autocomplete test
print("\n--- Autocomplete: 'ibu' ---")
cursor.execute("SELECT name FROM drugs WHERE LOWER(name) LIKE 'ibu%' LIMIT 5")
for r in cursor.fetchall():
    print(f"  {r[0]}")

# Enzyme/CYP test
print("\n--- CYP450 Coverage ---")
cursor.execute("SELECT COUNT(*) FROM drug_enzymes WHERE enzyme_name LIKE '%Cytochrome%' OR gene_name LIKE 'CYP%'")
cyp_count = cursor.fetchone()[0]
print(f"  CYP entries: {cyp_count}")

# RxNorm coverage
cursor.execute("SELECT COUNT(*) FROM drugs WHERE rxcui IS NOT NULL")
rx = cursor.fetchone()[0]
cursor.execute("SELECT COUNT(*) FROM drugs")
total = cursor.fetchone()[0]
print("\n--- RxNorm Coverage ---")
print(f"  {rx}/{total} drugs ({100*rx/total:.1f}%)")

# Severity distribution
print("\n--- Severity Distribution ---")
cursor.execute("SELECT severity, COUNT(*) FROM interactions GROUP BY severity ORDER BY COUNT(*) DESC")
for r in cursor.fetchall():
    print(f"  {r[0]}: {r[1]}")

conn.close()
print("\nVerification complete!")