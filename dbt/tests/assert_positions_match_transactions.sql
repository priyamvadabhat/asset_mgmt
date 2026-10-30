-- FAILS if reported quantity <> quantity derived from accepted transactions.
-- This is the DUPLICATE DELIVERY proof: if a transaction file were counted twice
-- the derived quantity would double and this test would return rows.
select * from {{ ref('gold_position_vs_transactions') }} where status = 'BREAK'
