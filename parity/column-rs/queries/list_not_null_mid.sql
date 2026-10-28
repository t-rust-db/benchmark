-- A LIST column's NULL test, mid cardinality (1,000 distinct labels): reads
-- the list column without taking it apart (db-core#809, #810).
SELECT count(*) FROM bench WHERE labels IS NOT NULL
