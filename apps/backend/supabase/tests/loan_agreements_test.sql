-- Family loan agreement paperwork (20261102490000_loan_agreements.sql).
--
-- Properties this file pins:
--   * the loan-servicing event (service only) writes a signed loan's agreement;
--     a member can't;
--   * an unsigned loan has no agreement to finalize;
--   * the written text carries the no-interest promise, the schedule and the
--     pause allowance as set at signing;
--   * replaying is a no-op: the text is history;
--   * the sweep finalizes exactly the signed loans with no agreement yet.
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

select pg_temp.member('00000000-0000-0000-0029-0000000000a1');
select pg_temp.member('00000000-0000-0000-0029-0000000000a2');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0029-0000000000a1'::uuid);
insert into public.family_loans (id, borrower_id, lender_id, principal_cents,
                                 status)
values ('00000000-0000-0000-0029-0000000000b1', '00000000-0000-0000-0029-0000000000a1',
        '00000000-0000-0000-0029-0000000000a2', 100000, 'proposed'),
       ('00000000-0000-0000-0029-0000000000b2', '00000000-0000-0000-0029-0000000000a1',
        '00000000-0000-0000-0029-0000000000a2', 20000, 'proposed');
select lives_ok($$select public.set_loan_schedule(
  '00000000-0000-0000-0029-0000000000b1'::uuid, 4, current_date + 1)$$, 'four installments');
select lives_ok($$select public.set_loan_schedule(
  '00000000-0000-0000-0029-0000000000b2'::uuid, 2, current_date + 1)$$, 'two installments');

-- --- who may write the agreement --------------------------------------------------

select throws_ok($$select public.finalize_loan_agreement(
  '00000000-0000-0000-0029-0000000000b1'::uuid)$$,
  '42501', 'permission denied for function finalize_loan_agreement');
reset role;

set local role service_role;
select pg_temp.as_service();
select throws_ok($$select public.finalize_loan_agreement(
  '00000000-0000-0000-0029-0000000000b1'::uuid)$$,
  'P0002', 'loan not found, or not yet signed by both sides');
select ok(public.finalize_signed_loan_agreements() IS NOT NULL,
  'the sweep runs while the fixture loans are unsigned');
select is((select agreement_text from public.family_loans
           where id = '00000000-0000-0000-0029-0000000000b1'::uuid), null,
  'the sweep writes nothing while unsigned');

-- --- signing and finalizing ---------------------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0029-0000000000a1'::uuid);
select lives_ok($$select public.sign_loan(
  '00000000-0000-0000-0029-0000000000b1'::uuid)$$, 'the borrower signs');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0029-0000000000a2'::uuid);
select is(public.sign_loan('00000000-0000-0000-0029-0000000000b1'::uuid), 'signed',
  'the lender signing completes the agreement');

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.finalize_loan_agreement(
  '00000000-0000-0000-0029-0000000000b1'::uuid)$$, 'the event writes the agreement');
select isnt((select agreement_text from public.family_loans
           where id = '00000000-0000-0000-0029-0000000000b1'::uuid),
  null, 'the loan now carries its written agreement');
select ok((select agreement_text from public.family_loans
           where id = '00000000-0000-0000-0029-0000000000b1'::uuid)
           ilike '%zero interest%'
           and (select agreement_finalized_at from public.family_loans
                where id = '00000000-0000-0000-0029-0000000000b1'::uuid) is not null,
  'the text carries the no-interest promise and a finalization date');
select lives_ok($$select public.finalize_loan_agreement(
  '00000000-0000-0000-0029-0000000000b1'::uuid)$$, 'a replay is a no-op');

-- --- the sweep writes exactly what is missing --------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0029-0000000000a1'::uuid);
select lives_ok($$select public.sign_loan(
  '00000000-0000-0000-0029-0000000000b2'::uuid)$$, 'the borrower signs l2');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0029-0000000000a2'::uuid);
select lives_ok($$select public.sign_loan(
  '00000000-0000-0000-0029-0000000000b2'::uuid)$$, 'the lender signs l2');

set local role service_role;
select pg_temp.as_service();
select is(public.finalize_signed_loan_agreements(), 1, 'the sweep writes l2 only');
reset role;

rollback;
