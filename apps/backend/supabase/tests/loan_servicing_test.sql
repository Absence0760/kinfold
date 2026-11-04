-- Loan servicing (20261101170000_loan_servicing.sql).
--
-- Properties this file pins:
--   * a payment that finishes an installment writes the date it was paid; a
--     part payment writes no date, and writing one on a still-owed installment
--     is refused;
--   * the reliability record counts only payments made on or before the
--     installment's due date;
--   * a proposed schedule cannot start with an installment already due in the
--     past, and a legal schedule still sums to exactly the principal;
--   * forgiving part of a loan takes that money off the tail of the schedule,
--     so the installments left add up to exactly what is outstanding and
--     collecting them repays the loan without breaking the totals check;
--     forgiving more than is owed is still refused;
--   * loan_default_due lists only a collecting loan that has missed three or
--     more installments and has used up its pause allowance, and applying the
--     agreed plan forgives exactly the outstanding amount with an audit row.
begin;
select plan(18);

-- --- fixtures ------------------------------------------------------------------

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

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
$$;

select pg_temp.member('00000000-0000-0000-000c-0000000000a1');  -- borrower
select pg_temp.member('00000000-0000-0000-000c-0000000000a2');  -- lender
select pg_temp.member('00000000-0000-0000-000c-0000000000a5');  -- reliability subject

-- d1: collecting, allowance 3; one installment gets paid late (seq 4), one
-- gets a part payment (seq 3).
insert into public.family_loans (id, borrower_id, lender_id, principal_cents, status, payment_day)
values ('00000000-0000-0000-000c-0000000000d1', '00000000-0000-0000-000c-0000000000a1',
        '00000000-0000-0000-000c-0000000000a2', 120000, 'active', 15);
insert into public.loan_installments (loan_id, seq, due_on, amount_cents) values
  ('00000000-0000-0000-000c-0000000000d1', 1, current_date - 50, 30000),
  ('00000000-0000-0000-000c-0000000000d1', 2, current_date + 10, 30000),
  ('00000000-0000-0000-000c-0000000000d1', 3, current_date + 40, 30000),
  ('00000000-0000-0000-000c-0000000000d1', 4, current_date + 70, 30000);

-- d9: the loan behind the reliability check. Both installments are paid today,
-- one was due five days ago (late), one is due in five days (on time).
insert into public.family_loans (id, borrower_id, lender_id, principal_cents, status, payment_day)
values ('00000000-0000-0000-000c-0000000000d9', '00000000-0000-0000-000c-0000000000a5',
        '00000000-0000-0000-000c-0000000000a2', 20000, 'active', 5);
insert into public.loan_installments (loan_id, seq, due_on, amount_cents) values
  ('00000000-0000-0000-000c-0000000000d9', 1, current_date - 5, 10000),
  ('00000000-0000-0000-000c-0000000000d9', 2, current_date + 5, 10000);
update public.loan_installments set paid_cents = amount_cents
  where loan_id = '00000000-0000-0000-000c-0000000000d9';

-- --- when an installment was paid ------------------------------------------------

update public.loan_installments set paid_cents = amount_cents
  where loan_id = '00000000-0000-0000-000c-0000000000d1' and seq = 4;
select is((select paid_on from public.loan_installments
           where loan_id = '00000000-0000-0000-000c-0000000000d1' and seq = 4),
  current_date, 'a payment that finishes an installment writes the date it was paid');

update public.loan_installments set paid_cents = 10000
  where loan_id = '00000000-0000-0000-000c-0000000000d1' and seq = 3;
select is((select paid_on from public.loan_installments
           where loan_id = '00000000-0000-0000-000c-0000000000d1' and seq = 3),
  null::date, 'a part payment writes no date');

select throws_ok(
  $$update public.loan_installments set paid_on = current_date
    where loan_id = '00000000-0000-0000-000c-0000000000d1' and seq = 3$$,
  '23514', null, 'a paid date cannot be written while the installment is still owed');

-- --- the reliability record counts payments made on time --------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-000c-0000000000a5');
select results_eq(
  $$select installments_paid_on_time, installments_due from public.my_reliability()$$,
  $$values (1::bigint, 1::bigint)$$,
  'the record counts only payments made on or before the due date, of the ones due');

reset role;

-- --- a proposed schedule starts today or later ------------------------------------

insert into public.family_loans (id, borrower_id, lender_id, principal_cents, payment_day)
values ('00000000-0000-0000-000c-0000000000d5', '00000000-0000-0000-000c-0000000000a1',
        '00000000-0000-0000-000c-0000000000a2', 100000, 5);

set local role authenticated;
select pg_temp.login('00000000-0000-0000-000c-0000000000a1');
select throws_ok(
  $$select public.set_loan_schedule('00000000-0000-0000-000c-0000000000d5', 12, current_date - 1)$$,
  '23514', 'the first installment cannot be due in the past',
  'a schedule cannot start with payments already overdue');
select lives_ok(
  $$select public.set_loan_schedule('00000000-0000-0000-000c-0000000000d5', 10, current_date + 1)$$,
  'a schedule starting from today is accepted');
select is((select sum(amount_cents) from public.loan_installments
           where loan_id = '00000000-0000-0000-000c-0000000000d5'),
  100000::numeric, 'the new schedule still adds up to exactly the principal');

reset role;

-- --- forgiveness shrinks the schedule ---------------------------------------------

insert into public.family_loans (id, borrower_id, lender_id, principal_cents, status, payment_day)
values ('00000000-0000-0000-000c-0000000000d6', '00000000-0000-0000-000c-0000000000a1',
        '00000000-0000-0000-000c-0000000000a2', 40000, 'active', 15);
insert into public.loan_installments (loan_id, seq, due_on, amount_cents) values
  ('00000000-0000-0000-000c-0000000000d6', 1, current_date + 20, 10000),
  ('00000000-0000-0000-000c-0000000000d6', 2, current_date + 40, 10000),
  ('00000000-0000-0000-000c-0000000000d6', 3, current_date + 60, 10000),
  ('00000000-0000-0000-000c-0000000000d6', 4, current_date + 80, 10000);

set local role authenticated;
select pg_temp.login('00000000-0000-0000-000c-0000000000a2');
select lives_ok(
  $$select public.forgive_loan('00000000-0000-0000-000c-0000000000d6', 15000, extract(year from current_date)::integer)$$,
  'the lender forgives 150.00 of the 400.00 loan');
select is(public.loan_outstanding_cents('00000000-0000-0000-000c-0000000000d6'),
  25000::bigint, 'forgiving 150.00 leaves 250.00 outstanding');
select results_eq(
  $$select seq, amount_cents from public.loan_installments
    where loan_id = '00000000-0000-0000-000c-0000000000d6' order by seq$$,
  $$values (1, 10000::bigint), (2, 10000::bigint), (3, 5000::bigint)$$,
  'the forgiven money is taken off the last unpaid installments');
select is((select sum(amount_cents) from public.loan_installments
           where loan_id = '00000000-0000-0000-000c-0000000000d6'),
  25000::numeric, 'the schedule left adds up to exactly what is outstanding');

reset role;
-- Collecting the shrunken schedule must not trip the loan-totals check.
update public.loan_installments set paid_cents = amount_cents
  where loan_id = '00000000-0000-0000-000c-0000000000d6';
select is(public.loan_outstanding_cents('00000000-0000-0000-000c-0000000000d6'),
  0::bigint, 'collecting the shrunken schedule repays the loan');
select is((select status from public.family_loans where id = '00000000-0000-0000-000c-0000000000d6'),
  'repaid'::public.loan_status, 'and the loan is marked repaid');

-- d7: 50.00 outstanding in one installment; forgiving 60.00 is refused.
insert into public.family_loans (id, borrower_id, lender_id, principal_cents, status, payment_day, pause_months_per_year)
values ('00000000-0000-0000-000c-0000000000d7', '00000000-0000-0000-000c-0000000000a1',
        '00000000-0000-0000-000c-0000000000a2', 5000, 'active', 15, 0);
insert into public.loan_installments (loan_id, seq, due_on, amount_cents)
values ('00000000-0000-0000-000c-0000000000d7', 1, current_date + 30, 5000);

set local role authenticated;
select pg_temp.login('00000000-0000-0000-000c-0000000000a2');
select throws_ok(
  $$select public.forgive_loan('00000000-0000-0000-000c-0000000000d7', 6000, extract(year from current_date)::integer)$$,
  '23514', 'payments and forgiveness exceed the principal',
  'forgiving more than is owed is still refused');

-- --- the agreed trigger for a default plan ----------------------------------------

-- d8: collecting, no pause allowance agreed, four installments long overdue.
insert into public.family_loans (id, borrower_id, lender_id, principal_cents, status, payment_day, pause_months_per_year, default_plan)
values ('00000000-0000-0000-000c-0000000000d8', '00000000-0000-0000-000c-0000000000a1',
        '00000000-0000-0000-000c-0000000000a2', 40000, 'active', 15, 0, 'forgive');
insert into public.loan_installments (loan_id, seq, due_on, amount_cents) values
  ('00000000-0000-0000-000c-0000000000d8', 1, current_date - 100, 10000),
  ('00000000-0000-0000-000c-0000000000d8', 2, current_date - 70, 10000),
  ('00000000-0000-0000-000c-0000000000d8', 3, current_date - 40, 10000),
  ('00000000-0000-0000-000c-0000000000d8', 4, current_date - 20, 10000);

set local role service_role;
select pg_temp.as_service();
select results_eq(
  $$select id, default_plan, missed_installments, pause_months_used from public.loan_default_due$$,
  $$values ('00000000-0000-0000-000c-0000000000d8'::uuid, 'forgive'::public.default_plan, 4, 0)$$,
  'only the loan that has used up its pause allowance and missed three installments is listed');
select is(public.apply_default_plan('00000000-0000-0000-000c-0000000000d8'),
  'forgiven'::public.loan_status, 'applying the agreed plan forgives the loan');
select is((select sum(amount_cents) from public.loan_forgiveness
           where loan_id = '00000000-0000-0000-000c-0000000000d8'),
  40000::numeric, 'the plan forgives exactly what was outstanding');
select is((select count(*) from private.audit_log
           where action = 'loan.default.forgive' and target_id = '00000000-0000-0000-000c-0000000000d8'),
  1::bigint, 'and the default is written down in the audit log');

rollback;