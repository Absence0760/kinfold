-- Home Fund loans (20261102420000_fund_loans.sql).
--
-- Properties this file pins:
--   * the partner opens a fund loan; a replayed reference answers with the loan
--     already made; liens over 105% in total are refused;
--   * the borrower signs their side; only the partner's disbursement activates;
--   * monthly payments follow the agreed schedule; income payments are capped
--     at the share of the member's live income, and payments can't be edited.
begin;
select plan(15);

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

select pg_temp.member('00000000-0000-0000-0020-0000000000a1');

insert into public.income_verifications
  (member_id, method, monthly_income_cents, verified_at, expires_at)
values ('00000000-0000-0000-0020-0000000000a1', 'self_attested', 100000,
        now(), now() + interval '6 months');

-- --- the partner opens the loan; a replay is a no-op -----------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.create_fund_loan(
  '00000000-0000-0000-0020-0000000000a1'::uuid, 100000::bigint, true,
  60000, 40000, 0, 'monthly', 0, 'loan_m1')$$, 'the partner opens a monthly fund loan');
select is((select count(*) from public.fund_loans), 1::bigint, 'one loan was opened');
select is(public.create_fund_loan(
  '00000000-0000-0000-0020-0000000000a1'::uuid, 100000::bigint, true,
  60000, 40000, 0, 'monthly', 0, 'loan_m1'),
  (select id from public.fund_loans where partner_ref = 'loan_m1'),
  'the replayed reference answers with the loan it already made');
select throws_ok($$select public.create_fund_loan(
  '00000000-0000-0000-0020-0000000000a1'::uuid, 100000::bigint, true,
  60000, 40000, 10000, 'monthly', 0, 'loan_bad')$$, '23514',
  'liens totalling 110% are refused');

-- --- the borrower signs; only the partner activates ------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0020-0000000000a1'::uuid);
select lives_ok($$select public.set_fund_loan_schedule(
  (select id from public.fund_loans where partner_ref = 'loan_m1'), 5, current_date + 1)$$,
  'the borrower sets the monthly schedule');
select is(public.sign_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_m1')::uuid), 'signed',
  'signing lands the loan as signed');
select throws_ok($$select public.activate_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_m1')::uuid)$$, '42501',
  'a member cannot activate; the disbursement is the partner''s');
reset role;

-- --- monthly payments follow the agreed schedule ----------------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.activate_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_m1')::uuid)$$,
  'the partner''s disbursement activates the loan');
select is(public.record_fund_loan_payment(
  (select id from public.fund_loans where partner_ref = 'loan_m1')::uuid, 1, 20000::bigint),
  80000::bigint, 'a full month moves and the balance reads back');
select throws_ok($$select public.record_fund_loan_payment(
  (select id from public.fund_loans where partner_ref = 'loan_m1')::uuid, 1, 20001::bigint)$$,
  '23514', 'a payment over what is owed on that installment is refused');

-- --- income payments are capped at the income share -------------------------------

select lives_ok($$select public.create_fund_loan(
  '00000000-0000-0000-0020-0000000000a1'::uuid, 60000::bigint, false,
  0, 0, 0, 'income', 5000, 'loan_i1')$$, 'the partner opens an income fund loan');
select is(public.fund_loan_income_due_cents(
  (select id from public.fund_loans where partner_ref = 'loan_i1')::uuid), 50000::bigint,
  'the month''s share of the live income reads back');
select throws_ok($$select public.record_fund_loan_payment(
  (select id from public.fund_loans where partner_ref = 'loan_i1')::uuid, 1, 60000::bigint)$$,
  '23514', 'an income payment over the month''s share is refused');
select is(public.record_fund_loan_payment(
  (select id from public.fund_loans where partner_ref = 'loan_i1')::uuid, 1, 50000::bigint),
  10000::bigint, 'a payment at the cap moves and the balance reads back');
select throws_ok($$update public.fund_loan_payments set amount_cents = 1
  where loan_id = (select id from public.fund_loans where partner_ref = 'loan_i1')$$,
  '42501', 'a recorded payment cannot be edited');

rollback;
