-- FAILS (returns rows) if for any dataset received <> accepted + rejected + duplicates,
-- i.e. a record was silently lost or double counted.
select * from {{ ref('gold_run_reconciliation') }} where not is_balanced
