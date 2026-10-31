-- Row-level security and grants: who can read and write what, from the API.
--
-- Properties this file pins:
--   * a member sees only their own requests, evidence and subscriptions, and
--     never another member's draft;
--   * anon reads neither requests nor the board, but can read the open books;
--   * scores, reviews, pool runs, payouts and contributions are written only by
--     security definer functions or the service role, and a request's status
--     never changes through a direct client update (column grants);
--   * nothing in schema `private` is reachable, and the service-role-only
--     functions are not executable by signed-in members;
--   * balances and cover dates of other members don't leak through helpers.
-- Several of these expect "permission denied" (grant layer) rather than an
-- empty result (RLS), which is the stronger property.
begin;
select plan(33);

-- --- fixtures ------------------------------------------------------------------
-- Temporary helpers, gone at rollback. They run as postgres (the owner), standing
-- in for the service role and the partner webhooks; clients can't do any of this.

create function pg_temp.member(p_id uuid, p_region text default 'CA',
                               p_status public.member_status default 'active')
returns uuid language sql as $$
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
  values (p_id, 'Member ' || right(p_id::text, 4), p_region, p_status);
  select p_id;
$$;

-- An income check, a subscription and its first captured payment `p_ago` back:
-- cover starts on that date.
create function pg_temp.cover(p_member uuid, p_ago interval default '200 days')
returns void language sql as $$
  with iv as (
    insert into public.income_verifications (member_id, method, monthly_income_cents)
    values (p_member, 'bank_link', 400000) returning id
  ), sub as (
    insert into public.subscriptions (member_id, formula_version, income_verification_id, monthly_cents, starts_on)
    select p_member, 1, iv.id, 4000, (now() - p_ago)::date from iv returning id
  )
  insert into public.subscription_payments (subscription_id, member_id, period, amount_cents, status, captured_at)
  select sub.id, p_member, date_trunc('month', now() - p_ago)::date, 4000, 'captured', now() - p_ago from sub;
$$;

create function pg_temp.payee(p_id uuid, p_kind public.payee_kind default 'repair_shop',
                              p_status public.verification_status default 'verified')
returns uuid language sql as $$
  insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at)
  values (p_id, p_kind, 'Payee ' || right(p_id::text, 4), 'CA', p_status,
          case when p_status = 'verified' then 'acct_' || p_id::text end,
          case when p_status = 'verified' then now() end)
  returning id;
$$;

create function pg_temp.vehicle(p_id uuid, p_member uuid, p_registered date default current_date - 200)
returns uuid language sql as $$
  insert into public.covered_assets (id, member_id, kind, description, value_cents, registered_on, verified_at)
  values (p_id, p_member, 'vehicle', 'Test car', 1200000, p_registered, now())
  returning id;
$$;

create function pg_temp.request(p_id uuid, p_member uuid, p_funding public.funding_mode default 'pool',
                                p_amount bigint default 100000, p_kind public.request_kind default 'car_damage',
                                p_payee uuid default null, p_asset uuid default null)
returns uuid language sql as $$
  insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on, payee_id, asset_id)
  values (p_id, p_member, p_kind, p_funding, 'Test request', p_amount, current_date - 5, p_payee, p_asset)
  returning id;
$$;

create function pg_temp.evidence(p_request uuid, p_kind public.evidence_kind default 'photo',
                                 p_status public.redaction_status default 'confirmed')
returns uuid language sql as $$
  insert into public.evidence (request_id, kind, original_path, redacted_path, sha256, redaction_status)
  values (p_request, p_kind, gen_random_uuid()::text || '/original.jpg',
          case when p_status in ('auto_done', 'confirmed') then gen_random_uuid()::text || '/redacted.jpg' end,
          repeat('a', 64), p_status)
  returning id;
$$;

-- Walk a request through allowed transitions (the status guard still applies).
create function pg_temp.move(p_request uuid, variadic p_path public.request_status[])
returns void language plpgsql as $$
declare
  s public.request_status;
begin
  foreach s in array p_path loop
    update public.requests set status = s where id = p_request;
  end loop;
end $$;

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;

select pg_temp.member('00000000-0000-0000-0001-0000000000a1', 'CA');  -- alice
select pg_temp.member('00000000-0000-0000-0001-0000000000a2', 'NY');  -- bob
select pg_temp.member('00000000-0000-0000-0001-0000000000a3', 'TX');  -- carol
select pg_temp.cover('00000000-0000-0000-0001-0000000000a1');
select pg_temp.cover('00000000-0000-0000-0001-0000000000a2');
select pg_temp.payee('00000000-0000-0000-0001-0000000000c1');

-- alice: one draft with evidence. bob: a draft, and an open pool request on the board.
select pg_temp.request('00000000-0000-0000-0001-0000000000b1', '00000000-0000-0000-0001-0000000000a1', 'people');
select pg_temp.evidence('00000000-0000-0000-0001-0000000000b1');
select pg_temp.request('00000000-0000-0000-0001-0000000000b2', '00000000-0000-0000-0001-0000000000a2', 'people');
select pg_temp.evidence('00000000-0000-0000-0001-0000000000b2');
select pg_temp.request('00000000-0000-0000-0001-0000000000b3', '00000000-0000-0000-0001-0000000000a2', 'pool');
select pg_temp.move('00000000-0000-0000-0001-0000000000b3', 'scoring', 'open');
update public.requests set public_summary = 'Rear bumper after a parking-lot hit', current_score = 90,
  submitted_at = now()
where id = '00000000-0000-0000-0001-0000000000b3';

-- A loan between bob and carol; alice is not a party.
insert into public.family_loans (id, borrower_id, lender_id, principal_cents)
values ('00000000-0000-0000-0001-0000000000d1', '00000000-0000-0000-0001-0000000000a2',
        '00000000-0000-0000-0001-0000000000a3', 50000);

-- --- as alice ------------------------------------------------------------------
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0001-0000000000a1');

select is((select count(*) from public.requests), 1::bigint,
  'a member sees only their own requests');
select is((select count(*) from public.requests where id = '00000000-0000-0000-0001-0000000000b2'), 0::bigint,
  'a member cannot read another member''s draft');
select is((select count(*) from public.evidence), 1::bigint,
  'a member sees only evidence on their own requests');
select is((select array_agg(distinct member_id) from public.subscriptions),
  array['00000000-0000-0000-0001-0000000000a1'::uuid],
  'a member sees only their own subscription');
select is((select count(*) from public.subscription_payments
           where member_id <> '00000000-0000-0000-0001-0000000000a1'), 0::bigint,
  'a member sees no one else''s payments');
select is((select count(*) from public.board_requests where id = '00000000-0000-0000-0001-0000000000b3'), 1::bigint,
  'an active member sees another member''s open pool request on the board');
select is((select count(*) from public.family_loans), 0::bigint,
  'a member sees no loans they are not party to');

select throws_ok(
  $$insert into public.scores (request_id, score, reasons, model, model_version, prompt_version, inputs_sha256)
    values ('00000000-0000-0000-0001-0000000000b1', 99, '["looks fine"]', 'm', '1', '1', 'x')$$,
  '42501', 'permission denied for table scores', 'a client cannot insert a score');
select throws_ok(
  $$insert into public.reviews (request_id, reviewer_id, decision, reason)
    values ('00000000-0000-0000-0001-0000000000b3', '00000000-0000-0000-0001-0000000000a1', 'refuse', 'self-appointed reviewer')$$,
  '42501', 'permission denied for table reviews', 'a client cannot insert a review');
select throws_ok(
  $$insert into public.pool_runs (fund, available_cents, reserve_cents, settings, algorithm_version)
    values ('protection', 100, 0, '{}', 'x')$$,
  '42501', 'permission denied for table pool_runs', 'a client cannot insert a pool run');
select throws_ok(
  $$insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id)
    select '00000000-0000-0000-0001-0000000000b1', '00000000-0000-0000-0001-0000000000c1', 100, id
    from public.evidence limit 1$$,
  '42501', 'permission denied for table payouts', 'a client cannot insert a payout');
select throws_ok(
  $$insert into public.contributions (request_id, contributor_id, source, amount_cents)
    values ('00000000-0000-0000-0001-0000000000b3', '00000000-0000-0000-0001-0000000000a1', 'gift', 100)$$,
  '42501', 'permission denied for table contributions', 'a client cannot insert a contribution directly');
select throws_ok(
  $$update public.requests set status = 'scoring' where id = '00000000-0000-0000-0001-0000000000b1'$$,
  '42501', 'permission denied for table requests', 'a client cannot update a request''s status directly');
select throws_ok(
  $$update public.requests set current_score = 100 where id = '00000000-0000-0000-0001-0000000000b1'$$,
  '42501', 'permission denied for table requests', 'a client cannot set their own score');
select lives_ok(
  $$update public.requests set title = 'Front bumper' where id = '00000000-0000-0000-0001-0000000000b1'$$,
  'a client can still edit their own draft''s granted columns');

select throws_ok('select count(*) from private.audit_log', '42501', 'permission denied for schema private',
  'a client cannot read the audit log');
select throws_ok('select count(*) from private.fraud_signals', '42501', 'permission denied for schema private',
  'a client cannot read fraud signals');
select throws_ok('select count(*) from private.ledger_lines', '42501', 'permission denied for schema private',
  'a client cannot read the ledger');
select ok(not has_schema_privilege('authenticated', 'private', 'usage')
          and not has_schema_privilege('anon', 'private', 'usage'),
  'neither client role has usage on schema private');

select throws_ok(
  $$select public.record_score('00000000-0000-0000-0001-0000000000b1', 99::smallint, '["x"]', 'm', '1', '1', 'x')$$,
  '42501', 'permission denied for function record_score', 'record_score is not executable by authenticated');
select throws_ok(
  $$select public.run_pool_allocation('protection', 100000)$$,
  '42501', 'permission denied for function run_pool_allocation', 'run_pool_allocation is not executable by authenticated');
select throws_ok(
  $$select private.post_journal('protection', 'x', null, null, '[]')$$,
  '42501', 'permission denied for schema private', 'post_journal is not reachable by authenticated');

-- Region drives reviewer matching (anti-collusion), so members can't edit it.
select throws_ok(
  $$update public.members set region = 'NV' where id = '00000000-0000-0000-0001-0000000000a1'$$,
  '42501', 'permission denied for table members', 'a member cannot change their own region');
select lives_ok(
  $$update public.members set display_name = 'Alice B' where id = '00000000-0000-0000-0001-0000000000a1'$$,
  'a member can change their display name');

select is(public.loan_outstanding_cents('00000000-0000-0000-0001-0000000000d1'), null::bigint,
  'a member cannot read the balance of a loan they are not party to');
select is(public.coverage_started_on('00000000-0000-0000-0001-0000000000a2'), null::date,
  'a member cannot read when another member''s cover started');
select isnt(public.coverage_started_on('00000000-0000-0000-0001-0000000000a1'), null::date,
  'a member can read when their own cover started');

-- --- as bob, party to the loan --------------------------------------------------
select pg_temp.login('00000000-0000-0000-0001-0000000000a2');
select is(public.loan_outstanding_cents('00000000-0000-0000-0001-0000000000d1'), 50000::bigint,
  'the borrower reads their loan balance');

-- --- as an anonymous caller -----------------------------------------------------
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select throws_ok('select count(*) from public.requests', '42501', 'permission denied for table requests',
  'anon cannot read requests');
select throws_ok('select count(*) from public.board_requests', '42501', 'permission denied for view board_requests',
  'anon cannot read the request board');
select throws_ok('select count(*) from public.evidence', '42501', 'permission denied for table evidence',
  'anon cannot read evidence');
-- Reads every column: count(*) alone lets the planner skip the per-fund
-- subqueries, and with them the functions the view calls.
select is((select count(*) from public.public_stats
           where requests_paid >= 0 and paid_out_cents >= 0 and pool_runs >= 0 and allocated_cents >= 0), 2::bigint,
  'anon reads the open-books stats (one row per pooled fund)');
select is((select count(*) from public.fund_settings), 2::bigint,
  'anon reads the published fund rules');

reset role;
select * from finish();
rollback;
