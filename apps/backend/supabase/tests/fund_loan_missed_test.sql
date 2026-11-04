-- Fund loans: missed installments and the default plan (20261102680000_fund_loan_missed.sql).
--
-- Properties this file pins:
--   * a Fund loan that is COLLECTING shows its unpaid installments more than
--     ten days late; a loan only signed (never disbursed) shows nothing, and
--     the owed line is what is left, not the installment's whole amount;
--   * closing a Fund loan under its plan stops collection: the loan is audited,
--     its missed rows go away, and no money moves after the fact;
--   * a loan repaid in full is not in default;
--   * a client cannot close a Fund loan - only the partner's agreement can;
--   * a Fund loan can never be forgiven: forgiveness belongs to family loans.
begin;
select plan(19);

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

select pg_temp.member('00000000-0000-0000-0021-0000000000a1');

-- --- three Fund loans, each with its own overdue story ---------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.create_fund_loan(
  '00000000-0000-0000-0021-0000000000a1'::uuid, 100000::bigint, true,
  60000, 40000, 0, 'monthly', 0, 'loan_m1')$$, 'the partner opens a monthly fund loan');
select lives_ok($$select public.create_fund_loan(
  '00000000-0000-0000-0021-0000000000a1'::uuid, 20000::bigint, false,
  0, 0, 0, 'monthly', 0, 'loan_s1')$$, 'the partner opens a loan that stays signed');
select lives_ok($$select public.create_fund_loan(
  '00000000-0000-0000-0021-0000000000a1'::uuid, 20000::bigint, false,
  0, 0, 0, 'monthly', 0, 'loan_r1')$$, 'the partner opens a loan that gets repaid');

-- The rows stand in for the schedule the borrower agreed to: loan m1 has one
-- paid installment, one partly paid and one unpaid (both overdue), and one not
-- yet due; loan s1 is overdue but never disbursed; loan r1 is paid in full.
insert into public.fund_loan_installments (loan_id, seq, due_on, amount_cents, paid_cents)
values ((select id from public.fund_loans where partner_ref = 'loan_m1'), 1,
        current_date - 20, 10000::bigint, 10000::bigint),
       ((select id from public.fund_loans where partner_ref = 'loan_m1'), 2,
        current_date - 15, 10000::bigint, 2000::bigint),
       ((select id from public.fund_loans where partner_ref = 'loan_m1'), 3,
        current_date - 11, 10000::bigint, 0::bigint),
       ((select id from public.fund_loans where partner_ref = 'loan_m1'), 4,
        current_date + 5, 70000::bigint, 0::bigint),
       ((select id from public.fund_loans where partner_ref = 'loan_s1'), 1,
        current_date - 15, 20000::bigint, 0::bigint),
       ((select id from public.fund_loans where partner_ref = 'loan_r1'), 1,
        current_date + 2, 20000::bigint, 0::bigint);

-- --- the borrower signs; the partner disburses two of them ------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0021-0000000000a1'::uuid);
select is(public.sign_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_m1')::uuid), 'signed',
  'signing the agreed schedule lands the loan as signed');
select lives_ok($$select public.sign_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_s1')::uuid)$$,
  'the second loan is signed but never disbursed');
select lives_ok($$select public.sign_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid)$$,
  'the third loan is signed too');

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.activate_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_m1')::uuid)$$,
  'the partner''s disbursement starts collection on loan m1');
select lives_ok($$select public.activate_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid)$$,
  'and it disburses the loan that will be repaid');
select is(public.record_fund_loan_payment(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid, 1,
  20000::bigint), 0::bigint, 'paying the whole installment leaves nothing outstanding');

-- --- the missed view -------------------------------------------------------------

select is((select count(*) from public.fund_loan_missed_installments
           where loan_id = (select id from public.fund_loans where partner_ref = 'loan_m1')),
  2::bigint, 'two installments of loan m1 are more than ten days late and unpaid');
select is((select owed_cents from public.fund_loan_missed_installments
           where loan_id = (select id from public.fund_loans where partner_ref = 'loan_m1')
           and seq = 2), 8000::bigint,
  'the owed line is what is left on that installment, not its whole amount');
select is((select count(*) from public.fund_loan_missed_installments
           where loan_id = (select id from public.fund_loans where partner_ref = 'loan_s1')),
  0::bigint, 'a loan that is only signed has nothing missed yet');

-- --- closing loan m1 under its plan ----------------------------------------------

select lives_ok($$select public.apply_fund_loan_default(
  (select id from public.fund_loans where partner_ref = 'loan_m1')::uuid)$$,
  'the partner''s agreement closes the loan under its plan');
reset role;
select is((select count(*) from private.audit_log where action = 'loan.default.fund'),
  1::bigint, 'the closure is audit-trailed');
set local role service_role;
select pg_temp.as_service();
select is((select count(*) from public.fund_loan_missed_installments
           where loan_id = (select id from public.fund_loans where partner_ref = 'loan_m1')),
  0::bigint, 'a closed loan stops collecting, so it has nothing missed');
select throws_ok($$select public.record_fund_loan_payment(
  (select id from public.fund_loans where partner_ref = 'loan_m1')::uuid, 4, 1000::bigint)$$,
  'P0002', 'fund loan not found, or not collecting',
  'no money moves on a loan that was closed under its plan');

-- --- a repaid loan is not in default, and no client can close one -----------------

select throws_ok($$select public.apply_fund_loan_default(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid)$$,
  'P0002', 'fund loan not found, or not collecting',
  'a loan already repaid in full is not in default');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0021-0000000000a1'::uuid);
select throws_ok($$select public.apply_fund_loan_default(
  (select id from public.fund_loans where partner_ref = 'loan_s1')::uuid)$$,
  '42501', 'a Fund loan closes under its plan by agreement, not by a client',
  'the borrower cannot close their own Fund loan');
select throws_ok($$insert into public.loan_forgiveness (loan_id, tax_year, amount_cents)
  values ((select id from public.fund_loans where partner_ref = 'loan_s1'),
          extract(year from current_date)::integer, 20000)$$,
  '23503', null, 'a Fund loan cannot be forgiven: forgiveness belongs to family loans');

reset role;
rollback;