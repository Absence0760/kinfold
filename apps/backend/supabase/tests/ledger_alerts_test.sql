-- Ledger difference alerts (20261102380000_ledger_alerts.sql).
--
-- Properties this file pins:
--   * a difference the reconcile job found is RECORDED, append-only, and reads
--     back to the service;
--   * a matching statement is not a difference (nothing spurious is stored);
--   * the alert is the service's: members have neither the write nor the read.
begin;
select plan(7);

-- --- the service records one difference ----------------------------------------

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.record_ledger_difference('protection', 'partner_cash',
  -800::bigint, -799::bigint)$$, 'the service records a one-cent difference');
select is((select count(*) from public.ledger_differences), 1::bigint, 'the alert landed once');
select is((select statement_cents from public.ledger_differences limit 1),
  -800::bigint, 'the statement figure is stored as the partner said it');

select throws_ok($$select public.record_ledger_difference('protection', 'partner_cash',
  -800::bigint, -800::bigint)$$, '23514',
  'a statement that matches the ledger is not an alert');
select is((select count(*) from public.ledger_differences), 1::bigint,
  'the refused match stored nothing');

-- --- the alert stays the service's ---------------------------------------------

select ok(has_function_privilege('service_role',
    'public.record_ledger_difference(public.fund, text, bigint, bigint)', 'execute')
    and not has_function_privilege('authenticated',
    'public.record_ledger_difference(public.fund, text, bigint, bigint)', 'execute'),
  'only the service records differences');
select ok(has_table_privilege('service_role', 'public.ledger_differences', 'select')
    and not has_table_privilege('authenticated', 'public.ledger_differences', 'select'),
  'only the service reads the alerts; members never see the books');

rollback;
