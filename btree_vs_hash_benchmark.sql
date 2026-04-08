\timing on

\echo ''
\echo '============================================================'
\echo '  B-Tree vs Hash Index Benchmark — PostgreSQL 16'
\echo '  Ojasva Manik, Piyush Gangrade & Prachi Yadav | IIST CSE'
\echo '============================================================'
\echo ''

DROP TABLE IF EXISTS bench_small CASCADE;
DROP TABLE IF EXISTS bench_medium CASCADE;
DROP TABLE IF EXISTS bench_large CASCADE;
DROP TABLE IF EXISTS bench_write_baseline CASCADE;
DROP TABLE IF EXISTS bench_write_btree CASCADE;
DROP TABLE IF EXISTS bench_write_hash CASCADE;

\echo '>> Creating bench_small (100,000 rows)...'
CREATE TABLE bench_small (
    id      INTEGER PRIMARY KEY,
    val     INTEGER NOT NULL,
    label   TEXT    NOT NULL
);
INSERT INTO bench_small (id, val, label)
SELECT s, (random() * 1000000)::INTEGER, md5(s::TEXT) FROM generate_series(1, 100000) AS s;
ANALYZE bench_small;

\echo '>> Creating bench_medium (1,000,000 rows)...'
CREATE TABLE bench_medium (
    id      INTEGER PRIMARY KEY,
    val     INTEGER NOT NULL,
    label   TEXT    NOT NULL
);
INSERT INTO bench_medium (id, val, label)
SELECT s, (random() * 10000000)::INTEGER, md5(s::TEXT) FROM generate_series(1, 1000000) AS s;
ANALYZE bench_medium;

\echo '>> Creating bench_large (10,000,000 rows)...'
CREATE TABLE bench_large (
    id      INTEGER PRIMARY KEY,
    val     INTEGER NOT NULL,
    label   TEXT    NOT NULL
);
INSERT INTO bench_large (id, val, label)
SELECT s, (random() * 100000000)::INTEGER, md5(s::TEXT) FROM generate_series(1, 10000000) AS s;
ANALYZE bench_large;

SET max_parallel_workers_per_gather = 0;

CREATE OR REPLACE FUNCTION run_benchmark(
    p_test_name text,
    p_query text,
    p_total_runs int DEFAULT 15,
    p_warmup_runs int DEFAULT 3
)
RETURNS TABLE (
    test_name text,
    recorded_runs int,
    median_ms numeric,
    avg_ms numeric,
    min_ms numeric,
    max_ms numeric
) AS $$
DECLARE
    v_explain_json jsonb;
    v_exec_time numeric;
    v_times numeric[] := '{}';
BEGIN
    FOR i IN 1..p_total_runs LOOP
        EXECUTE 'EXPLAIN (ANALYZE, FORMAT JSON) ' || p_query INTO v_explain_json;
        v_exec_time := (v_explain_json->0->>'Execution Time')::numeric;
        IF i > p_warmup_runs THEN
            v_times := array_append(v_times, v_exec_time);
        END IF;
    END LOOP;

    RETURN QUERY
    SELECT
        p_test_name,
        array_length(v_times, 1),
        round((percentile_cont(0.5) WITHIN GROUP (ORDER BY t.val))::numeric, 3),
        round(avg(t.val)::numeric, 3),
        round(min(t.val)::numeric, 3),
        round(max(t.val)::numeric, 3)
    FROM unnest(v_times) AS t(val);
END;
$$ LANGUAGE plpgsql;

\echo ''
\echo '============================================================'
\echo '  SEQUENTIAL SCAN BASELINE'
\echo '============================================================'

SELECT * FROM run_benchmark('Baseline Small Equality', 'SELECT * FROM bench_small WHERE val = 42000');
SELECT * FROM run_benchmark('Baseline Small Range', 'SELECT * FROM bench_small WHERE val BETWEEN 40000 AND 41000');

SELECT * FROM run_benchmark('Baseline Medium Equality', 'SELECT * FROM bench_medium WHERE val = 420000');
SELECT * FROM run_benchmark('Baseline Medium Range', 'SELECT * FROM bench_medium WHERE val BETWEEN 400000 AND 410000');

SELECT * FROM run_benchmark('Baseline Large Equality', 'SELECT * FROM bench_large WHERE val = 4200000');
SELECT * FROM run_benchmark('Baseline Large Range', 'SELECT * FROM bench_large WHERE val BETWEEN 4000000 AND 4100000');

\echo ''
\echo '============================================================'
\echo '  CREATE B-TREE INDEXES'
\echo '============================================================'

CREATE INDEX idx_btree_small  ON bench_small  USING BTREE (val);
CREATE INDEX idx_btree_medium ON bench_medium USING BTREE (val);
CREATE INDEX idx_btree_large  ON bench_large  USING BTREE (val);

SELECT indexrelname AS index_name, pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes WHERE relname IN ('bench_small', 'bench_medium', 'bench_large') AND indexrelname NOT LIKE '%pkey%';

\echo ''
\echo '============================================================'
\echo '  B-TREE PERFORMANCE BENCHMARK'
\echo '============================================================'

SET enable_seqscan = OFF;

\echo '---------- SMALL (100K rows) ----------'
SELECT * FROM run_benchmark('B-Tree Small Equality', 'SELECT * FROM bench_small WHERE val = 42000');
SELECT * FROM run_benchmark('B-Tree Small Range',    'SELECT * FROM bench_small WHERE val BETWEEN 40000 AND 41000');

\echo '---------- MEDIUM (1M rows) ----------'
SELECT * FROM run_benchmark('B-Tree Medium Equality', 'SELECT * FROM bench_medium WHERE val = 420000');
SELECT * FROM run_benchmark('B-Tree Medium Range',    'SELECT * FROM bench_medium WHERE val BETWEEN 400000 AND 410000');

\echo '---------- LARGE (10M rows) ----------'
SELECT * FROM run_benchmark('B-Tree Large Equality', 'SELECT * FROM bench_large WHERE val = 4200000');
SELECT * FROM run_benchmark('B-Tree Large Range',    'SELECT * FROM bench_large WHERE val BETWEEN 4000000 AND 4100000');

\echo ''
\echo '============================================================'
\echo '  DROP B-TREE & CREATE HASH INDEXES'
\echo '============================================================'

DROP INDEX idx_btree_small;
DROP INDEX idx_btree_medium;
DROP INDEX idx_btree_large;

CREATE INDEX idx_hash_small  ON bench_small  USING HASH (val);
CREATE INDEX idx_hash_medium ON bench_medium USING HASH (val);
CREATE INDEX idx_hash_large  ON bench_large  USING HASH (val);

SELECT indexrelname AS index_name, pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes WHERE relname IN ('bench_small', 'bench_medium', 'bench_large') AND indexrelname NOT LIKE '%pkey%';

\echo ''
\echo '============================================================'
\echo '  HASH PERFORMANCE BENCHMARK'
\echo '============================================================'

\echo '---------- SMALL (100K rows) ----------'
SELECT * FROM run_benchmark('Hash Small Equality', 'SELECT * FROM bench_small WHERE val = 42000');
SET enable_seqscan = ON; 
SELECT * FROM run_benchmark('Hash Small Range (Fallback)', 'SELECT * FROM bench_small WHERE val BETWEEN 40000 AND 41000');
SET enable_seqscan = OFF;

\echo '---------- MEDIUM (1M rows) ----------'
SELECT * FROM run_benchmark('Hash Medium Equality', 'SELECT * FROM bench_medium WHERE val = 420000');
SET enable_seqscan = ON; 
SELECT * FROM run_benchmark('Hash Medium Range (Fallback)', 'SELECT * FROM bench_medium WHERE val BETWEEN 400000 AND 410000');
SET enable_seqscan = OFF;

\echo '---------- LARGE (10M rows) ----------'
SELECT * FROM run_benchmark('Hash Large Equality', 'SELECT * FROM bench_large WHERE val = 4200000');
SET enable_seqscan = ON; 
SELECT * FROM run_benchmark('Hash Large Range (Fallback)', 'SELECT * FROM bench_large WHERE val BETWEEN 4000000 AND 4100000');
SET enable_seqscan = OFF;

\echo ''
\echo '============================================================'
\echo '  RECREATE B-TREE (FREE PLANNER)'
\echo '============================================================'

CREATE INDEX idx_btree_small  ON bench_small  USING BTREE (val);
CREATE INDEX idx_btree_medium ON bench_medium USING BTREE (val);
CREATE INDEX idx_btree_large  ON bench_large  USING BTREE (val);

RESET enable_seqscan;

\echo '---------- SMALL (100K rows) ----------'
SELECT * FROM run_benchmark('Free Planner Small Equality', 'SELECT * FROM bench_small WHERE val = 42000');
SELECT * FROM run_benchmark('Free Planner Small Range', 'SELECT * FROM bench_small WHERE val BETWEEN 40000 AND 41000');

\echo '---------- MEDIUM (1M rows) ----------'
SELECT * FROM run_benchmark('Free Planner Medium Equality', 'SELECT * FROM bench_medium WHERE val = 420000');
SELECT * FROM run_benchmark('Free Planner Medium Range', 'SELECT * FROM bench_medium WHERE val BETWEEN 400000 AND 410000');

\echo '---------- LARGE (10M rows) ----------'
SELECT * FROM run_benchmark('Free Planner Large Equality', 'SELECT * FROM bench_large WHERE val = 4200000');
SELECT * FROM run_benchmark('Free Planner Large Range', 'SELECT * FROM bench_large WHERE val BETWEEN 4000000 AND 4100000');

\echo ''
\echo '============================================================'
\echo '  WRITE OVERHEAD BENCHMARK'
\echo '============================================================'

\echo '>> Baseline INSERT...'
CREATE TABLE bench_write_baseline (id SERIAL PRIMARY KEY, val INTEGER NOT NULL, label TEXT NOT NULL);
INSERT INTO bench_write_baseline (val, label)
SELECT (random() * 1000000)::INTEGER, md5(s::TEXT) FROM generate_series(1, 10000) AS s;

\echo '>> INSERT with B-Tree active...'
CREATE TABLE bench_write_btree (id SERIAL PRIMARY KEY, val INTEGER NOT NULL, label TEXT NOT NULL);
CREATE INDEX idx_write_btree ON bench_write_btree USING BTREE (val);
INSERT INTO bench_write_btree (val, label)
SELECT (random() * 1000000)::INTEGER, md5(s::TEXT) FROM generate_series(1, 10000) AS s;

\echo '>> INSERT with Hash active...'
CREATE TABLE bench_write_hash (id SERIAL PRIMARY KEY, val INTEGER NOT NULL, label TEXT NOT NULL);
CREATE INDEX idx_write_hash ON bench_write_hash USING HASH (val);
INSERT INTO bench_write_hash (val, label)
SELECT (random() * 1000000)::INTEGER, md5(s::TEXT) FROM generate_series(1, 10000) AS s;

\echo ''
\echo '============================================================'
\echo '  TABLE SIZE SUMMARY'
\echo '============================================================'
\echo ''

SELECT
    relname AS table_name,
    pg_size_pretty(pg_relation_size(relid)) AS table_data_size,
    pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) AS total_index_size,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_disk_footprint
FROM pg_stat_user_tables
WHERE relname IN ('bench_small', 'bench_medium', 'bench_large')
ORDER BY pg_total_relation_size(relid) DESC;

\echo ''
\echo '============================================================'
\echo '  BENCHMARK COMPLETE'
\echo '============================================================'
