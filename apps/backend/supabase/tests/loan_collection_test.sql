-- Loan collection (20261102230000_loan_collection.sql).
--
-- Properties this file pins:
--   * the service records a payment up to what the installment still owes; a
--     partial payment is allowed, more than owed and zero are refused;
--   * only loans still collecting move money: signed loans haven't been
--     disbursed, forgiven/repaid/cancelled ones are over;
--   * a paused installment is not collected;
--   * the paid date lands on a full installment and the loan turns `repaid`
--     once nothing is left, both through the existing triggers;
--   * a member can't record a payment; the payment is audit-logged.
begin;
select plan(13);

-- --- fixtures ------------------------------------------------------------------
-- Temporary helpers, gone at rollback. They run as postgres (the owner),
-- standing in for the service and the payment partner.

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
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

-- A signed loan in a given state with installments, inserted with triggers off.
-- One installment is marked paused when p_paused.
create function pg_temp.loan_in(p_loan uuid, p_borrower uuid, p_lender uuid,
                                p_status public.loan_status, p_paused boolean)
returns void language plpgsql as $$
begin
  insert into public.family_loans (id, borrower_id, lender_id, principal_cents, payment_day,
                                   pause_months_per_year, default_plan, status,
                                   borrower_signed_at, lender_signed_at, secured)
  values (p_loan, p_borrower, p_lender, 30000, 15, 2, 'forgive', p_status,
          now(), now(), false);
  insert into public.loan_installments (loan_id, seq, due_on, amount_cents, paused)
  values (p_loan, 1, current_date + 5, 15000, p_paused),
         (p_loan, 2, current_date + 35, 15000, false);
end $$;

select pg_temp.member('00000000-0000-0000-0008-0000000000a1');  -- borrower
select pg_temp.member('00000000-0000-0000-0008-0000000000a2');  -- lender
-- L1: active, first installment not paused.
select pg_temp.loan_in('00000000-0000-0000-0008-0000000000f1', '00000000-0000-0000-0008-0000000000a1',
                       '00000000-0000-0000-0008-0000000000a2', 'active', false);
-- L2: signed only (money hasn't moved).
select pg_temp.loan_in('00000000-0000-0000-0008-0000000000f2', '00000000-0000-0000-0008-0000000000a1',
                       '00000000-0000-0000-0008-0000000000a2', 'signed', false);
-- L3: paused loan with a paused installment.
select pg_temp.loan_in('00000000-0000-0000-0008-0000000000f3', '00000000-0000-0000-0008-0000000000a1',
                       '00000000-0000-0000-0008-0000000000a2', 'paused', true);

-- --- collecting an installment ---------------------------------------------------------

set local role service_role;
select pg_temp.as_service();
select is((select public.record_loan_payment('00000000-0000-0000-0008-0000000000f1', 1, 15000::bigint)),
  0::bigint, 'a full payment on an active loan leaves nothing owed on that installment');
select is((select paid_cents from public.loan_installments
           where loan_id = '00000000-0000-0000-0008-0000000000f1' and seq = 1),
  15000::bigint, 'the installment says paid');
select isnt((select paid_on from public.loan_installments
              where loan_id = '00000000-0000-0000-0008-0000000000f1' and seq = 1),
  NULL::date, 'the full installment remembers the paid date (existing trigger)');
select is((select public.record_loan_payment('00000000-0000-0000-0008-0000000000f1', 2, 10000::bigint)),
  5000::bigint, 'a partial payment is allowed and reports what is still owed');

select throws_ok($$select public.record_loan_payment('00000000-0000-0000-0008-0000000000f1', 2, 5001::bigint)$$,
  '23514', 'loan payment must be between 1 and 5000 cents',
  'an installment can''t be overpaid');
select throws_ok($$select public.record_loan_payment('00000000-0000-0000-0008-0000000000f1', 2, 0::bigint)$$,
  '23514', 'loan payment must be between 1 and 5000 cents',
  'zero moves no money');
select throws_ok($$select public.record_loan_payment('00000000-0000-0000-0008-0000000000f1', 9, 100::bigint)$$,
  'P0002', 'installment not found', 'a missing installment is refused');

select throws_ok($$select public.record_loan_payment('00000000-0000-0000-0008-0000000000f2', 1, 100::bigint)$$,
  'P0002', 'loan not found, or not collecting',
  'a signed loan has no money moving yet');
select throws_ok($$select public.record_loan_payment('00000000-0000-0000-0008-0000000000f3', 1, 100::bigint)$$,
  '23514', 'a paused installment is not being collected',
  'the pause agreed on holds');

-- --- the loan finishes only through the existing triggers ------------------------

select is((select public.record_loan_payment('00000000-0000-0000-0008-0000000000f1', 2, 5000::bigint)),
  0::bigint, 'the last payment finishes the installment');
select is((select status from public.family_loans where id = '00000000-0000-0000-0008-0000000000f1'),
  'repaid', 'with nothing left, the loan turns repaid');

-- --- an over payment is the service's ---------------------------------------

-- --- the payment is audit-logged --------------------------------------------------

reset role;
select is((select count(*) from private.audit_log where action = 'loan.payment'),
  3::bigint, 'every payment is audit-logged (refusals write nothing)');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0008-0000000000a1');
select throws_ok($$select public.record_loan_payment('00000000-0000-0000-0008-0000000000f1', 1, 100::bigint)$$,
  '42501', 'loan payments are moved by the service',
  'a member cannot record a payment: the partner moves money');
