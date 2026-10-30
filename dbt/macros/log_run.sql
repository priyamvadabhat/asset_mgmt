{# =============================================================================
   log_run : on-run-end hook. Runs even when a model failed, so failures are
   recorded in AUDIT.PIPELINE_RUN_LOG instead of disappearing.
   Also copies this run's reconciliation + metrics into the history tables.
   ============================================================================= #}
{% macro log_run(results) %}
  {% if execute %}

    {# --- count node outcomes --- #}
    {% set ns = namespace(ok=0, bad=0, skipped=0) %}
    {% for r in results %}
      {% if r.status in ['error', 'fail'] %}{% set ns.bad = ns.bad + 1 %}
      {% elif r.status == 'skipped' %}{% set ns.skipped = ns.skipped + 1 %}
      {% else %}{% set ns.ok = ns.ok + 1 %}
      {% endif %}
    {% endfor %}

    {# --- 1. run log --- #}
    {% set run_log_sql %}
      insert into {{ target.database }}.audit.pipeline_run_log
      select '{{ invocation_id }}', current_timestamp(), '{{ var("business_date") }}'::date,
             '{{ "FAILED" if ns.bad > 0 else "SUCCESS" }}',
             {{ ns.ok }}, {{ ns.bad }}, {{ ns.skipped }}, '{{ flags.WHICH }}'
    {% endset %}
    {% do run_query(run_log_sql) %}

    {# --- 2. history tables: only rows of THIS run (guard on run_id), so a failed
           run that skipped the recon model never re-inserts stale rows --- #}
    {% set recon_sql %}
      insert into {{ target.database }}.audit.run_reconciliation_history
      select run_id, run_ts, business_date, dataset, records_received, accepted, rejected, duplicates, is_balanced
      from {{ target.database }}.gold.gold_run_reconciliation
      where run_id = '{{ invocation_id }}'
    {% endset %}
    {% set metrics_sql %}
      insert into {{ target.database }}.audit.run_metrics_history
      select run_id, run_ts, business_date, metric_name, metric_value
      from {{ target.database }}.gold.gold_run_metrics
      where run_id = '{{ invocation_id }}'
    {% endset %}
    {% do run_query(recon_sql) %}
    {% do run_query(metrics_sql) %}

  {% endif %}
{% endmacro %}
