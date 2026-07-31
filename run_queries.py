import sqlite3
import re

conn = sqlite3.connect('northwind.db')
cur = conn.cursor()

with open('analysis.sql') as f:
    sql_text = f.read()

# Split into individual statements, keeping track of the preceding comment/label
blocks = re.split(r'\n\n(?=-- \d\.\d)', sql_text)

for block in blocks:
    block = block.strip()
    if not block:
        continue
    lines = block.split('\n')
    label = lines[0].replace('--', '').strip()
    stmt = '\n'.join(l for l in lines if not l.strip().startswith('--')).strip()
    if not stmt:
        continue
    try:
        cur.execute(stmt)
        cols = [d[0] for d in cur.description]
        rows = cur.fetchall()
        print(f"=== {label} ===")
        print(cols)
        for r in rows[:15]:
            print(r)
        print()
    except Exception as e:
        print(f"=== {label} === ERROR: {e}\n")

conn.close()
