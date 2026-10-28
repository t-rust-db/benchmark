-- A LIST column's NULL test, low cardinality (8 distinct tags): reads the
-- list column without taking it apart (db-core#809, #810).
SELECT count(*) FROM bench WHERE tags IS NOT NULL
