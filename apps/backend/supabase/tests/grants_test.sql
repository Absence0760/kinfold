-- Grant funding (20261102550000_grant_funding.sql).
--
-- Properties this file pins:
--   * the partner reports grant money in, and each source's money lands in a
--     labelled pot of its own — never in `available`, the account pool
--     allocations draw from;
--   * federal money gets its own pot and never enters insured cover, while a
--     non-federal grant for the protection fund lands in that fund's dues pot
--     (which only ever pays premiums);
--   * a replayed report with the same partner reference is a no-op answering
--     with the row it already made, so no money is double-counted;
--   * grant rows are append-only, and a blank reference or a non-positive
--     amount is refused; members can't report money in or write the rows.
begin;
select plan(19);

-- --- fixtures ------------------------------------------------------------------

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
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
select is(public.ledger_balance('home_fund'::public.fund, 'grants'), 250000::bigint,
  'the grant money joins the labelled grants pot');
select is(public.ledger_balance('home_fund'::public.fund, 'federal_grants'), 0::bigint,
  'the federal pot stays empty until federal money arrives');
select lives_ok($$select public.record_grant('home_fund'::public.fund, 'local_government'::public.grant_source,
  'City HOME match', true, 500000::bigint, 'grant_r2')$$,
  'a local-government grant marked federal lands in the federal pot');
select is(public.ledger_balance('home_fund'::public.fund, 'federal_grants'), 500000::bigint,
  'federally funded money is its own pot');
select is(public.ledger_balance('home_fund'::public.fund, 'grants'), 250000::bigint,
  'the two pots never mix');
select lives_ok($$select public.record_grant('protection'::public.fund, 'employer'::public.grant_source,
  'Employer dues pot', false, 40000::bigint, 'grant_r3')$$,
  'a non-federal grant for the protection fund lands in the dues pot');
select is(public.ledger_balance('protection'::public.fund, 'dues'), 40000::bigint,
  'grant money pays dues, which only ever pays premiums');
select is(public.ledger_balance('protection'::public.fund, 'available'), 0::bigint,
  'grant money never reaches the account pool allocations draw from');

-- --- the refusals ----------------------------------------------------------------

select throws_ok($$select public.record_grant('protection'::public.fund, 'local_government'::public.grant_source,
  'Federal cover money', true, 40000::bigint, 'grant_r4')$$,
  '23514', 'federal money never enters insured cover');
select throws_ok($$select public.record_grant('home_fund'::public.fund, 'foundation'::public.grant_source,
  '', false, 250000::bigint, 'grant_r5')$$,
  '23514', 'a grant report names the award it came from');
select throws_ok($$select public.record_grant('home_fund'::public.fund, 'foundation'::public.grant_source,
  'Blank reference', false, 250000::bigint, '')$$,
  '23514', 'a grant report needs the partner''s reference');

-- --- replaying the same report adds no money -------------------------------------

select is(public.record_grant('home_fund'::public.fund, 'foundation'::public.grant_source,
  'Kinfold Home Fund charity', false, 999999::bigint, 'grant_r1'),
  (select id from public.grants where partner_ref = 'grant_r1'),
  'a replayed report answers with the row it already made');
select is(public.ledger_balance('home_fund'::public.fund, 'grants'), 250000::bigint,
  'the replayed report counted no money again');
select throws_ok($$insert into public.grants (fund, source, programme, federal, amount_cents, partner_ref)
  values ('home_fund'::public.fund, 'foundation'::public.grant_source, 'Zero money', false, 0::bigint, 'grant_r6')$$,
  '23514', 'a grant row refuses a non-positive amount at the table too');

-- --- history and access -----------------------------------------------------------

select throws_ok($$update public.grants set amount_cents = 1
  where partner_ref = 'grant_r1'$$,
  '42501', 'grants is append-only');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000001'::uuid);
select throws_ok($$select public.record_grant('home_fund'::public.fund, 'foundation'::public.grant_source,
  'Member try', false, 250000::bigint, 'grant_r7')$$,
  '42501', 'a member cannot report grant money');
select throws_ok($$insert into public.grants (fund, source, programme, federal, amount_cents, partner_ref)
  values ('home_fund'::public.fund, 'foundation'::public.grant_source, 'Member write', false, 1::bigint, 'grant_r8')$$,
  '42501', 'permission denied for table grants', 'a member cannot write grant rows');
select is((select count(*) from public.grants where fund = 'home_fund'), 2::bigint,
  'members read who funded the cooperative');

rollback;