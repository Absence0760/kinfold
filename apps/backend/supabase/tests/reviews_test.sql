-- Reviews and appeals: only a person refuses, in writing, and a panel hears appeals.
--
-- Properties this file pins:
--   * record_review needs the reviewer role, and a reviewer can't review their
--     own request or one from a member in their region (anti-collusion);
--   * refusing needs a reason of at least 10 characters and lands the request
--     in 'refused', taking two steps where the state machine needs them;
--   * approving a request whose pledges already cover it returns it to funded;
--   * only the owner of a refused request appeals, only the panel decides, never
--     their own appeal; upholding sends the request back to review;
--   * every decision is audit-logged.
begin;
select plan(27);

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

select pg_temp.member('00000000-0000-0000-0003-0000000000a1', 'CA');  -- olga, the requester
select pg_temp.member('00000000-0000-0000-0003-0000000000a2', 'NY');  -- rita, reviewer
select pg_temp.member('00000000-0000-0000-0003-0000000000a3', 'CA');  -- carl, reviewer in olga's region
select pg_temp.member('00000000-0000-0000-0003-0000000000a4', 'TX');  -- pia, appeal panel
select pg_temp.member('00000000-0000-0000-0003-0000000000a5', 'WA');  -- xan, plain member
insert into public.member_roles (member_id, role) values
  ('00000000-0000-0000-0003-0000000000a2', 'reviewer'),
  ('00000000-0000-0000-0003-0000000000a3', 'reviewer'),
  ('00000000-0000-0000-0003-0000000000a4', 'panel');

-- q1: olga, in review. q2: rita's own, in review. q3: olga, open. q4: olga, fully pledged.
select pg_temp.request('00000000-0000-0000-0003-0000000000b1', '00000000-0000-0000-0003-0000000000a1');
select pg_temp.move('00000000-0000-0000-0003-0000000000b1', 'scoring', 'in_review');
select pg_temp.request('00000000-0000-0000-0003-0000000000b2', '00000000-0000-0000-0003-0000000000a2');
select pg_temp.move('00000000-0000-0000-0003-0000000000b2', 'scoring', 'in_review');
select pg_temp.request('00000000-0000-0000-0003-0000000000b3', '00000000-0000-0000-0003-0000000000a1');
select pg_temp.move('00000000-0000-0000-0003-0000000000b3', 'scoring', 'open');
select pg_temp.request('00000000-0000-0000-0003-0000000000b4', '00000000-0000-0000-0003-0000000000a1', 'people', 50000);
select pg_temp.move('00000000-0000-0000-0003-0000000000b4', 'scoring', 'open');
insert into public.contributions (request_id, contributor_id, source, amount_cents)
values ('00000000-0000-0000-0003-0000000000b4', '00000000-0000-0000-0003-0000000000a5', 'gift', 50000);
select pg_temp.move('00000000-0000-0000-0003-0000000000b4', 'in_review');  -- funded, then sent back to a person
-- q5: pia's own request, refused by rita (review recorded in this transaction).
select pg_temp.request('00000000-0000-0000-0003-0000000000b5', '00000000-0000-0000-0003-0000000000a4');
select pg_temp.move('00000000-0000-0000-0003-0000000000b5', 'scoring', 'in_review');
insert into public.reviews (request_id, reviewer_id, decision, reason)
values ('00000000-0000-0000-0003-0000000000b5', '00000000-0000-0000-0003-0000000000a2', 'refuse', 'Photos predate the policy.');
select pg_temp.move('00000000-0000-0000-0003-0000000000b5', 'refused');

-- --- who may review ------------------------------------------------------------
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0003-0000000000a5');
select throws_ok(
  $$select public.record_review('00000000-0000-0000-0003-0000000000b1', 'approve', 'Evidence is consistent.')$$,
  '42501', 'reviewers only', 'a member without the reviewer role cannot review');

select pg_temp.login('00000000-0000-0000-0003-0000000000a2');
select throws_ok(
  $$select public.record_review('00000000-0000-0000-0003-0000000000b2', 'approve', 'Looks good to me.')$$,
  '42501', 'you cannot review your own request', 'a reviewer cannot review their own request');

select pg_temp.login('00000000-0000-0000-0003-0000000000a3');
select throws_ok(
  $$select public.record_review('00000000-0000-0000-0003-0000000000b1', 'approve', 'Evidence is consistent.')$$,
  '42501', 'requests are reviewed by someone outside the member''s region',
  'a reviewer cannot review a member from their own region');

-- --- refusing ---------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0003-0000000000a2');
select throws_ok(
  $$select public.record_review('00000000-0000-0000-0003-0000000000b1', 'refuse', 'no')$$,
  '23514', null, 'a refusal needs a written reason of at least 10 characters');
select is(public.record_review('00000000-0000-0000-0003-0000000000b1', 'refuse', 'Estimate is for a different car.'),
  'refused'::public.request_status, 'a reviewer refuses a request in review');
select is(public.record_review('00000000-0000-0000-0003-0000000000b3', 'refuse', 'Damage photos are stock images.'),
  'refused'::public.request_status, 'a reviewer refuses an open request');
select is(public.record_review('00000000-0000-0000-0003-0000000000b4', 'approve', 'Invoice matches the estimate.'),
  'funded'::public.request_status, 'approving a fully pledged request returns it to funded');

reset role;
select is((select status from public.requests where id = '00000000-0000-0000-0003-0000000000b1'),
  'refused'::public.request_status, 'the refused request is stored as refused');
select results_eq(
  $$select from_status::text, to_status::text from public.request_events
    where request_id = '00000000-0000-0000-0003-0000000000b3' and from_status is not null order by id$$,
  $$values ('draft'::text, 'scoring'::text), ('scoring', 'open'), ('open', 'in_review'), ('in_review', 'refused')$$,
  'refusing an open request goes open -> in_review -> refused');
select results_eq(
  $$select to_status::text from public.request_events
    where request_id = '00000000-0000-0000-0003-0000000000b4' order by id desc limit 3$$,
  $$values ('funded'::text), ('open'), ('in_review')$$,
  'approval walks in_review -> open -> funded');
select is((select count(*) from public.reviews where reviewer_id = '00000000-0000-0000-0003-0000000000a2'
           and request_id in ('00000000-0000-0000-0003-0000000000b1', '00000000-0000-0000-0003-0000000000b3',
                              '00000000-0000-0000-0003-0000000000b4')), 3::bigint,
  'every decision is written to reviews');
select is((select count(*) from private.audit_log
           where actor = '00000000-0000-0000-0003-0000000000a2' and action = 'review.refuse'
             and target = 'requests' and target_id = '00000000-0000-0000-0003-0000000000b1'
             and detail ->> 'reason' = 'Estimate is for a different car.'), 1::bigint,
  'a refusal is audit-logged with its reason');

-- --- appeals ---------------------------------------------------------------------
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0003-0000000000a5');
select throws_ok(
  $$select public.file_appeal('00000000-0000-0000-0003-0000000000b1', 'I think this was wrong.')$$,
  '42501', 'only a refused request of yours can be appealed', 'only the owner can appeal');

select pg_temp.login('00000000-0000-0000-0003-0000000000a1');
select throws_ok(
  $$select public.file_appeal('00000000-0000-0000-0003-0000000000b4', 'Appealing a funded request.')$$,
  '42501', 'only a refused request of yours can be appealed', 'only a refused request can be appealed');
select isnt(public.file_appeal('00000000-0000-0000-0003-0000000000b1', 'The estimate was re-issued for my car.'), null,
  'the owner appeals a refused request');
select isnt(public.file_appeal('00000000-0000-0000-0003-0000000000b3', 'The photos are mine, here are the originals.'), null,
  'the owner appeals a second refused request');
select throws_ok(
  $$select public.file_appeal('00000000-0000-0000-0003-0000000000b1', 'And once more for luck.')$$,
  '23505', null, 'a request has at most one open appeal');

select pg_temp.login('00000000-0000-0000-0003-0000000000a4');
select isnt(public.file_appeal('00000000-0000-0000-0003-0000000000b5', 'My photos are dated correctly.'), null,
  'a panel member can appeal their own refusal like anyone else');

select pg_temp.login('00000000-0000-0000-0003-0000000000a2');
select throws_ok(
  $$select public.decide_appeal((select id from public.appeals
     where request_id = '00000000-0000-0000-0003-0000000000b1'), true)$$,
  '42501', 'appeal panel only', 'a reviewer who is not on the panel cannot decide an appeal');

select pg_temp.login('00000000-0000-0000-0003-0000000000a4');
select throws_ok(
  $$select public.decide_appeal((select id from public.appeals
     where request_id = '00000000-0000-0000-0003-0000000000b5'), true)$$,
  '42501', 'you cannot decide your own appeal', 'a panel member cannot decide their own appeal');
select lives_ok(
  $$select public.decide_appeal((select id from public.appeals
     where request_id = '00000000-0000-0000-0003-0000000000b1'), true)$$,
  'the panel upholds an appeal');
select lives_ok(
  $$select public.decide_appeal((select id from public.appeals
     where request_id = '00000000-0000-0000-0003-0000000000b3'), false)$$,
  'the panel denies an appeal');
select throws_ok(
  $$select public.decide_appeal((select id from public.appeals
     where request_id = '00000000-0000-0000-0003-0000000000b1'), false)$$,
  'P0002', 'appeal not found or already decided', 'an appeal is decided once');

reset role;
select is((select status from public.requests where id = '00000000-0000-0000-0003-0000000000b1'),
  'in_review'::public.request_status, 'an upheld appeal sends the request back to review');
select is((select status from public.requests where id = '00000000-0000-0000-0003-0000000000b3'),
  'refused'::public.request_status, 'a denied appeal leaves the request refused');
select ok((select status = 'upheld' and decided_by = '00000000-0000-0000-0003-0000000000a4' and decided_at is not null
           from public.appeals where request_id = '00000000-0000-0000-0003-0000000000b1'),
  'the appeal records the outcome, who decided and when');
select is((select array_agg(action order by id) from private.audit_log
           where actor = '00000000-0000-0000-0003-0000000000a4' and target = 'appeals'),
  array['appeal.upheld', 'appeal.denied'], 'appeal decisions are audit-logged');

select * from finish();
rollback;
