{{ config(tags = ['sample_data']) }}
-- Scenario test for the SUPPLIED sample data (run: dbt test --select tag:sample_data).
-- Expected compliance exceptions: T1005 (TRADING_BAN) and T1007 (BUY_BAN).
-- NOT expected: T1006 (after ban ended), T1008 (SELL under BUY_BAN), T1009 (ban LIFTED).
with expected as (select 'T1005' as transaction_id union all select 'T1007'),
     actual   as (select transaction_id from {{ ref('gold_compliance_exceptions') }})
select coalesce(e.transaction_id, a.transaction_id) as transaction_id,
       iff(e.transaction_id is null, 'UNEXPECTED_EXCEPTION', 'MISSING_EXCEPTION') as problem
from expected e full outer join actual a on e.transaction_id = a.transaction_id
where e.transaction_id is null or a.transaction_id is null
