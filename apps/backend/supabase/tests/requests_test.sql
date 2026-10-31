-- The request lifecycle: submission rules, pool eligibility, score routing and
-- the status state machine.
--
-- Properties this file pins:
--   * submit_request needs an active member, a payee, at least one piece of
--     evidence, and every redacted copy confirmed by the member;
--   * pool funding enforces the waiting period (cover start and, for vehicle
--     requests, the vehicle's registration), the per-request cap and the fund's
--     kinds; people-only requests skip pool rules;
--   * record_score routes, never refuses: >= min_score opens, below asks for
--     evidence, an open high-severity fraud signal sends it to a person;
--   * 'refused' is unreachable without a same-transaction review, invalid
--     transitions fail even for the owner, and request_events logs every change.
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

select pg_temp.member('00000000-0000-0000-0002-0000000000a1', 'CA');                          -- ana: covered 200 days
select pg_temp.member('00000000-0000-0000-0002-0000000000a2', 'CA', 'pending_verification');  -- ben: not verified
select pg_temp.member('00000000-0000-0000-0002-0000000000a3', 'CA');                          -- cy: covered 30 days
select pg_temp.member('00000000-0000-0000-0002-0000000000a4', 'CA');                          -- dee: someone else
select pg_temp.cover('00000000-0000-0000-0002-0000000000a1');
select pg_temp.cover('00000000-0000-0000-0002-0000000000a3', '30 days');
select pg_temp.payee('00000000-0000-0000-0002-0000000000c1');
select pg_temp.vehicle('00000000-0000-0000-0002-0000000000e1', '00000000-0000-0000-0002-0000000000a1');                        -- old car
select pg_temp.vehicle('00000000-0000-0000-0002-0000000000e2', '00000000-0000-0000-0002-0000000000a1', current_date - 30);    -- new car
select pg_temp.vehicle('00000000-0000-0000-0002-0000000000e3', '00000000-0000-0000-0002-0000000000a3');

-- Drafts that each break exactly one rule.
select pg_temp.request('00000000-0000-0000-0002-0000000000b1', '00000000-0000-0000-0002-0000000000a2', 'people', 100000, 'car_damage', '00000000-0000-0000-0002-0000000000c1');
select pg_temp.evidence('00000000-0000-0000-0002-0000000000b1');
select pg_temp.request('00000000-0000-0000-0002-0000000000b2', '00000000-0000-0000-0002-0000000000a1', 'people');  -- no payee
select pg_temp.evidence('00000000-0000-0000-0002-0000000000b2');
select pg_temp.request('00000000-0000-0000-0002-0000000000b3', '00000000-0000-0000-0002-0000000000a1', 'people', 100000, 'car_damage', '00000000-0000-0000-0002-0000000000c1');  -- no evidence
select pg_temp.request('00000000-0000-0000-0002-0000000000b4', '00000000-0000-0000-0002-0000000000a1', 'people', 100000, 'car_damage', '00000000-0000-0000-0002-0000000000c1');
select pg_temp.evidence('00000000-0000-0000-0002-0000000000b4');
select pg_temp.evidence('00000000-0000-0000-0002-0000000000b4', 'estimate', 'auto_done');  -- not confirmed yet
-- Pool requests.
select pg_temp.request('00000000-0000-0000-0002-0000000000b5', '00000000-0000-0000-0002-0000000000a3', 'pool', 100000, 'car_damage', '00000000-0000-0000-0002-0000000000c1', '00000000-0000-0000-0002-0000000000e3');  -- cover too new
select pg_temp.evidence('00000000-0000-0000-0002-0000000000b5');
select pg_temp.request('00000000-0000-0000-0002-0000000000b6', '00000000-0000-0000-0002-0000000000a1', 'pool', 100000, 'car_damage', '00000000-0000-0000-0002-0000000000c1', '00000000-0000-0000-0002-0000000000e2');  -- car too new
select pg_temp.evidence('00000000-0000-0000-0002-0000000000b6');
select pg_temp.request('00000000-0000-0000-0002-0000000000b7', '00000000-0000-0000-0002-0000000000a1', 'pool', 100000, 'car_damage', '00000000-0000-0000-0002-0000000000c1');  -- no car
select pg_temp.evidence('00000000-0000-0000-0002-0000000000b7');
select pg_temp.request('00000000-0000-0000-0002-0000000000b8', '00000000-0000-0000-0002-0000000000a1', 'pool', 1000001, 'car_damage', '00000000-0000-0000-0002-0000000000c1', '00000000-0000-0000-0002-0000000000e1');  -- over the cap
select pg_temp.evidence('00000000-0000-0000-0002-0000000000b8');
select pg_temp.request('00000000-0000-0000-0002-0000000000b9', '00000000-0000-0000-0002-0000000000a1', 'pool', 100000, 'down_payment', '00000000-0000-0000-0002-0000000000c1');  -- kind dropped below
select pg_temp.evidence('00000000-0000-0000-0002-0000000000b9');
-- Valid ones.
select pg_temp.request('00000000-0000-0000-0002-0000000000ba', '00000000-0000-0000-0002-0000000000a1', 'pool', 100000, 'car_damage', '00000000-0000-0000-0002-0000000000c1', '00000000-0000-0000-0002-0000000000e1');
select pg_temp.evidence('00000000-0000-0000-0002-0000000000ba');
select pg_temp.request('00000000-0000-0000-0002-0000000000bb', '00000000-0000-0000-0002-0000000000a3', 'people', 100000, 'car_damage', '00000000-0000-0000-0002-0000000000c1');
select pg_temp.evidence('00000000-0000-0000-0002-0000000000bb');
select pg_temp.request('00000000-0000-0000-0002-0000000000bc', '00000000-0000-0000-0002-0000000000a1', 'people', 100000, 'home_repair', '00000000-0000-0000-0002-0000000000c1');
select pg_temp.evidence('00000000-0000-0000-0002-0000000000bc');

-- A rule change is data: the home fund stops taking down payments.
update public.fund_settings set kinds = '{home_repair,mortgage_gap,loan_payoff}' where fund = 'home_fund';

-- --- submission ----------------------------------------------------------------
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0002-0000000000a2');
select throws_ok($$select public.submit_request('00000000-0000-0000-0002-0000000000b1')$$,
  '42501', 'verify your identity before submitting a request', 'a member who is not verified cannot submit');

select pg_temp.login('00000000-0000-0000-0002-0000000000a4');
select throws_ok($$select public.submit_request('00000000-0000-0000-0002-0000000000ba')$$,
  'P0002', 'request not found', 'a member cannot submit someone else''s request');

select pg_temp.login('00000000-0000-0000-0002-0000000000a1');
select throws_ok($$select public.submit_request('00000000-0000-0000-0002-0000000000b2')$$,
  '23514', 'name who should be paid (a shop, lender or seller)', 'submitting needs a payee');
select throws_ok($$select public.submit_request('00000000-0000-0000-0002-0000000000b3')$$,
  '23514', 'add at least one piece of evidence', 'submitting needs at least one piece of evidence');
select throws_ok($$select public.submit_request('00000000-0000-0000-0002-0000000000b4')$$,
  '23514', 'check and confirm the redacted copy of every piece of evidence',
  'submitting needs every redaction confirmed');
select throws_ok($$select public.submit_request('00000000-0000-0000-0002-0000000000b6')$$,
  '23514', 'the vehicle must be registered with Kinfold 60 days before the incident',
  'a pool car request needs the vehicle registered waiting_days before the incident');
select throws_ok($$select public.submit_request('00000000-0000-0000-0002-0000000000b7')$$,
  '23514', 'the vehicle must be registered with Kinfold 60 days before the incident',
  'a pool car request needs a covered vehicle');
select throws_ok($$select public.submit_request('00000000-0000-0000-0002-0000000000b8')$$,
  '23514', 'the pool pays at most 1000000 cents per request', 'pool requests are capped at max_request_cents');
select throws_ok($$select public.submit_request('00000000-0000-0000-0002-0000000000b9')$$,
  '23514', 'the community pool does not cover down_payment requests yet', 'pool requests must be a kind the fund covers');
select is(public.submit_request('00000000-0000-0000-0002-0000000000ba'), 'scoring'::public.request_status,
  'an eligible pool request moves to scoring');
select isnt((select submitted_at from public.requests where id = '00000000-0000-0000-0002-0000000000ba'), null,
  'submission stamps submitted_at');
select is(public.submit_request('00000000-0000-0000-0002-0000000000bc'), 'scoring'::public.request_status,
  'a people-only request submits');

select pg_temp.login('00000000-0000-0000-0002-0000000000a3');
select throws_ok($$select public.submit_request('00000000-0000-0000-0002-0000000000b5')$$,
  '23514', 'pool cover starts 60 days after your first payment; ask your people instead',
  'pool cover needs coverage_started_on + waiting_days before the incident');
select is(public.submit_request('00000000-0000-0000-0002-0000000000bb'), 'scoring'::public.request_status,
  'people-only requests skip the pool waiting period');

-- --- scoring (service role) ------------------------------------------------------
reset role;
select is(public.record_score('00000000-0000-0000-0002-0000000000ba', 70::smallint, '["photos match the estimate"]', 'm', '1', 'p1', 'h'),
  'open'::public.request_status, 'a score at min_score opens the request');
select is((select current_score from public.requests where id = '00000000-0000-0000-0002-0000000000ba'), 70::smallint,
  'the score is stored on the request');
select is(public.record_score('00000000-0000-0000-0002-0000000000bb', 69::smallint, '["no photos of the vehicle yet"]', 'm', '1', 'p1', 'h'),
  'needs_evidence'::public.request_status, 'a score below min_score asks for evidence, not refusal');
insert into private.fraud_signals (request_id, kind, severity)
values ('00000000-0000-0000-0002-0000000000bc', 'duplicate_photo', 'high');
select is(public.record_score('00000000-0000-0000-0002-0000000000bc', 99::smallint, '["strong evidence"]', 'm', '1', 'p1', 'h'),
  'in_review'::public.request_status, 'an open high-severity fraud signal sends even a high score to a person');
select throws_ok($$select public.record_score('00000000-0000-0000-0002-0000000000ba', 80::smallint, '["again"]', 'm', '1', 'p1', 'h')$$,
  '23514', 'request is not waiting for a score', 'a request not in scoring cannot be scored');
select is((select count(*) from public.scores
           where request_id in ('00000000-0000-0000-0002-0000000000ba', '00000000-0000-0000-0002-0000000000bb',
                                '00000000-0000-0000-0002-0000000000bc')), 3::bigint,
  'every score is recorded');

-- A resolved or low-severity signal doesn't divert.
select pg_temp.request('00000000-0000-0000-0002-0000000000bd', '00000000-0000-0000-0002-0000000000a1', 'people');
select pg_temp.move('00000000-0000-0000-0002-0000000000bd', 'scoring');
insert into private.fraud_signals (request_id, kind, severity, resolved_at) values
  ('00000000-0000-0000-0002-0000000000bd', 'duplicate_photo', 'high', now()),
  ('00000000-0000-0000-0002-0000000000bd', 'metadata_missing', 'low', null);
select is(public.record_score('00000000-0000-0000-0002-0000000000bd', 90::smallint, '["fine"]', 'm', '1', 'p1', 'h'),
  'open'::public.request_status, 'resolved or low-severity signals do not divert a request');

-- --- resubmission after more evidence ------------------------------------------
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0002-0000000000a3');
select is(public.submit_request('00000000-0000-0000-0002-0000000000bb'), 'scoring'::public.request_status,
  'a request needing evidence can be resubmitted');

-- --- the state machine (as the owner role, so the guard is the only check) ------
reset role;
select throws_ok(
  $$update public.requests set status = 'refused' where id = '00000000-0000-0000-0002-0000000000bc'$$,
  '42501', 'only a reviewer''s recorded decision can refuse a request',
  'even the service role cannot refuse without a same-transaction review');
select throws_ok(
  $$update public.requests set status = 'open' where id = '00000000-0000-0000-0002-0000000000b2'$$,
  '23514', 'a request cannot move from draft to open', 'a draft cannot skip scoring');
select throws_ok(
  $$update public.requests set status = 'paid' where id = '00000000-0000-0000-0002-0000000000ba'$$,
  '23514', 'a request cannot move from open to paid', 'an open request cannot jump to paid');
select throws_ok(
  $$update public.requests set status = 'refused' where id = '00000000-0000-0000-0002-0000000000ba'$$,
  '23514', 'a request cannot move from open to refused', 'refusal is only reachable from in_review');
select throws_ok(
  $$insert into public.requests (member_id, kind, title, amount_cents, incident_on, status)
    values ('00000000-0000-0000-0002-0000000000a1', 'car_damage', 'x', 100, current_date, 'open')$$,
  '23514', 'requests start as drafts', 'a request cannot be created past draft');

select results_eq(
  $$select from_status::text, to_status::text from public.request_events
    where request_id = '00000000-0000-0000-0002-0000000000ba' order by id$$,
  $$values (null::text, 'draft'::text), ('draft', 'scoring'), ('scoring', 'open')$$,
  'request_events records creation and every status change, in order');
select is((select actor from public.request_events
           where request_id = '00000000-0000-0000-0002-0000000000ba' and to_status = 'scoring'),
  '00000000-0000-0000-0002-0000000000a1'::uuid, 'the event records who made the change');
select results_eq(
  $$select from_status::text, to_status::text from public.request_events
    where request_id = '00000000-0000-0000-0002-0000000000bb' order by id$$,
  $$values (null::text, 'draft'::text), ('draft', 'scoring'), ('scoring', 'needs_evidence'), ('needs_evidence', 'scoring')$$,
  'a resubmitted request''s history shows the round trip');

-- --- withdrawal ------------------------------------------------------------------
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0002-0000000000a4');
select throws_ok($$select public.withdraw_request('00000000-0000-0000-0002-0000000000ba')$$,
  'P0002', 'request not found or can no longer be withdrawn', 'only the owner can withdraw');
select pg_temp.login('00000000-0000-0000-0002-0000000000a1');
select lives_ok($$select public.withdraw_request('00000000-0000-0000-0002-0000000000ba')$$,
  'the owner withdraws an open request');
select throws_ok($$select public.withdraw_request('00000000-0000-0000-0002-0000000000bc')$$,
  'P0002', 'request not found or can no longer be withdrawn', 'a request in review cannot be withdrawn');

reset role;
select * from finish();
rollback;
