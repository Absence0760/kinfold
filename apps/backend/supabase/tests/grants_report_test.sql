-- The grant report (20261102560000_grant_report.sql).
--
-- Properties this file pins:
--   * the report aggregates grant money by fund, source and federal flag, so
--     funders see what their money funded without any grant-to-allocation
--     link;
--   * everyone — anon, members and the service — can read it;
--   * grant money still never joins `available`, the account the pool draws.
begin;
select plan(6);

-- Ledger figures are read as what this file moved: the seed's own journals are
-- already on the books (dues, premiums, payouts, pool grants), and a balance
-- read whole would count them too. The baseline is every account's balance
-- before this file posts anything.
create temp table seed_ledger on commit drop as
  select a.fund, a.code, public.ledger_balance(a.fund, a.code) as cents
  from (select distinct fund, code from private.ledger_accounts) a;
grant select on seed_ledger to public;
create function pg_temp.moved(p_fund public.fund, p_code text) returns bigint language sql as $$
  select public.ledger_balance(p_fund, p_code)
       - coalesce((select cents from pg_temp.seed_ledger where fund = p_fund and code = p_code), 0)
$$;

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

-- --- the partner reports money in -----------------------------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.record_grant('home_fund'::public.fund, 'foundation'::public.grant_source,
  'Kinfold Home Fund charity', false, 250000::bigint, 'grant_r1')$$,
  'a foundation grant lands in the Home Fund grants pot');
select lives_ok($$select public.record_grant('home_fund'::public.fund, 'local_government'::public.grant_source,
  'City HOME match', true, 500000::bigint, 'grant_r2')$$,
  'a local-government grant marked federal lands in the federal pot');

-- --- the report ---------------------------------------------------------------

select is((select count(*) from jsonb_array_elements(public.grant_report())), 2::bigint,
  'the report aggregates by fund, source and federal flag — two pots');
select is((select (e ->> 'amount_cents')::bigint from jsonb_array_elements(public.grant_report()) as e
           where e ->> 'source' = 'foundation'), 250000::bigint,
  'the foundation row carries the money that source reported');
select is(pg_temp.moved('home_fund'::public.fund, 'available'), 0::bigint,
  'grant money still never joins the account the pool draws');

set local role anon;
select lives_ok($$select public.grant_report()$$, 'the public reads the grant report too');

rollback;