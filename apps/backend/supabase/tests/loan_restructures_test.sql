-- Family loan restructures (20261102480000_loan_restructures.sql).
--
-- Properties this file pins:
--   * either side stages a new schedule; a second staged ask is refused while
--     one waits; a staged ask alone moves no money;
--   * the other side signing completes the agreement and re-spreads the
--     unpaid installments only — money already returned keeps its dates, and
--     installments land on the loan's payment day like every other schedule;
--   * the outstanding figure never changes across a restructure;
--   * a past start date, a schedule longer than 480 months, a loan owed
--     nothing, and too many installments for what is left are refused;
--   * both sides read the restructures, nobody else does.
begin;
select plan(16);

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

select pg_temp.member('00000000-0000-0000-0028-0000000000a1');
select pg_temp.member('00000000-0000-0000-0028-0000000000a2');
select pg_temp.member('00000000-0000-0000-0028-0000000000a3');

-- A1 borrows from A2. Loan l1 is collecting with five installments, one of
-- them already paid back. Loan l2 owes nothing. Loan l3 owes $2.
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0028-0000000000a1'::uuid);
insert into public.family_loans (id, borrower_id, lender_id, principal_cents,
                                 status, borrower_signed_at, lender_signed_at)
values ('00000000-0000-0000-0028-0000000000b1', '00000000-0000-0000-0028-0000000000a1',
        '00000000-0000-0000-0028-0000000000a2', 100000, 'active', now(), now()),
       ('00000000-0000-0000-0028-0000000000b2', '00000000-0000-0000-0028-0000000000a1',
        '00000000-0000-0000-0028-0000000000a2', 20000, 'active', now(), now()),
       ('00000000-0000-0000-0028-0000000000b3', '00000000-0000-0000-0028-0000000000a1',
        '00000000-0000-0000-0028-0000000000a2', 100000, 'active', now(), now());
insert into public.loan_installments (loan_id, seq, due_on, amount_cents, paid_cents) values
  ('00000000-0000-0000-0028-0000000000b1', 1, current_date - 30, 20000, 20000),
  ('00000000-0000-0000-0028-0000000000b1', 2, current_date - 20, 20000, 0),
  ('00000000-0000-0000-0028-0000000000b1', 3, current_date - 10, 20000, 0),
  ('00000000-0000-0000-0028-0000000000b1', 4, current_date + 10, 20000, 0),
  ('00000000-0000-0000-0028-0000000000b1', 5, current_date + 20, 20000, 0),
  ('00000000-0000-0000-0028-0000000000b2', 1, current_date - 30, 20000, 20000),
  ('00000000-0000-0000-0028-0000000000b3', 1, current_date - 30, 99800, 99800),
  ('00000000-0000-0000-0028-0000000000b3', 2, current_date - 10, 200, 0);

-- --- either side stages the new schedule ----------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0028-0000000000a1'::uuid);
select lives_ok($$select public.restructure_loan(
  '00000000-0000-0000-0028-0000000000b1'::uuid, 8, (date_trunc('month', current_date
  + interval '1 month'))::date)$$, 'the borrower stages eight months');
select is((select count(*) from public.loan_restructures
           where loan_id = '00000000-0000-0000-0028-0000000000b1'::uuid
             and other_signed_at is null), 1::bigint, 'the ask waits for the other side');
select throws_ok($$select public.restructure_loan(
  '00000000-0000-0000-0028-0000000000b1'::uuid, 10, current_date + 1)$$,
  '23514', 'a restructure the other side has not signed yet is already pending');
select is((select count(*) from public.loan_installments
           where loan_id = '00000000-0000-0000-0028-0000000000b1'::uuid), 5::bigint,
  'the staged ask alone moves no money');
reset role;

-- --- the lender signs the agreement ---------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0028-0000000000a2'::uuid);
select is(public.sign_loan_restructure('00000000-0000-0000-0028-0000000000b1'::uuid),
  'active', 'the lender signs and the schedule re-spreads');
select is((select count(*) from public.loan_installments
           where loan_id = '00000000-0000-0000-0028-0000000000b1'::uuid
             and paid_cents < amount_cents), 8::bigint, 'the unpaid money re-spread over eight months');
select is((select min(due_on) from public.loan_installments
           where loan_id = '00000000-0000-0000-0028-0000000000b1'::uuid
             and paid_cents < amount_cents),
  (date_trunc('month', current_date + interval '1 month'))::date,
  'the new schedule starts on the agreed day');
select is(public.loan_outstanding_cents('00000000-0000-0000-0028-0000000000b1'::uuid),
  80000::bigint, 'restructuring repays the same money over different dates, never less');
select is((select amount_cents from public.loan_installments
           where loan_id = '00000000-0000-0000-0028-0000000000b1'::uuid
             and paid_cents = amount_cents), 20000::bigint,
  'the installment already paid keeps its date and amount');

-- --- refusals --------------------------------------------------------------------

select throws_ok($$select public.restructure_loan(
  '00000000-0000-0000-0028-0000000000b1'::uuid, 6, current_date - 1)$$,
  '23514', 'a restructured schedule can''t start in the past');
select throws_ok($$select public.restructure_loan(
  '00000000-0000-0000-0028-0000000000b1'::uuid, 481, current_date + 1)$$,
  '23514', 'new row for relation "loan_restructures" violates check constraint "loan_restructures_months_check"');
select throws_ok($$select public.restructure_loan(
  '00000000-0000-0000-0028-0000000000b2'::uuid, 6, current_date + 1)$$,
  '23514', 'a loan that owes nothing has nothing to restructure');
select throws_ok($$select public.restructure_loan(
  '00000000-0000-0000-0028-0000000000b3'::uuid, 300, current_date + 1)$$,
  '23514', 'too many installments for what is left to pay');
reset role;

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0028-0000000000a3'::uuid);
select throws_ok($$select public.restructure_loan(
  '00000000-0000-0000-0028-0000000000b1'::uuid, 6, current_date + 1)$$,
  'P0002', 'loan not found');
select is((select count(*) from public.loan_restructures), 0::bigint,
  'a member with no relation reads nothing');
reset role;

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0028-0000000000a2'::uuid);
select is((select sum(amount_cents) from public.loan_installments
           where loan_id = '00000000-0000-0000-0028-0000000000b1'::uuid
             and paid_cents < amount_cents), 80000::numeric,
  'the re-spread covers exactly the money still owed');
reset role;

rollback;
