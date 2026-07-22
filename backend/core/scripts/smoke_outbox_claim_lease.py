"""Smoke-test indexing_outbox claim lease interval SQL against local Postgres."""
import psycopg2

conn = psycopg2.connect(
    host="localhost",
    port=5432,
    dbname="careconnect",
    user="postgres",
    password="changeme",
)
conn.autocommit = True
cur = conn.cursor()

print("--- interval binding modes ---")
try:
    cur.execute("SELECT CAST((%s::int || ' minutes') AS INTERVAL)", (10,))
    print("INT_CONCAT_OK:", cur.fetchone())
except Exception as e:
    print("INT_CONCAT_FAIL:", str(e).splitlines()[0])
    conn.rollback()
    conn.autocommit = True

cur.execute("SELECT make_interval(mins => %s)", (10,))
print("MAKE_INTERVAL_OK:", cur.fetchone())

cur.execute("SELECT CAST((%s::text || ' minutes') AS INTERVAL)", (10,))
print("TEXT_CONCAT_OK:", cur.fetchone())

print("--- claim query smoke ---")
cur.execute(
    """
CREATE TABLE IF NOT EXISTS indexing_outbox_claim_smoke (
  id BIGSERIAL PRIMARY KEY,
  processed_at TIMESTAMPTZ NULL,
  claimed_at TIMESTAMPTZ NULL
)
"""
)
cur.execute("TRUNCATE indexing_outbox_claim_smoke")
cur.execute(
    """
INSERT INTO indexing_outbox_claim_smoke (processed_at, claimed_at) VALUES
  (NULL, NULL),
  (NULL, NOW() - INTERVAL '1 minute'),
  (NULL, NOW() - INTERVAL '20 minutes'),
  (NOW(), NULL)
"""
)

lease_minutes = 10
cur.execute(
    """
    SELECT id FROM indexing_outbox_claim_smoke
    WHERE processed_at IS NULL
      AND (claimed_at IS NULL
           OR claimed_at < (NOW() - make_interval(mins => %s)))
    ORDER BY id ASC
    FOR UPDATE SKIP LOCKED
    LIMIT %s
    """,
    (lease_minutes, 10),
)
rows = [r[0] for r in cur.fetchall()]
print("CLAIMED_IDS:", rows)
assert len(rows) == 2, rows
print("SMOKE_PASS")

cur.execute("DROP TABLE IF EXISTS indexing_outbox_claim_smoke")
cur.close()
conn.close()
