-- Fund loan pauses and resumes (20261102450000_fund_loan_pauses.sql).
--
-- Properties this file pins:
--   * the borrower pauses their own fund loan: the pause is recorded, the loan
--     reads 'paused', unpaid installments slide out, and nothing owed changes;
--   * pausing beyond the allowance is refused and tells the borrower to ask
--     the lending Fund to restructure;
--   * a paused loan still takes payments;
--   * the borrower resumes early at any time; the loan-servicing service only
--     resumes pauses that have run out, and a member can't run that job;
--   * pause rows are append-only, and only the borrower can read them.
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

select pg_temp.member('00000000-0000-0000-0025-0000000000a1');
select pg_temp.member('00000000-0000-0000-0025-0000000000a2');

-- The partner opens and activates a monthly fund loan, with one payment paid,
-- so there are unpaid installments for a pause to push back.
set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.create_fund_loan(
  '00000000-0000-0000-0025-0000000000a1'::uuid, 100000::bigint, true,
  60000, 40000, 0, 'monthly', 0, 'loan_p1')$$, 'the partner opens a monthly fund loan');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0025-0000000000a1'::uuid);
select lives_ok($$select public.set_fund_loan_schedule(
  (select id from public.fund_loans where partner_ref = 'loan_p1')::uuid,
  5, current_date + 1)$$, 'the borrower sets the schedule');
select is(public.sign_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_p1')::uuid), 'signed',
  'the borrower signs');

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.activate_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_p1')::uuid)$$,
  'the partner disburses');
select is(public.record_fund_loan_payment(
  (select id from public.fund_loans where partner_ref = 'loan_p1')::uuid, 1, 20000::bigint),
  80000::bigint, 'one installment is paid');

-- --- the borrower pauses their own loan -------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0025-0000000000a1'::uuid);
select lives_ok($$select public.pause_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_p1')::uuid, 2, 'hard year')$$,
  'the borrower pauses two months without asking');
select is((select status from public.fund_loans
           where partner_ref = 'loan_p1'), 'paused', 'the loan reads paused');
select is((select count(*) from public.fund_loan_pauses
           where loan_id = (select id from public.fund_loans where partner_ref = 'loan_p1')),
  1::bigint, 'the pause is recorded with its reason');
select is((select due_on from public.fund_loan_installments
           where loan_id = (select id from public.fund_loans where partner_ref = 'loan_p1')
             and seq = 2),
  (current_date + 1 + interval '3 months')::date,
  'the unpaid installment slid two months out');
select is(public.fund_loan_outstanding_cents(
  (select id from public.fund_loans where partner_ref = 'loan_p1')::uuid),
  80000::bigint, 'the pause bought back dates, not money');

-- --- the allowance, then the restructure ask --------------------------------------

select throws_ok($$select public.pause_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_p1')::uuid, 2)$$,
  '23514', 'this loan allows 3 pause months a year (2 used); ask the lending Fund to restructure');

-- --- a paused loan still collects by agreement ------------------------------------

set local role service_role;
select pg_temp.as_service();
select is(public.record_fund_loan_payment(
  (select id from public.fund_loans where partner_ref = 'loan_p1')::uuid, 2, 20000::bigint),
  60000::bigint, 'the partner still moves money on the paused loan');

-- --- resuming ---------------------------------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0025-0000000000a1'::uuid);
select is(public.resume_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_p1')::uuid), 'active',
  'the borrower resumes early at any time');
select throws_ok($$select public.resume_ended_fund_pauses()$$, '42501',
  'permission denied for function resume_ended_fund_pauses');

set local role service_role;
select pg_temp.as_service();
select is(public.resume_ended_fund_pauses(), 0::int,
  'the job only resumes pauses that ran out; this pause is still ahead');
select throws_ok($$update public.fund_loan_pauses set months = 12
  where loan_id = (select id from public.fund_loans where partner_ref = 'loan_p1')$$,
  '42501', 'fund_loan_pauses is append-only');

-- --- only the borrower reads their pauses -----------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0025-0000000000a2'::uuid);
select is((select count(*) from public.fund_loan_pauses), 0::bigint,
  'another member sees nothing in their pauses');

rollback;
