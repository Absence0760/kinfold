-- A request's payee has to fit what the request asks for
-- (20261102190000_payee_fits.sql).
--
-- Properties this file pins:
--   * `payee_fits` answers one mapping, the same one the web form's `payeeKindsFor`
--     offers: shops for cars, a contractor for a repair, whoever pays the money back
--     for home money;
--   * `submit_request` refuses a mismatched payee, and a fitting payee still submits;
--   * the refusal is at submission, not at the draft: a member can save a draft with
--     any payee they picked, the gate is the step where money starts aiming somewhere.
begin;
select plan(10);

-- --- fixtures ------------------------------------------------------------------
-- Temporary helpers, gone at rollback. They run as postgres (the owner); clients
-- can't create members or payees.

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

create function pg_temp.payee(p_id uuid, p_kind public.payee_kind default 'repair_shop',
                              p_status public.verification_status default 'verified')
returns uuid language sql as $$
  insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at)
  values (p_id, p_kind, 'Payee ' || right(p_id::text, 4), 'CA', p_status,
          case when p_status = 'verified' then 'acct_' || p_id::text end,
          case when p_status = 'verified' then now() end)
  returning id;
$$;

-- p_payee_kind is the kind of the payee `p_payee` points at, so each draft
-- carries whatever mismatch the assertion below needs.
create function pg_temp.request(p_id uuid, p_member uuid, p_kind public.request_kind,
                                p_payee_kind public.payee_kind, p_amount bigint default 100000)
returns uuid language sql as $$
  insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on, payee_id)
  values (p_id, p_member, p_kind, 'people', 'Test request', p_amount, current_date - 5,
          (select id from public.payees where kind = p_payee_kind))
  returning id;
$$;

create function pg_temp.evidence(p_request uuid) returns void language sql as $$
  insert into public.evidence (request_id, kind, original_path, redacted_path, sha256, redaction_status)
  values (p_request, 'photo', gen_random_uuid()::text || '/original.jpg',
          gen_random_uuid()::text || '/redacted.jpg', repeat('a', 64), 'confirmed');
$$;

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;

select pg_temp.member('00000000-0000-0000-000f-0000000000a1');
select pg_temp.payee('00000000-0000-0000-000f-0000000000c1', 'repair_shop');
select pg_temp.payee('00000000-0000-0000-000f-0000000000c2', 'contractor');
select pg_temp.payee('00000000-0000-0000-000f-0000000000c3', 'lender');

-- --- the mapping ---------------------------------------------------------------

select is(public.payee_fits('car_damage', 'repair_shop'), true, 'a car request names a repair shop');
select is(public.payee_fits('car_deductible', 'repair_shop'), true,
  'a group deductible request names a repair shop');
select is(public.payee_fits('home_repair', 'contractor'), true, 'a home repair names a contractor');
select is(public.payee_fits('mortgage_gap', 'lender'), true, 'home money names whoever pays it back');
select is(public.payee_fits('loan_payoff', 'repair_shop'), false,
  'a repair shop cannot be paid for a loan payoff');
select is(public.payee_fits('home_repair', 'lender'), false, 'a home repair does not aim money at a lender');

-- --- submission ----------------------------------------------------------------

-- A repair drafted against a shop: the draft saved (the table allows it), the
-- submission refuses.
select pg_temp.request('00000000-0000-0000-000f-0000000000b1', '00000000-0000-0000-000f-0000000000a1',
                       'home_repair', 'repair_shop');
select pg_temp.evidence('00000000-0000-0000-000f-0000000000b1');
select is((select count(*) from public.requests where id = '00000000-0000-0000-000f-0000000000b1'),
  1::bigint, 'a mismatched payee can be drafted: the refusal is at submission, not at the form');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-000f-0000000000a1');
select throws_ok($$select public.submit_request('00000000-0000-0000-000f-0000000000b1')$$,
  '23514', 'the payee does not fit this request', 'a repair cannot be paid at a repair shop');

-- The same request against a contractor goes through.
select pg_temp.request('00000000-0000-0000-000f-0000000000b2', '00000000-0000-0000-000f-0000000000a1',
                       'home_repair', 'contractor');
select pg_temp.evidence('00000000-0000-0000-000f-0000000000b2');
select is(public.submit_request('00000000-0000-0000-000f-0000000000b2'), 'scoring'::public.request_status,
  'the same repair against a contractor submits');

-- A mortgage gap aimed at a shop, refused with the same words.
select pg_temp.request('00000000-0000-0000-000f-0000000000b3', '00000000-0000-0000-000f-0000000000a1',
                       'mortgage_gap', 'repair_shop');
select pg_temp.evidence('00000000-0000-0000-000f-0000000000b3');
select throws_ok($$select public.submit_request('00000000-0000-0000-000f-0000000000b3')$$,
  '23514', 'the payee does not fit this request', 'home money cannot be paid at a repair shop');
