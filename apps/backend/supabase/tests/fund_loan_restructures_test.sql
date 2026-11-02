-- Fund loan restructures (20261102460000_fund_loan_restructures.sql).
--
-- Properties this file pins:
--   * the borrower stages a restructure on their own collecting monthly loan;
--     only unpaid installments are touched, and the outstanding never changes;
--   * a pending ask blocks a second ask; the partner's servicing event applies
--     it, and a member can't;
--   * income schedules have nothing to reschedule;
--   * a paused loan can still be restructured;
--   * only the borrower reads their restructures.
begin;
select plan(22);

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

select pg_temp.member('00000000-0000-0000-0026-0000000000a1');
select pg_temp.member('00000000-0000-0000-0026-0000000000a2');

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.create_fund_loan(
  '00000000-0000-0000-0026-0000000000a1'::uuid, 100000::bigint, true,
  60000, 40000, 0, 'monthly', 0, 'loan_r1')$$, 'the partner opens a monthly fund loan');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0026-0000000000a1'::uuid);
select lives_ok($$select public.set_fund_loan_schedule(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid,
  5, current_date + 1)$$, 'the borrower sets five installments');
select is(public.sign_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid), 'signed',
  'the borrower signs');

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.activate_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid)$$,
  'the partner disburses');
select is(public.record_fund_loan_payment(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid, 1, 20000::bigint),
  80000::bigint, 'one installment is paid back');

-- --- the borrower stages the ask ---------------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0026-0000000000a1'::uuid);
select lives_ok($$select public.restructure_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid, 8,
  current_date + 3)$$, 'the borrower asks for eight smaller payments');
select is((select count(*) from public.fund_loan_restructures
           where loan_id = (select id from public.fund_loans where partner_ref = 'loan_r1')
             and applied_at is null), 1::int, 'the ask is pending on the loan');
select throws_ok($$select public.restructure_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid, 10,
  current_date + 3)$$, '23514', 'a second ask is refused while one is pending');
select throws_ok($$select public.apply_fund_loan_restructure(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid)$$,
  '42501', 'a member cannot answer the ask; the partner''s event does');

-- --- the partner's event applies it -------------------------------------------------

set local role service_role;
select pg_temp.as_service();
select is(public.apply_fund_loan_restructure(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid), true,
  'the servicing event applies the pending ask');
select is((select count(*) from public.fund_loan_restructures
           where loan_id = (select id from public.fund_loans where partner_ref = 'loan_r1')
             and applied_at is null), 0::int, 'the ask is no longer pending');
select is((select count(*) from public.fund_loan_installments
           where loan_id = (select id from public.fund_loans where partner_ref = 'loan_r1')
             and paid_cents < amount_cents), 8::int, 'the unpaid money re-spread over eight months');
select is((select min(due_on) from public.fund_loan_installments
           where loan_id = (select id from public.fund_loans where partner_ref = 'loan_r1')
             and paid_cents < amount_cents),
  (current_date + 3)::date, 'the new schedule starts on the requested day');
select is(public.fund_loan_outstanding_cents(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid),
  80000::bigint, 'restructuring repays the same money over different dates, never less');
select is((select amount_cents from public.fund_loan_installments
           where loan_id = (select id from public.fund_loans where partner_ref = 'loan_r1')
             and paid_cents = amount_cents),
  20000::bigint, 'the installment already paid keeps its date and amount');

-- --- income schedules and pauses ------------------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0026-0000000000a1'::uuid);
select throws_ok($$select public.restructure_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid, 1, current_date - 1)$$,
  '23514', 'a schedule can''t start in the past');
set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.create_fund_loan(
  '00000000-0000-0000-0026-0000000000a1'::uuid, 60000::bigint, false,
  0, 0, 0, 'income', 5000, 'loan_i2')$$, 'the partner opens an income fund loan');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0026-0000000000a1'::uuid);
select throws_ok($$select public.restructure_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_i2')::uuid, 6, current_date + 1)$$,
  '23514', 'income payments are computed, not scheduled');
select lives_ok($$select public.pause_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid, 1)$$, 'the loan pauses');
select lives_ok($$select public.restructure_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid, 8, current_date + 4)$$,
  'a paused loan can still ask to restructure');
select throws_ok($$select public.restructure_fund_loan(
  (select id from public.fund_loans where partner_ref = 'loan_r1')::uuid, 6, current_date + 2)$$,
  'P0002', 'another borrower''s loan answers with nothing');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0026-0000000000a2'::uuid);
select is((select count(*) from public.fund_loan_restructures), 0::int,
  'another member sees no restructures');

rollback;
