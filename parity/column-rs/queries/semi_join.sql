-- Semi-join: the fact rows whose customer is in a filtered dimension
-- subquery (tools#90). The subquery returns ~33k of the 100k customer keys.
SELECT SUM(amount)
FROM bench
WHERE customer_id IN (SELECT customer_id FROM bench_customers WHERE tier = 'gold')
