-- Hardening: the gaps closed by 20261030120400_hardening.sql.
--
-- Properties this file pins:
--   * close_account refuses while requests, appeals, loans or pledges are open,
--     then closes and scrubs the member, deletes their assets (keeping, scrubbed,
--     one named on a request), preferences and supporter rows, ends the
--     subscription and audit-logs it; deleting from auth.users is refused;
--   * capture_contributions (service only) needs a funded request whose loans
--     are all signed; paying a request out makes its signed loans active, and
--     only active or paused loans can be forgiven or paused;
--   * refunds_due (service only) lists captured money on requests that ended
--     unpaid; mark_refunded (service only) records it, idempotently;
--   * a refused request isn't re-reviewed; roles need an active member; one
--     appeal per refusal; a panel member doesn't decide an appeal on a request
--     they reviewed; the owner never sees reviewer_id (my_request_reviews);
--   * pauses end (borrower any time, service once the pause ran out, plus the
--     daily resume_ended_pauses); set_loan_terms only while proposed, clearing
--     signatures; installments fall on the payment day; the last payment marks
--     a loan repaid and a loan owing nothing never defaults;
--   * public.post_journal is service-only and needs two lines; record_score on
--     a missing request says so; request_raised_cents answers only those who can
--     see the request; pledges and pool grants wait for a verified payee.
-- Service-role steps run as the real service_role (set local role), so its
-- grants are under test too.
begin;
select plan(89);

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

-- As the service role itself (not postgres), so the grants are under test too.
-- Used inline: `reset role; set local role service_role; select pg_temp.as_service();`
create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

select pg_temp.member('00000000-0000-0000-0009-0000000000a1', 'CA');                          -- ola, requester
select pg_temp.member('00000000-0000-0000-0009-0000000000a2', 'CA');                          -- abe, her brother
select pg_temp.member('00000000-0000-0000-0009-0000000000a3', 'NY');                          -- sky, a stranger
select pg_temp.member('00000000-0000-0000-0009-0000000000a4', 'NY');                          -- rob, reviewer
select pg_temp.member('00000000-0000-0000-0009-0000000000a5', 'TX');                          -- pam, panel
select pg_temp.member('00000000-0000-0000-0009-0000000000a6', 'WA');                          -- wes, reviewer + panel
select pg_temp.member('00000000-0000-0000-0009-0000000000a7', 'CA');                          -- cal, closes his account
select pg_temp.member('00000000-0000-0000-0009-0000000000a8', 'NY', 'suspended');             -- sid, suspended reviewer
select pg_temp.member('00000000-0000-0000-0009-0000000000a9', 'CA', 'pending_verification');  -- una, unverified
insert into public.member_roles (member_id, role) values
  ('00000000-0000-0000-0009-0000000000a4', 'reviewer'),
  ('00000000-0000-0000-0009-0000000000a5', 'panel'),
  ('00000000-0000-0000-0009-0000000000a6', 'reviewer'),
  ('00000000-0000-0000-0009-0000000000a6', 'panel'),
  ('00000000-0000-0000-0009-0000000000a8', 'reviewer');
select pg_temp.payee('00000000-0000-0000-0009-0000000000c1');                 -- verified shop
select pg_temp.payee('00000000-0000-0000-0009-0000000000c2', 'repair_shop', 'pending');  -- still being verified

-- r1, r2: ola's, in review. r5: pam's own, in review.
select pg_temp.request(id, '00000000-0000-0000-0009-0000000000a1', 'people', 100000, 'car_damage',
                       '00000000-0000-0000-0009-0000000000c1')
from unnest(array['00000000-0000-0000-0009-0000000000b1', '00000000-0000-0000-0009-0000000000b2']::uuid[]) id;
select pg_temp.request('00000000-0000-0000-0009-0000000000b5', '00000000-0000-0000-0009-0000000000a5', 'people', 100000,
                       'car_damage', '00000000-0000-0000-0009-0000000000c1');
select pg_temp.move(id, 'scoring', 'in_review')
from unnest(array['00000000-0000-0000-0009-0000000000b1', '00000000-0000-0000-0009-0000000000b2',
                  '00000000-0000-0000-0009-0000000000b5']::uuid[]) id;

-- --- 5. roles count only for active members ----------------------------------------
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0009-0000000000a8');
select is(public.has_role('reviewer'), false, 'a suspended member''s roles do not count');
select throws_ok(
  $$select public.record_review('00000000-0000-0000-0009-0000000000b1', 'approve', 'Evidence is consistent.')$$,
  '42501', 'reviewers only', 'a suspended reviewer cannot review');

-- --- 4. a refused request is not re-decided directly -----------------------------------
select pg_temp.login('00000000-0000-0000-0009-0000000000a4');
select is(public.record_review('00000000-0000-0000-0009-0000000000b1', 'refuse', 'Estimate is for a different car.'),
  'refused'::public.request_status, 'fixture: a reviewer refuses r1');
select throws_ok(
  $$select public.record_review('00000000-0000-0000-0009-0000000000b1', 'approve', 'On second thoughts, fine.')$$,
  '23514', 'request is not reviewable in status refused', 'a reviewer cannot re-decide a refused request');
select lives_ok(
  $$select public.record_review('00000000-0000-0000-0009-0000000000b5', 'refuse', 'Photos predate the policy.')$$,
  'fixture: a reviewer refuses pam''s own request');
select pg_temp.login('00000000-0000-0000-0009-0000000000a6');
select lives_ok(
  $$select public.record_review('00000000-0000-0000-0009-0000000000b2', 'refuse', 'Invoice total does not match.')$$,
  'fixture: wes (reviewer and panel) refuses r2');

-- --- 7. one appeal per refusal ----------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0009-0000000000a1');
select isnt(public.file_appeal('00000000-0000-0000-0009-0000000000b1', 'The estimate was re-issued for my car.'), null,
  'the owner appeals the refusal');
select pg_temp.login('00000000-0000-0000-0009-0000000000a5');
select lives_ok(
  $$select public.decide_appeal((select id from public.appeals where request_id = '00000000-0000-0000-0009-0000000000b1'), false)$$,
  'the panel denies the appeal');
select pg_temp.login('00000000-0000-0000-0009-0000000000a1');
select throws_ok(
  $$select public.file_appeal('00000000-0000-0000-0009-0000000000b1', 'Appealing the same refusal again.')$$,
  '23505', 'this refusal has already been appealed', 'a denied appeal cannot be re-filed against the same refusal');

-- --- 6. a panel member never decides an appeal on a request they reviewed -----------------
select isnt(public.file_appeal('00000000-0000-0000-0009-0000000000b2', 'The invoice was corrected by the shop.'), null,
  'the owner appeals r2');
select pg_temp.login('00000000-0000-0000-0009-0000000000a6');
select throws_ok(
  $$select public.decide_appeal((select id from public.appeals where request_id = '00000000-0000-0000-0009-0000000000b2'), true)$$,
  '42501', 'you reviewed this request; another panel member decides the appeal',
  'a panel member cannot decide an appeal on a request they reviewed');
select pg_temp.login('00000000-0000-0000-0009-0000000000a5');
select lives_ok(
  $$select public.decide_appeal((select id from public.appeals where request_id = '00000000-0000-0000-0009-0000000000b2'), true)$$,
  'another panel member upholds it');
select pg_temp.login('00000000-0000-0000-0009-0000000000a4');
select is(public.record_review('00000000-0000-0000-0009-0000000000b2', 'refuse', 'Second look: still does not match.'),
  'refused'::public.request_status, 'the reopened request is refused again');
select pg_temp.login('00000000-0000-0000-0009-0000000000a1');
select isnt(public.file_appeal('00000000-0000-0000-0009-0000000000b2', 'Here is the shop''s letter.'), null,
  'a new refusal can be appealed once more');

-- --- 8. the member never learns who reviewed their request ---------------------------------
select is((select count(*) from public.reviews where request_id = '00000000-0000-0000-0009-0000000000b1'), 0::bigint,
  'the owner cannot read review rows (and so reviewer_id) on their request');
select results_eq(
  $$select decision::text, reason from public.my_request_reviews('00000000-0000-0000-0009-0000000000b1')$$,
  $$values ('refuse'::text, 'Estimate is for a different car.'::text)$$,
  'the owner reads each decision and its reason through my_request_reviews');
select is((select proargnames from pg_proc where oid = 'public.my_request_reviews(uuid)'::regprocedure),
  array['p_request', 'decision', 'reason', 'created_at'], 'my_request_reviews returns no reviewer id');
select pg_temp.login('00000000-0000-0000-0009-0000000000a3');
select throws_ok($$select * from public.my_request_reviews('00000000-0000-0000-0009-0000000000b1')$$,
  'P0002', 'request not found', 'nobody else reads a request''s reviews through it');
select pg_temp.login('00000000-0000-0000-0009-0000000000a5');
select is((select reviewer_id from public.reviews where request_id = '00000000-0000-0000-0009-0000000000b1'),
  '00000000-0000-0000-0009-0000000000a4'::uuid, 'the panel reads full review rows');
select is((select count(*) from public.reviews where request_id = '00000000-0000-0000-0009-0000000000b5'), 0::bigint,
  'a panel member cannot read the review rows on their own request');
select pg_temp.login('00000000-0000-0000-0009-0000000000a4');
select is((select count(*) from public.reviews where reviewer_id = '00000000-0000-0000-0009-0000000000a4'), 3::bigint,
  'a reviewer reads the reviews they wrote');

-- --- 14. record_score on a missing request ------------------------------------------------
reset role;
set local role service_role;
select pg_temp.as_service();
select throws_ok(
  $$select public.record_score('00000000-0000-0000-0009-00000000ffff', 80::smallint, '["x"]', 'm', '1', 'p1', 'h')$$,
  'P0002', 'request not found', 'record_score on a missing request says so');

-- --- 16. pledges and pool grants wait for a verified payee -----------------------------------
-- r3: on the board, payee pending. r4: on the board, payee verified. r6: a draft
-- naming the pending payee. r7: people-only, verified payee, abe is a supporter.
reset role;
select pg_temp.request('00000000-0000-0000-0009-0000000000b3', '00000000-0000-0000-0009-0000000000a1', 'pool', 50000,
                       'car_damage', '00000000-0000-0000-0009-0000000000c2');
select pg_temp.request('00000000-0000-0000-0009-0000000000b4', '00000000-0000-0000-0009-0000000000a1', 'pool', 50000,
                       'car_damage', '00000000-0000-0000-0009-0000000000c1');
select pg_temp.request('00000000-0000-0000-0009-0000000000b6', '00000000-0000-0000-0009-0000000000a1', 'people', 50000,
                       'car_damage', '00000000-0000-0000-0009-0000000000c2');
select pg_temp.evidence('00000000-0000-0000-0009-0000000000b6');
select pg_temp.request('00000000-0000-0000-0009-0000000000b7', '00000000-0000-0000-0009-0000000000a1', 'people', 100000,
                       'car_damage', '00000000-0000-0000-0009-0000000000c1');
select pg_temp.move(id, 'scoring', 'open')
from unnest(array['00000000-0000-0000-0009-0000000000b3', '00000000-0000-0000-0009-0000000000b4',
                  '00000000-0000-0000-0009-0000000000b7']::uuid[]) id;
update public.requests set public_summary = 'Front wing after a low-speed bump', current_score = 99,
  submitted_at = now()
where id in ('00000000-0000-0000-0009-0000000000b3', '00000000-0000-0000-0009-0000000000b4');
insert into public.request_supporters (request_id, member_id, relationship) values
  ('00000000-0000-0000-0009-0000000000b3', '00000000-0000-0000-0009-0000000000a2', 'brother'),
  ('00000000-0000-0000-0009-0000000000b7', '00000000-0000-0000-0009-0000000000a2', 'brother');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0009-0000000000a3');
select throws_ok($$select public.pledge('00000000-0000-0000-0009-0000000000b3', 1000, 'gift')$$,
  '23514', 'pledges open once the request''s payee is verified', 'a stranger cannot give before the payee is verified');
select pg_temp.login('00000000-0000-0000-0009-0000000000a2');
select throws_ok($$select public.pledge('00000000-0000-0000-0009-0000000000b3', 1000, 'loan')$$,
  '23514', 'pledges open once the request''s payee is verified', 'family cannot lend before the payee is verified');
select lives_ok($$select public.pledge('00000000-0000-0000-0009-0000000000b7', 1000, 'gift')$$,
  'family gives once the payee is verified');
select pg_temp.login('00000000-0000-0000-0009-0000000000a1');
select is(public.submit_request('00000000-0000-0000-0009-0000000000b6'), 'scoring'::public.request_status,
  'a request can still be submitted while its payee is verified in parallel');

reset role;
set local role service_role;
select pg_temp.as_service();
select set_config('test.run', public.run_pool_allocation('protection', 1000000)::text, true);
reset role;
select is((select count(*) from public.pool_allocations where run_id = current_setting('test.run')::uuid
           and request_id = '00000000-0000-0000-0009-0000000000b3'), 0::bigint,
  'the pool skips a request whose payee is not verified');
select is((select grant_cents from public.pool_allocations where run_id = current_setting('test.run')::uuid
           and request_id = '00000000-0000-0000-0009-0000000000b4'), 50000::bigint,
  'the pool pays an equal request with a verified payee');

-- --- 15. request_raised_cents answers only people who can see the request -----------------------
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0009-0000000000a1');
select is(public.request_raised_cents('00000000-0000-0000-0009-0000000000b7'), 1000::bigint, 'the owner reads raised');
select pg_temp.login('00000000-0000-0000-0009-0000000000a2');
select is(public.request_raised_cents('00000000-0000-0000-0009-0000000000b7'), 1000::bigint, 'a supporter reads raised');
select pg_temp.login('00000000-0000-0000-0009-0000000000a3');
select is(public.request_raised_cents('00000000-0000-0000-0009-0000000000b7'), null::bigint,
  'a stranger gets nothing for a request off the board');
select is(public.request_raised_cents('00000000-0000-0000-0009-0000000000b4'), 50000::bigint,
  'a verified member reads raised for a request on the board');
select pg_temp.login('00000000-0000-0000-0009-0000000000a9');
select is(public.request_raised_cents('00000000-0000-0000-0009-0000000000b4'), null::bigint,
  'an unverified member gets nothing, even for a board request');
reset role;
set local role service_role;
select pg_temp.as_service();
select is(public.request_raised_cents('00000000-0000-0000-0009-0000000000b7'), 1000::bigint, 'the service role reads raised');

-- --- 2 + 12. capture once every loan is signed; disbursed loans are active ---------------------
-- r8: abe gives 300.00 and lends 700.00, which funds it.
reset role;
select pg_temp.request('00000000-0000-0000-0009-0000000000b8', '00000000-0000-0000-0009-0000000000a1', 'people', 100000,
                       'car_damage', '00000000-0000-0000-0009-0000000000c1');
select pg_temp.move('00000000-0000-0000-0009-0000000000b8', 'scoring', 'open');
insert into public.request_supporters (request_id, member_id, relationship)
values ('00000000-0000-0000-0009-0000000000b8', '00000000-0000-0000-0009-0000000000a2', 'brother');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0009-0000000000a2');
select public.pledge('00000000-0000-0000-0009-0000000000b8', 30000, 'gift');
select public.pledge('00000000-0000-0000-0009-0000000000b8', 70000, 'loan');
select set_config('test.loan', (select id from public.family_loans
  where request_id = '00000000-0000-0000-0009-0000000000b8')::text, true);
select throws_ok($$select public.capture_contributions('00000000-0000-0000-0009-0000000000b8')$$,
  '42501', 'permission denied for function capture_contributions', 'capture_contributions is not executable by members');

reset role;
set local role service_role;
select pg_temp.as_service();
select throws_ok($$select public.capture_contributions('00000000-0000-0000-0009-0000000000b8')$$,
  '23514', 'every loan must be signed by both sides before money is captured',
  'nothing is captured while a loan behind the request is unsigned');
select throws_ok($$select public.capture_contributions('00000000-0000-0000-0009-0000000000b7')$$,
  '23514', 'only a funded request''s pledges are captured', 'a request that is not funded is not captured');

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0009-0000000000a2');
select public.set_loan_schedule(current_setting('test.loan')::uuid, 2, '2027-01-01');
select public.sign_loan(current_setting('test.loan')::uuid);
select pg_temp.login('00000000-0000-0000-0009-0000000000a1');
select public.sign_loan(current_setting('test.loan')::uuid);

reset role;
set local role service_role;
select pg_temp.as_service();
select is(public.capture_contributions('00000000-0000-0000-0009-0000000000b8'), 2,
  'once every loan is signed, the pledges are captured and counted');
reset role;
select is((select array_agg(distinct status) from public.contributions where request_id = '00000000-0000-0000-0009-0000000000b8'),
  array['captured'::public.contribution_status], 'every pledge on the request is now captured');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0009-0000000000a2');
select throws_ok($$select public.forgive_loan(current_setting('test.loan')::uuid, 1000, 2027)$$,
  '42501', 'only the lender can forgive an active loan', 'a signed loan not yet disbursed cannot be forgiven');
select pg_temp.login('00000000-0000-0000-0009-0000000000a1');
select throws_ok($$select public.pause_loan(current_setting('test.loan')::uuid, 1)$$,
  '23514', 'only an active loan can be paused', 'a signed loan not yet disbursed cannot be paused');

reset role;
insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id, status)
values ('00000000-0000-0000-0009-0000000000b8', '00000000-0000-0000-0009-0000000000c1', 100000,
        pg_temp.evidence('00000000-0000-0000-0009-0000000000b8', 'invoice'), 'sent');
select pg_temp.move('00000000-0000-0000-0009-0000000000b8', 'paid');
select is((select status from public.family_loans where id = current_setting('test.loan')::uuid),
  'active'::public.loan_status, 'paying the request out makes its signed loan active');

-- --- 11. paying the last cent marks the loan repaid -------------------------------------------
update public.loan_installments set paid_cents = amount_cents where loan_id = current_setting('test.loan')::uuid and seq = 1;
select is((select status from public.family_loans where id = current_setting('test.loan')::uuid),
  'active'::public.loan_status, 'a part-paid loan stays active');
update public.loan_installments set paid_cents = amount_cents where loan_id = current_setting('test.loan')::uuid and seq = 2;
select is((select (status, public.loan_outstanding_cents(id))::text from public.family_loans
           where id = current_setting('test.loan')::uuid), '(repaid,0)', 'paying the last installment marks it repaid');

-- An active loan recorded as fully paid (written directly, so no trigger ran).
insert into public.family_loans (id, borrower_id, lender_id, principal_cents, status, default_plan)
values ('00000000-0000-0000-0009-0000000000d9', '00000000-0000-0000-0009-0000000000a1',
        '00000000-0000-0000-0009-0000000000a2', 1000, 'active', 'forgive');
insert into public.loan_installments (loan_id, seq, due_on, amount_cents, paid_cents)
values ('00000000-0000-0000-0009-0000000000d9', 1, current_date - 30, 1000, 1000);
set local role service_role;
select pg_temp.as_service();
select throws_ok($$select public.apply_default_plan('00000000-0000-0000-0009-0000000000d9')$$,
  '23514', 'nothing is outstanding: the loan is repaid, not in default',
  'a default plan is never applied to a loan that owes nothing');

-- --- 3. refunds ---------------------------------------------------------------------------
-- r9: 1000.00 captured, then sent back to review and refused; a 50.00 pledge on it is released.
reset role;
select pg_temp.request('00000000-0000-0000-0009-0000000000b9', '00000000-0000-0000-0009-0000000000a1', 'people', 100000,
                       'car_damage', '00000000-0000-0000-0009-0000000000c1');
select pg_temp.move('00000000-0000-0000-0009-0000000000b9', 'scoring', 'open');
insert into public.contributions (id, request_id, contributor_id, source, amount_cents, status, partner_ref) values
  ('00000000-0000-0000-0009-0000000000e1', '00000000-0000-0000-0009-0000000000b9', '00000000-0000-0000-0009-0000000000a2',
   'gift', 95000, 'captured', 'pi_h_1'),
  ('00000000-0000-0000-0009-0000000000e2', '00000000-0000-0000-0009-0000000000b9', '00000000-0000-0000-0009-0000000000a3',
   'gift', 5000, 'pledged', null);
select pg_temp.move('00000000-0000-0000-0009-0000000000b9', 'in_review');
insert into public.reviews (request_id, reviewer_id, decision, reason)
values ('00000000-0000-0000-0009-0000000000b9', '00000000-0000-0000-0009-0000000000a4', 'refuse', 'Invoice is for another car.');
select pg_temp.move('00000000-0000-0000-0009-0000000000b9', 'refused');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0009-0000000000a2');
select throws_ok($$select count(*) from public.refunds_due$$, '42501', 'permission denied for view refunds_due',
  'members cannot read refunds_due');
select throws_ok($$select public.mark_refunded('00000000-0000-0000-0009-0000000000e1', 're_x')$$,
  '42501', 'permission denied for function mark_refunded', 'mark_refunded is not executable by members');

reset role;
set local role service_role;
select pg_temp.as_service();
select results_eq(
  $$select contribution_id, amount_cents, request_status::text from public.refunds_due
    where request_id = '00000000-0000-0000-0009-0000000000b9'$$,
  $$values ('00000000-0000-0000-0009-0000000000e1'::uuid, 95000::bigint, 'refused'::text)$$,
  'refunds_due lists captured money on a refused request, not released pledges');
select throws_ok(
  $$select public.mark_refunded((select id from public.contributions
     where request_id = '00000000-0000-0000-0009-0000000000b8' and source = 'gift'), 're_x')$$,
  'P0002', 'contribution not found or not due a refund', 'money on a paid request is not refundable');
select lives_ok($$select public.mark_refunded('00000000-0000-0000-0009-0000000000e1', 're_h_1')$$,
  'the service marks the refund done');
select lives_ok($$select public.mark_refunded('00000000-0000-0000-0009-0000000000e1', 're_h_1')$$,
  'a retried webhook for the same refund is a no-op');
select is((select (status, refund_partner_ref, refunded_at is not null, partner_ref)::text from public.contributions
           where id = '00000000-0000-0000-0009-0000000000e1'), '(refunded,re_h_1,t,pi_h_1)',
  'the refund keeps the capture reference and records its own');
select is((select count(*) from public.refunds_due where request_id = '00000000-0000-0000-0009-0000000000b9'), 0::bigint,
  'a refunded contribution leaves refunds_due');

-- --- 9. pauses end ------------------------------------------------------------------------
-- l1: active, being paused now. l2: paused, its pause ran out. l3: paused, pause still running.
reset role;
insert into public.family_loans (id, borrower_id, lender_id, principal_cents, status) values
  ('00000000-0000-0000-0009-0000000000d1', '00000000-0000-0000-0009-0000000000a1', '00000000-0000-0000-0009-0000000000a2', 60000, 'active'),
  ('00000000-0000-0000-0009-0000000000d2', '00000000-0000-0000-0009-0000000000a1', '00000000-0000-0000-0009-0000000000a2', 60000, 'paused'),
  ('00000000-0000-0000-0009-0000000000d3', '00000000-0000-0000-0009-0000000000a1', '00000000-0000-0000-0009-0000000000a2', 60000, 'paused'),
  ('00000000-0000-0000-0009-0000000000d4', '00000000-0000-0000-0009-0000000000a1', '00000000-0000-0000-0009-0000000000a2', 60000, 'paused');
insert into public.loan_pauses (loan_id, months, started_on, created_by) values
  ('00000000-0000-0000-0009-0000000000d2', 2, current_date - interval '4 months', '00000000-0000-0000-0009-0000000000a1'),
  ('00000000-0000-0000-0009-0000000000d3', 2, current_date - interval '1 month', '00000000-0000-0000-0009-0000000000a1'),
  ('00000000-0000-0000-0009-0000000000d4', 1, current_date - interval '1 month', '00000000-0000-0000-0009-0000000000a1');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0009-0000000000a1');
select public.pause_loan('00000000-0000-0000-0009-0000000000d1', 2);
reset role;
set local role service_role;
select pg_temp.as_service();
select throws_ok($$select public.resume_loan('00000000-0000-0000-0009-0000000000d1')$$,
  '23514', format('the borrower''s pause runs until %s', (current_date + interval '2 months')::date),
  'the service cannot end a pause that is still running');
select is(public.resume_loan('00000000-0000-0000-0009-0000000000d4'), 'active'::public.loan_status,
  'the service resumes a loan whose pause has run out');
reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0009-0000000000a2');
select throws_ok($$select public.resume_loan('00000000-0000-0000-0009-0000000000d1')$$,
  'P0002', 'loan not found', 'the lender cannot resume the borrower''s loan');
select throws_ok($$select public.resume_ended_pauses()$$,
  '42501', 'permission denied for function resume_ended_pauses', 'the daily job''s function is service-only');
select pg_temp.login('00000000-0000-0000-0009-0000000000a1');
select is(public.resume_loan('00000000-0000-0000-0009-0000000000d1'), 'active'::public.loan_status,
  'the borrower resumes early, at any time');
select throws_ok($$select public.resume_loan('00000000-0000-0000-0009-0000000000d1')$$,
  '23514', 'only a paused loan can be resumed', 'an active loan has nothing to resume');
reset role;
set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.resume_ended_pauses()$$, 'the daily job runs');
reset role;
select is((select array_agg(status order by id) from public.family_loans
           where id in ('00000000-0000-0000-0009-0000000000d2', '00000000-0000-0000-0009-0000000000d3')),
  array['active', 'paused']::public.loan_status[], 'the daily job resumes ended pauses and leaves running ones');

-- --- 10. loan terms, and installments on the payment day -------------------------------------
insert into public.family_loans (id, borrower_id, lender_id, principal_cents) values
  ('00000000-0000-0000-0009-0000000000d5', '00000000-0000-0000-0009-0000000000a1', '00000000-0000-0000-0009-0000000000a2', 90000);
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0009-0000000000a1');
select lives_ok($$select public.set_loan_schedule('00000000-0000-0000-0009-0000000000d5', 3, '2026-12-10')$$,
  'the borrower sets a schedule');
select results_eq(
  $$select due_on from public.loan_installments where loan_id = '00000000-0000-0000-0009-0000000000d5' order by seq$$,
  $$values ('2027-01-01'::date), ('2027-02-01'), ('2027-03-01')$$,
  'installments fall on the payment day (1st), the first no earlier than asked');
select public.sign_loan('00000000-0000-0000-0009-0000000000d5');
select pg_temp.login('00000000-0000-0000-0009-0000000000a3');
select throws_ok($$select public.set_loan_terms('00000000-0000-0000-0009-0000000000d5', 15, 3, 'mediate')$$,
  'P0002', 'loan not found', 'only the borrower or lender sets terms');
select pg_temp.login('00000000-0000-0000-0009-0000000000a2');
select throws_ok($$select public.set_loan_terms('00000000-0000-0000-0009-0000000000d5', 29, 3, 'mediate')$$,
  '23514', 'payment day must be 1 to 28', 'the payment day is 1 to 28');
select throws_ok($$select public.set_loan_terms('00000000-0000-0000-0009-0000000000d5', 15, 3, 'repay_on_sale')$$,
  '23514', 'repay on sale needs a loan secured by a lien', 'repay on sale needs a secured loan');
select lives_ok($$select public.set_loan_terms('00000000-0000-0000-0009-0000000000d5', 20, 2, 'forgive')$$,
  'the lender sets the terms while the loan is proposed');
select is((select (payment_day, pause_months_per_year, default_plan, borrower_signed_at is null, lender_signed_at is null)::text
           from public.family_loans where id = '00000000-0000-0000-0009-0000000000d5'), '(20,2,forgive,t,t)',
  'new terms are stored and clear both signatures');
select results_eq(
  $$select due_on from public.loan_installments where loan_id = '00000000-0000-0000-0009-0000000000d5' order by seq$$,
  $$values ('2027-01-20'::date), ('2027-02-20'), ('2027-03-20')$$,
  'an existing schedule moves to the new payment day');
select lives_ok($$select public.set_loan_schedule('00000000-0000-0000-0009-0000000000d5', 3, '2026-12-10')$$,
  'a new schedule after the terms change');
select results_eq(
  $$select due_on, amount_cents from public.loan_installments where loan_id = '00000000-0000-0000-0009-0000000000d5' order by seq$$,
  $$values ('2026-12-20'::date, 30000::bigint), ('2027-01-20', 30000), ('2027-02-20', 30000)$$,
  'each installment lands on the 20th and the total is still exactly the principal');
select public.sign_loan('00000000-0000-0000-0009-0000000000d5');
select pg_temp.login('00000000-0000-0000-0009-0000000000a1');
select public.sign_loan('00000000-0000-0000-0009-0000000000d5');
select throws_ok($$select public.set_loan_terms('00000000-0000-0000-0009-0000000000d5', 5, 2, 'forgive')$$,
  '23514', 'a signed loan''s terms can only change by agreement (restructure)', 'a signed loan''s terms are fixed');

-- --- 13. post_journal for the service role --------------------------------------------------
reset role;
select ok(not has_function_privilege('anon', 'public.post_journal(public.fund, text, uuid, text, jsonb)', 'execute')
          and not has_function_privilege('authenticated', 'public.post_journal(public.fund, text, uuid, text, jsonb)', 'execute')
          and has_function_privilege('service_role', 'public.post_journal(public.fund, text, uuid, text, jsonb)', 'execute'),
  'only the service role can execute public.post_journal');
set local role service_role;
select pg_temp.as_service();
select lives_ok(
  $$select public.post_journal('protection', 'subscription', null, 'pi_h_j1',
      '[{"code":"partner_cash","amount_cents":800},{"code":"available","amount_cents":-800}]');
    set constraints all immediate$$,
  'the service role posts a balanced journal through the public wrapper');
set constraints all deferred;
select throws_ok(
  $$select public.post_journal('protection', 'subscription', null, 'pi_h_j2', '[{"code":"partner_cash","amount_cents":0}]')$$,
  '23514', 'a journal needs at least two lines', 'a one-line journal is refused');
select throws_ok(
  $$select public.post_journal('protection', 'subscription', null, 'pi_h_j3', '[]')$$,
  '23514', 'a journal needs at least two lines', 'an empty journal is refused');

-- --- 1. closing an account -----------------------------------------------------------------
-- cal: cover and a subscription, two cars (one named on a request), allocation
-- preferences, a supporter of r7, an open request, and he lends on loan l6.
reset role;
select pg_temp.cover('00000000-0000-0000-0009-0000000000a7');
select pg_temp.vehicle('00000000-0000-0000-0009-0000000000f1', '00000000-0000-0000-0009-0000000000a7');
select pg_temp.vehicle('00000000-0000-0000-0009-0000000000f2', '00000000-0000-0000-0009-0000000000a7');
select pg_temp.request('00000000-0000-0000-0009-000000000b10', '00000000-0000-0000-0009-0000000000a7', 'people', 10000,
                       'car_damage', '00000000-0000-0000-0009-0000000000c1', '00000000-0000-0000-0009-0000000000f2');
select pg_temp.move('00000000-0000-0000-0009-000000000b10', 'scoring', 'open');
insert into public.allocation_preferences (member_id, target, weight_pct)
values ('00000000-0000-0000-0009-0000000000a7', 'car_damage', 100);
insert into public.request_supporters (request_id, member_id, relationship)
values ('00000000-0000-0000-0009-0000000000b7', '00000000-0000-0000-0009-0000000000a7', 'cousin');
insert into public.family_loans (id, borrower_id, lender_id, principal_cents, status)
values ('00000000-0000-0000-0009-0000000000d6', '00000000-0000-0000-0009-0000000000a1', '00000000-0000-0000-0009-0000000000a7', 5000, 'active');

select throws_ok($$delete from auth.users where id = '00000000-0000-0000-0009-0000000000a7'$$,
  '23503', null, 'deleting a member with a financial record from auth.users is refused');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0009-0000000000a7');
select throws_ok($$select public.close_account()$$,
  '23514', 'withdraw or finish your open requests before closing your account', 'an open request blocks closing');
select public.withdraw_request('00000000-0000-0000-0009-000000000b10');
select throws_ok($$select public.close_account()$$,
  '23514', 'settle the loans you owe or are owed before closing your account', 'a loan still being repaid blocks closing');
reset role;
update public.family_loans set status = 'repaid' where id = '00000000-0000-0000-0009-0000000000d6';
set local role authenticated;
select public.pledge('00000000-0000-0000-0009-0000000000b7', 2000, 'gift');
select throws_ok($$select public.close_account()$$,
  '23514', 'your pledges are still waiting to be collected', 'a pledge not yet collected blocks closing');
reset role;
update public.contributions set status = 'released'
where request_id = '00000000-0000-0000-0009-0000000000b7' and contributor_id = '00000000-0000-0000-0009-0000000000a7';

set local role authenticated;
select lives_ok($$select public.close_account(); set constraints all immediate$$, 'with nothing outstanding, the member closes');
set constraints all deferred;
select lives_ok($$update public.members set display_name = 'Cal again' where id = auth.uid()$$,
  'fixture: a closed member tries to rename themselves');
reset role;
select is((select (status, display_name)::text from public.members where id = '00000000-0000-0000-0009-0000000000a7'),
  '(closed,"Closed account")', 'the account is closed, its name scrubbed and kept scrubbed');
select results_eq(
  $$select id, description, removed_on is not null from public.covered_assets
    where member_id = '00000000-0000-0000-0009-0000000000a7'$$,
  $$values ('00000000-0000-0000-0009-0000000000f2'::uuid, 'Closed account'::text, true)$$,
  'unreferenced assets are deleted; one named on a request is scrubbed and kept');
select is((select count(*) from public.allocation_preferences where member_id = '00000000-0000-0000-0009-0000000000a7')
        + (select count(*) from public.request_supporters where member_id = '00000000-0000-0000-0009-0000000000a7'),
  0::bigint, 'allocation preferences and supporter rows are deleted');
select is((select count(*) from public.subscriptions where member_id = '00000000-0000-0000-0009-0000000000a7' and ends_on is null),
  0::bigint, 'the active subscription is ended');
select is((select count(*) from public.requests where member_id = '00000000-0000-0000-0009-0000000000a7')
        + (select count(*) from public.request_events r join public.requests q on q.id = r.request_id
           where q.member_id = '00000000-0000-0000-0009-0000000000a7'), 5::bigint,
  'the request and its history are kept');
select is((select count(*) from private.audit_log where action = 'account.closed'
           and target_id = '00000000-0000-0000-0009-0000000000a7' and actor = '00000000-0000-0000-0009-0000000000a7'),
  1::bigint, 'closing is audit-logged');
set local role authenticated;
select throws_ok($$select public.close_account()$$, '23514', 'this account is already closed', 'an account closes once');

reset role;
select * from finish();
rollback;
