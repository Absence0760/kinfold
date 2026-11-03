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

select is((select count(*) from jsonb_array_elements(public.grant_report())), 2::int,
  'the report aggregates by fund, source and federal flag — two pots');
select is((select e ->> 'amount_cents' from jsonb_array_elements(public.grant_report())
           where e ->> 'source' = 'foundation'), 250000::bigint,
  'the foundation row carries the money that source reported');
select is(public.ledger_balance('home_fund'::public.fund, 'available'), 0::bigint,
  'grant money still never joins the account the pool draws');

set local role anon;
select lives_ok($$select public.grant_report()$$, 'the public reads the grant report too');

rollback;