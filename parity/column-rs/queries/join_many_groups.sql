-- The `join` query grouped by the customer key instead of its tier: 100K
-- groups at `large` instead of 3, so each row group's partial aggregate is
-- large and how partials are merged shows up in time and memory
-- (db-core#863).
SELECT bench_customers.customer_id, SUM(bench.amount)
FROM bench JOIN bench_customers ON bench.customer_id = bench_customers.customer_id
GROUP BY bench_customers.customer_id
