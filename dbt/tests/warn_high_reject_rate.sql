{{ config(severity = 'warn') }}
-- WARNS (does not block) when more than reject_rate_warn_threshold of a dataset was rejected.
-- Acts as the "alert" on a bad / truncated / corrupt delivery.
select dataset, records_received, rejected, reject_rate
from {{ ref('gold_run_reconciliation') }}
where reject_rate > {{ var('reject_rate_warn_threshold') }}
