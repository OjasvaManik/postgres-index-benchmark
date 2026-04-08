# PostgreSQL B-Tree vs. Hash Index Benchmark

> Empirical performance analysis of PostgreSQL 16's B-Tree and Hash index implementations across varying dataset sizes (100K, 1M, and 10M rows) on modern NVMe Gen 5 hardware.

---

## Overview

Historically, PostgreSQL Hash indexes were not WAL-safe and lacked widespread adoption. Since **PostgreSQL 10**, they are crash-safe, prompting the need to re-evaluate their performance against the ubiquitous B-Tree.

This benchmark tests both index types across three core metrics:

1. **Read Performance** — Exact-match equality queries and range queries (0.1% selectivity)
2. **Creation Overhead** — Time required to generate the index from scratch
3. **Storage Footprint** — Physical disk space consumed by the index structure
4. **Write Overhead** — Latency penalty during an OLTP-style 10,000-row batch `INSERT`

---

## Methodology

To ensure rigorous and reproducible results, the benchmark employs a custom PL/pgSQL function (`run_benchmark`) that enforces a **strict warm-cache methodology**:

- Each query type is executed **15 times**
- The first **3 executions are discarded** to eliminate cold-start disk I/O latency
- The **median execution time** of the remaining 12 runs is recorded to mathematically isolate algorithmic speed and reduce the influence of OS scheduling jitter
- Raw times are captured dynamically using `EXPLAIN (ANALYZE, FORMAT JSON)`

---

## Prerequisites

- **PostgreSQL 16+** (testing was conducted using the official PostgreSQL Docker image)
- A terminal with `psql` access
- **Hardware Note:** For results consistent with the paper, testing should be conducted on high-performance solid-state storage (NVMe SSD). Running this on mechanical HDDs will heavily skew range-query results due to random I/O latency.

---

## How to Run

**1. Clone the repository:**

```bash
git clone https://github.com/OjasvaManik/postgres-index-benchmark.git
cd postgres-index-benchmark
```

**2. Execute the script against your PostgreSQL instance:**

> ⚠️ The 10-million-row dataset generation and index creation may take several minutes to complete.

**Option A — Direct `psql`:**

```bash
psql -U your_username -d your_database -f btree_vs_hash_benchmark.sql 2>&1 | tee results.txt
```

**Option B — Docker:**

```bash
docker cp btree_vs_hash_benchmark.sql your-container-name:/tmp/
docker exec -it your-container-name psql -U your_username -d your_database -f /tmp/btree_vs_hash_benchmark.sql 2>&1 | tee results.txt
```

The script will output a formatted table to your console detailing median execution times, index sizes, and write overhead.

---

## Conclusion

**B-Tree remains the optimal default for general-purpose workloads.**

Hash indexes should be strictly reserved for highly queried, exact-match columns (e.g., UUID lookups, session tokens) where pure read speed supersedes the significant infrastructure and storage penalties.

---

## Authors

| Name | Institution | Department |
|---|---|---|
| **Ojasva Manik** | Indore Institute of Science and Technology | Computer Science & Engineering |
| **Piyush Gangrade** | Indore Institute of Science and Technology | Computer Science & Engineering |
| **Prachi Yadav** | Indore Institute of Science and Technology | Computer Science & Engineering |
