-- UNNEST + GROUP BY, mid cardinality (1,000 distinct labels): one row per
-- element, hash-aggregated on the element (db-core#802, #809).
SELECT label, count(*) FROM bench, UNNEST(labels) AS t(label) GROUP BY label
