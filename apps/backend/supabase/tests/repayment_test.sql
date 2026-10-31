-- Repayment, hardship and the giving record.
--
-- Properties this file pins:
--   * a pause within the agreed allowance pushes every unpaid installment back
--     by N months, leaves paid ones alone and never changes the total owed;
--     beyond the allowance it fails, and only the borrower can pause;
--   * 'repay_on_sale' needs a secured loan;
--   * apply_default_plan (service role only) forgives exactly what's left under
--     'forgive', and marks 'mediate' / 'repay_on_sale' loans defaulted, with an
--     audit row either way;
--   * loan_missed_installments shows only installments more than 10 days
--     overdue on loans still collecting, and only to the borrower and lender;
--   * my_giving_record shows only the caller's own captured figures;
--   * pool_requests_paid_3y counts only paid pool requests whose payout went out
--     in the last three years, and a member can ask only about themselves.
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

-- A request taken all the way to paid, its payout sent at `p_paid_at`.
create function pg_temp.paid_request(p_id uuid, p_member uuid, p_funding public.funding_mode, p_paid_at timestamptz)
returns uuid language sql as $$
  select pg_temp.request(p_id, p_member, p_funding, 50000, 'car_damage', '00000000-0000-0000-0008-0000000000c1');
  select pg_temp.move(p_id, 'scoring', 'open');
  insert into public.contributions (request_id, contributor_id, source, amount_cents, status)
  values (p_id, '00000000-0000-0000-0008-0000000000a3', 'gift', 50000, 'captured');
  insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id, status, created_at)
  values (p_id, '00000000-0000-0000-0008-0000000000c1', 50000, pg_temp.evidence(p_id, 'invoice'), 'sent', p_paid_at);
  select pg_temp.move(p_id, 'paid');
  select p_id;
$$;

select pg_temp.member('00000000-0000-0000-0008-0000000000a1', 'CA');  -- bea, borrower
select pg_temp.member('00000000-0000-0000-0008-0000000000a2', 'CA');  -- len, lender
select pg_temp.member('00000000-0000-0000-0008-0000000000a3', 'NY');  -- xia, someone else
select pg_temp.member('00000000-0000-0000-0008-0000000000a4', 'TX');  -- pat, pool claimant
select pg_temp.payee('00000000-0000-0000-0008-0000000000c1');

-- d1: active, 4 x 300.00, the first paid, the second 20 days late.
insert into public.family_loans (id, borrower_id, lender_id, principal_cents, status, payment_day)
values ('00000000-0000-0000-0008-0000000000d1', '00000000-0000-0000-0008-0000000000a1',
        '00000000-0000-0000-0008-0000000000a2', 120000, 'active', 15);
insert into public.loan_installments (loan_id, seq, due_on, amount_cents, paid_cents) values
  ('00000000-0000-0000-0008-0000000000d1', 1, current_date - 50, 30000, 30000),
  ('00000000-0000-0000-0008-0000000000d1', 2, current_date - 20, 30000, 0),
  ('00000000-0000-0000-0008-0000000000d1', 3, current_date + 10, 30000, 0),
  ('00000000-0000-0000-0008-0000000000d1', 4, current_date + 40, 30000, 0);
-- d7: still proposed.
insert into public.family_loans (id, borrower_id, lender_id, principal_cents)
values ('00000000-0000-0000-0008-0000000000d7', '00000000-0000-0000-0008-0000000000a1',
        '00000000-0000-0000-0008-0000000000a2', 1000);

-- --- pausing -----------------------------------------------------------------------
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0008-0000000000a3');
select throws_ok($$select public.pause_loan('00000000-0000-0000-0008-0000000000d1', 1)$$,
  'P0002', 'loan not found', 'a stranger cannot pause a loan');
select pg_temp.login('00000000-0000-0000-0008-0000000000a2');
select throws_ok($$select public.pause_loan('00000000-0000-0000-0008-0000000000d1', 1)$$,
  'P0002', 'loan not found', 'the lender cannot pause the borrower''s repayments');

select pg_temp.login('00000000-0000-0000-0008-0000000000a1');
select throws_ok($$select public.pause_loan('00000000-0000-0000-0008-0000000000d7', 1)$$,
  '23514', 'only an active loan can be paused', 'a loan not yet in force cannot be paused');
select lives_ok($$select public.pause_loan('00000000-0000-0000-0008-0000000000d1', 2, 'Hours cut at work')$$,
  'the borrower pauses two months, within the allowance');
select results_eq(
  $$select seq, due_on from public.loan_installments
    where loan_id = '00000000-0000-0000-0008-0000000000d1' order by seq$$,
  $$values (1, current_date - 50),
           (2, (current_date - 20 + interval '2 months')::date),
           (3, (current_date + 10 + interval '2 months')::date),
           (4, (current_date + 40 + interval '2 months')::date)$$,
  'a pause shifts every unpaid installment by N months and leaves paid ones alone');
select is((select sum(amount_cents) from public.loan_installments where loan_id = '00000000-0000-0000-0008-0000000000d1'),
  120000::numeric, 'a pause never changes the total scheduled');
select is(public.loan_outstanding_cents('00000000-0000-0000-0008-0000000000d1'), 90000::bigint,
  'a pause never changes what is owed');
select is((select status from public.family_loans where id = '00000000-0000-0000-0008-0000000000d1'),
  'paused'::public.loan_status, 'the loan shows as paused');
select throws_ok($$select public.pause_loan('00000000-0000-0000-0008-0000000000d1', 2)$$,
  '23514', 'this loan allows 3 pause months a year (2 used); ask your lender to restructure',
  'a pause beyond the allowance in 12 months fails');
select lives_ok($$select public.pause_loan('00000000-0000-0000-0008-0000000000d1', 1)$$,
  'a pause up to exactly the allowance is fine');
select throws_ok($$select public.pause_loan('00000000-0000-0000-0008-0000000000d1', 1)$$,
  '23514', 'this loan allows 3 pause months a year (3 used); ask your lender to restructure',
  'once the allowance is used, no more pauses this year');

select pg_temp.login('00000000-0000-0000-0008-0000000000a2');
select is((select sum(months) from public.loan_pauses where loan_id = '00000000-0000-0000-0008-0000000000d1'),
  3::bigint, 'the lender sees the pauses');
select pg_temp.login('00000000-0000-0000-0008-0000000000a3');
select is((select count(*) from public.loan_pauses), 0::bigint, 'a stranger sees no pauses');

-- --- default plans ---------------------------------------------------------------------
reset role;
select throws_ok(
  $$insert into public.family_loans (borrower_id, lender_id, principal_cents, default_plan)
    values ('00000000-0000-0000-0008-0000000000a1', '00000000-0000-0000-0008-0000000000a2', 1000, 'repay_on_sale')$$,
  '23514', null, 'repay_on_sale needs a secured loan');
select lives_ok(
  $$insert into public.family_loans (borrower_id, lender_id, principal_cents, default_plan, secured)
    values ('00000000-0000-0000-0008-0000000000a1', '00000000-0000-0000-0008-0000000000a2', 1000, 'repay_on_sale', true)$$,
  'a secured loan can repay on sale');

-- d2 forgive: 1000.00, 300.00 paid, 700.00 overdue. d3 mediate. d4 repay on sale.
insert into public.family_loans (id, borrower_id, lender_id, principal_cents, status, default_plan, secured) values
  ('00000000-0000-0000-0008-0000000000d2', '00000000-0000-0000-0008-0000000000a1', '00000000-0000-0000-0008-0000000000a2', 100000, 'active', 'forgive', false),
  ('00000000-0000-0000-0008-0000000000d3', '00000000-0000-0000-0008-0000000000a1', '00000000-0000-0000-0008-0000000000a2', 50000, 'active', 'mediate', false),
  ('00000000-0000-0000-0008-0000000000d4', '00000000-0000-0000-0008-0000000000a1', '00000000-0000-0000-0008-0000000000a2', 50000, 'paused', 'repay_on_sale', true);
insert into public.loan_installments (loan_id, seq, due_on, amount_cents, paid_cents) values
  ('00000000-0000-0000-0008-0000000000d2', 1, current_date - 60, 30000, 30000),
  ('00000000-0000-0000-0008-0000000000d2', 2, current_date - 30, 70000, 0);

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0008-0000000000a2');
select throws_ok($$select public.apply_default_plan('00000000-0000-0000-0008-0000000000d2')$$,
  '42501', 'permission denied for function apply_default_plan', 'apply_default_plan is not executable by authenticated');
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select is(public.apply_default_plan('00000000-0000-0000-0008-0000000000d2'), 'forgiven'::public.loan_status,
  '''forgive'' forgives the rest');
select is((select (amount_cents, tax_year)::text from public.loan_forgiveness where loan_id = '00000000-0000-0000-0008-0000000000d2'),
  format('(70000,%s)', extract(year from current_date)), 'forgiveness is written for exactly the outstanding amount');
select is((select (status, public.loan_outstanding_cents(id), defaulted_at is not null)::text from public.family_loans
           where id = '00000000-0000-0000-0008-0000000000d2'), '(forgiven,0,t)', 'the forgiven loan owes nothing');
select is(public.apply_default_plan('00000000-0000-0000-0008-0000000000d3'), 'defaulted'::public.loan_status,
  '''mediate'' marks the loan defaulted');
select is(public.apply_default_plan('00000000-0000-0000-0008-0000000000d4'), 'defaulted'::public.loan_status,
  '''repay_on_sale'' marks the loan defaulted');
select is((select array_agg(defaulted_at is not null order by id) from public.family_loans
           where id in ('00000000-0000-0000-0008-0000000000d3', '00000000-0000-0000-0008-0000000000d4')),
  array[true, true], 'defaulted loans record when');
select is((select array_agg(action || ':' || (detail ->> 'outstanding_cents') order by target_id) from private.audit_log
           where target = 'family_loans' and target_id in ('00000000-0000-0000-0008-0000000000d2',
             '00000000-0000-0000-0008-0000000000d3', '00000000-0000-0000-0008-0000000000d4')),
  array['loan.default.forgive:70000', 'loan.default.mediate:50000', 'loan.default.repay_on_sale:50000'],
  'every default is audit-logged with what was outstanding');
select throws_ok($$select public.apply_default_plan('00000000-0000-0000-0008-0000000000d3')$$,
  '23514', 'loan is defaulted', 'a plan is applied once');

-- --- missed installments --------------------------------------------------------------
-- d5 active: paid / 11 days late, partly paid / exactly 10 days late / 5 days late / paused.
insert into public.family_loans (id, borrower_id, lender_id, principal_cents, status)
values ('00000000-0000-0000-0008-0000000000d5', '00000000-0000-0000-0008-0000000000a1', '00000000-0000-0000-0008-0000000000a2', 100000, 'active');
insert into public.loan_installments (loan_id, seq, due_on, amount_cents, paid_cents, paused) values
  ('00000000-0000-0000-0008-0000000000d5', 1, current_date - 30, 20000, 20000, false),
  ('00000000-0000-0000-0008-0000000000d5', 2, current_date - 11, 20000, 5000, false),
  ('00000000-0000-0000-0008-0000000000d5', 3, current_date - 10, 20000, 0, false),
  ('00000000-0000-0000-0008-0000000000d5', 4, current_date - 5, 20000, 0, false),
  ('00000000-0000-0000-0008-0000000000d5', 5, current_date - 40, 20000, 0, true);

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0008-0000000000a1');
select results_eq(
  $$select loan_id, seq, owed_cents from public.loan_missed_installments order by loan_id, seq$$,
  $$values ('00000000-0000-0000-0008-0000000000d5'::uuid, 2, 15000::bigint)$$,
  'the borrower sees only what is more than 10 days overdue on loans still collecting');
select pg_temp.login('00000000-0000-0000-0008-0000000000a2');
select is((select count(*) from public.loan_missed_installments), 1::bigint, 'the lender sees the same');
select pg_temp.login('00000000-0000-0000-0008-0000000000a3');
select is((select count(*) from public.loan_missed_installments), 0::bigint, 'nobody else sees missed installments');
reset role;
set local role anon;
select throws_ok($$select count(*) from public.loan_missed_installments$$, '42501', null,
  'anon cannot read missed installments');
reset role;

-- --- the giving record --------------------------------------------------------------
-- bea: subscription (40.00 captured, 40.00 pending); gives xia 50.00 captured + 70.00
-- pledged, lends 100.00 captured. bea's own request: 200.00 from the pool and 30.00
-- from xia captured, 10.00 pledged.
select pg_temp.cover('00000000-0000-0000-0008-0000000000a1');
insert into public.subscription_payments (subscription_id, member_id, period, amount_cents, status)
select id, member_id, date_trunc('month', now() + interval '1 month')::date, 4000, 'pending'
from public.subscriptions where member_id = '00000000-0000-0000-0008-0000000000a1';

select pg_temp.request('00000000-0000-0000-0008-0000000000b1', '00000000-0000-0000-0008-0000000000a3', 'people', 500000);
select pg_temp.request('00000000-0000-0000-0008-0000000000b2', '00000000-0000-0000-0008-0000000000a1', 'pool', 500000);
select pg_temp.move(id, 'scoring', 'open')
from unnest(array['00000000-0000-0000-0008-0000000000b1', '00000000-0000-0000-0008-0000000000b2']::uuid[]) id;
insert into public.family_loans (id, request_id, borrower_id, lender_id, principal_cents)
values ('00000000-0000-0000-0008-0000000000d6', '00000000-0000-0000-0008-0000000000b1',
        '00000000-0000-0000-0008-0000000000a3', '00000000-0000-0000-0008-0000000000a1', 10000);
insert into public.pool_runs (id, fund, available_cents, reserve_cents, allocated_cents, settings, algorithm_version)
values ('00000000-0000-0000-0008-0000000000e1', 'protection', 100000, 0, 20000, '{}', 'test');
insert into public.pool_allocations (id, run_id, request_id, score, band, need_cents, grant_cents)
values ('00000000-0000-0000-0008-0000000000e2', '00000000-0000-0000-0008-0000000000e1',
        '00000000-0000-0000-0008-0000000000b2', 90, 90, 500000, 20000);
insert into public.contributions (request_id, contributor_id, source, amount_cents, status, loan_id, pool_allocation_id) values
  ('00000000-0000-0000-0008-0000000000b1', '00000000-0000-0000-0008-0000000000a1', 'gift', 5000, 'captured', null, null),
  ('00000000-0000-0000-0008-0000000000b1', '00000000-0000-0000-0008-0000000000a1', 'gift', 7000, 'pledged', null, null),
  ('00000000-0000-0000-0008-0000000000b1', '00000000-0000-0000-0008-0000000000a1', 'loan', 10000, 'captured', '00000000-0000-0000-0008-0000000000d6', null),
  ('00000000-0000-0000-0008-0000000000b2', null, 'pool', 20000, 'captured', null, '00000000-0000-0000-0008-0000000000e2'),
  ('00000000-0000-0000-0008-0000000000b2', '00000000-0000-0000-0008-0000000000a3', 'gift', 3000, 'captured', null, null),
  ('00000000-0000-0000-0008-0000000000b2', '00000000-0000-0000-0008-0000000000a3', 'gift', 1000, 'pledged', null, null);

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0008-0000000000a1');
select results_eq($$select * from public.my_giving_record()$$,
  $$values (4000::bigint, 5000::bigint, 10000::bigint, 20000::bigint, 3000::bigint, 0::bigint)$$,
  'the giving record counts only the caller''s captured money, never pledges or pending payments');
select pg_temp.login('00000000-0000-0000-0008-0000000000a3');
select results_eq($$select * from public.my_giving_record()$$,
  $$values (0::bigint, 3000::bigint, 0::bigint, 0::bigint, 15000::bigint, 0::bigint)$$,
  'another member gets their own figures, not the first member''s');

-- --- pool requests paid in the last three years -------------------------------------------
reset role;
select pg_temp.paid_request('00000000-0000-0000-0008-0000000001b1', '00000000-0000-0000-0008-0000000000a4', 'pool', now() - interval '1 year');
select pg_temp.paid_request('00000000-0000-0000-0008-0000000001b2', '00000000-0000-0000-0008-0000000000a4', 'people', now() - interval '1 year');
select pg_temp.paid_request('00000000-0000-0000-0008-0000000001b3', '00000000-0000-0000-0008-0000000000a4', 'pool', now() - interval '4 years');
select pg_temp.paid_request('00000000-0000-0000-0008-0000000001b5', '00000000-0000-0000-0008-0000000000a4', 'both', now() - interval '6 months');
-- Submitted long ago, paid recently: it counts from when it was paid.
update public.requests set submitted_at = now() - interval '4 years' where id = '00000000-0000-0000-0008-0000000001b5';
-- Funded but not yet paid.
select pg_temp.request('00000000-0000-0000-0008-0000000001b4', '00000000-0000-0000-0008-0000000000a4', 'pool', 50000);
select pg_temp.move('00000000-0000-0000-0008-0000000001b4', 'scoring', 'open');
insert into public.contributions (request_id, contributor_id, source, amount_cents, status)
values ('00000000-0000-0000-0008-0000000001b4', '00000000-0000-0000-0008-0000000000a3', 'gift', 50000, 'captured');

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select is(public.pool_requests_paid_3y('00000000-0000-0000-0008-0000000000a4'), 2,
  'counts paid pool and both requests paid out in the last 3 years, nothing else');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0008-0000000000a4');
select is(public.pool_requests_paid_3y('00000000-0000-0000-0008-0000000000a4'), 2, 'a member reads their own count');
select pg_temp.login('00000000-0000-0000-0008-0000000000a3');
select throws_ok($$select public.pool_requests_paid_3y('00000000-0000-0000-0008-0000000000a4')$$,
  '42501', 'you can only see your own record', 'a member cannot read another member''s claim history');

reset role;
select * from finish();
rollback;
