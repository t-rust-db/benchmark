-- UNNEST + GROUP BY, low cardinality (8 distinct tags): one row per element,
-- hash-aggregated on the element (db-core#802, #809).
SELECT tag, count(*) FROM bench, UNNEST(tags) AS t(tag) GROUP BY tag
