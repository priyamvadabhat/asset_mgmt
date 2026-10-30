-- FAILS if a position is published twice (one row per portfolio/security/date).
select portfolio_id, security_id, position_date, count(*) as n
from {{ ref('gold_portfolio_positions') }}
group by 1, 2, 3
having count(*) > 1
