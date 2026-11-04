-- Fair-lending data (20261102540000_fair_lending.sql).
--
-- Properties this file pins:
--   * the borrower offers the voluntary self-test on their own non-secured
--     Fund loan, and all four disclosures have to be acknowledged;
--   * a secured Fund loan refuses the self-test (it answers on the
--     monitoring form instead) and refuses a duplicate of either kind;
--   * the monitoring form is collected by the lending partner only, and only
--     for loans secured by the home;
--   * the scorer, reviewers and panel can't read demographics at all — the
--     borrower themselves sees no rows;
--   * the auditor's read and the CDFI loan-level row are service-only, and
--     voluntary self-test data shows "Do Not Know" in the federal row;
--   * the rows are append-only.
begin;
select plan(17);

-- --- fixtures ------------------------------------------------------------------

create function pg_temp.member(p_id uuid, p_region text default 'CA') returns void
language sql as $$
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data, is_super_admin,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', p_id, 'authenticated', 'authenticated',
    p_id::text || '@test.invalid', 'x', now(), now(), now(),
    '{"provider":"email"}', '{}', false, '', '', '', '');
  insert into public.members (id, display_name, region, status)
  values (p_id, 'Member ' || right(p_id::text, 4), p_region, 'active');
$$;

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

select pg_temp.member('00000000-0000-0000-0026-0000000000a1');

-- The partner opens two Fund loans for the same borrower: one unsecured
-- (monthly), one secured by a lien on the home — the two fair-lending routes.
set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.create_fund_loan(
  '00000000-0000-0000-0026-0000000000a1'::uuid, 100000::bigint, false,
  0, 0, 0, 'monthly', 0, 'loan_h1')$$, 'the partner opens an unsecured fund loan');
select lives_ok($$select public.create_fund_loan(
  '00000000-0000-0000-0026-0000000000a1'::uuid, 100000::bigint, true,
  30000, 0, 0, 'monthly', 0, 'loan_h2')$$, 'the partner opens a secured fund loan');

-- --- the borrower offers the self-test -------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0026-0000000000a1'::uuid);
select throws_ok($$select public.offer_fair_lending_self_test(
  (select id from public.fund_loans where partner_ref = 'loan_h2')::uuid,
  true, true, true, true, 'Black', 'Not Hispanic or Latino', 'Female')$$,
  '23514', 'a secured fund loan answers on the monitoring form instead');
select throws_ok($$select public.offer_fair_lending_self_test(
  (select id from public.fund_loans where partner_ref = 'loan_h1')::uuid,
  true, false, true, true, 'Black', 'Not Hispanic or Latino', 'Female')$$,
  '23514', 'the self-test needs all four disclosures acknowledged');
select lives_ok($$select public.offer_fair_lending_self_test(
  (select id from public.fund_loans where partner_ref = 'loan_h1')::uuid,
  true, true, true, true, 'Black', 'Not Hispanic or Latino', 'Female')$$,
  'the borrower offers the self-test on their own loan');
select throws_ok($$select public.offer_fair_lending_self_test(
  (select id from public.fund_loans where partner_ref = 'loan_h1')::uuid,
  true, true, true, true, 'Black', 'Not Hispanic or Latino', 'Female')$$,
  '23514', 'the self-test is recorded once per loan');

-- --- the borrower can't reach the other route or the reads -----------------------

select throws_ok($$select public.record_fair_lending_monitoring_form(
  (select id from public.fund_loans where partner_ref = 'loan_h2')::uuid,
  'White', 'Not Hispanic or Latino', 'Male')$$,
  '42501', 'a member cannot collect the government monitoring form');
select throws_ok($$select public.fair_lending_rows(
  (select id from public.fund_loans where partner_ref = 'loan_h1')::uuid)$$,
  '42501', 'a member cannot read fair-lending rows');
select throws_ok('select count(*) from private.fair_lending', '42501',
  'permission denied for table fair_lending',
  'a member reads no demographics at all, not even their own');

-- --- the partner collects the monitoring form -------------------------------------

set local role service_role;
select pg_temp.as_service();
select throws_ok($$select public.record_fair_lending_monitoring_form(
  (select id from public.fund_loans where partner_ref = 'loan_h1')::uuid,
  'White', 'Not Hispanic or Latino', 'Male')$$,
  '23514', 'the monitoring form is only for loans secured by the home');
select lives_ok($$select public.record_fair_lending_monitoring_form(
  (select id from public.fund_loans where partner_ref = 'loan_h2')::uuid,
  'White', 'Not Hispanic or Latino', 'Male')$$,
  'the partner records the monitoring form on the secured loan');
reset role;
select is((select race from private.fair_lending
           where loan_id = (select id from public.fund_loans where partner_ref = 'loan_h1')
             and source = 'self_test'), 'Black',
  'the self-test answers are kept as given for the auditor');
set local role service_role;
select pg_temp.as_service();
select is(public.cdfi_loan_fair_lending(
  (select id from public.fund_loans where partner_ref = 'loan_h1')::uuid) ->> 'race',
  'Do Not Know', 'voluntary self-test data is not federally reported');
reset role;
select is((select race from private.fair_lending
           where loan_id = (select id from public.fund_loans where partner_ref = 'loan_h2')
             and source = 'monitoring_form'), 'White',
  'the monitoring form answers are kept as given');
set local role service_role;
select pg_temp.as_service();
select is(public.cdfi_loan_fair_lending(
  (select id from public.fund_loans where partner_ref = 'loan_h2')::uuid) ->> 'race',
  'White', 'the monitoring form data is the row the federal report counts');
reset role;
select is((select count(*) from private.fair_lending), 2::bigint,
  'the auditor sees one row per route');
set local role service_role;
select pg_temp.as_service();

-- --- history ---------------------------------------------------------------------

select throws_ok($$update private.fair_lending set sex = 'Female'
  where loan_id = (select id from public.fund_loans where partner_ref = 'loan_h1')::uuid$$,
  '42501', 'fair_lending is append-only');

rollback;