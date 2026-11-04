-- Income checks (20261102270000_income_verification.sql).
--
-- Properties this file pins:
--   * the service records an income check for an active member, and the bank-
--     link leg carries the vendor's reference (a self-attested figure doesn't
--     need one);
--   * a negative income figure and a member who isn't active are refused;
--   * the record stores the figure the service passed and keeps the audit
--     trail; the member then reads their own check.
begin;
select plan(8);

-- --- fixtures ------------------------------------------------------------------

create function pg_temp.member(p_id uuid, p_status public.member_status default 'active')
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
  values (p_id, 'Member ' || right(p_id::text, 4), 'CA', p_status);
  select p_id;
$$;

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

select pg_temp.member('00000000-0000-0000-0011-0000000000a1');
select pg_temp.member('00000000-0000-0000-0011-0000000000a2', 'pending_verification');

-- --- recording a check ---------------------------------------------------------

set local role service_role;
select pg_temp.as_service();
select isnt((select record_income_verification('00000000-0000-0000-0011-0000000000a1',
                              'bank_link', 450000::bigint, 'bank-ref-1')), NULL::uuid,
  'the bank-linked check is recorded');
select is((select count(*) from public.income_verifications
           where member_id = '00000000-0000-0000-0011-0000000000a1'
             and method = 'bank_link' and monthly_income_cents = 450000
             and provider_ref = 'bank-ref-1'),
  1::bigint, 'the figure and the vendor reference land on the row');
select isnt((select record_income_verification('00000000-0000-0000-0011-0000000000a1',
                              'self_attested', 300000::bigint)), NULL::uuid,
  'a self-attested figure needs no vendor reference');
reset role;
select is((select count(*) from private.audit_log where action = 'income.verified'),
  2::bigint, 'each income check is audit-logged (the figure stays off the log)');
set local role service_role;
select pg_temp.as_service();

-- --- refusals ------------------------------------------------------------------

select throws_ok($$select record_income_verification('00000000-0000-0000-0011-0000000000a1',
                       'bank_link', 450000::bigint)$$,
  '23514', 'a bank-linked income check needs the vendor''s reference',
  'an untraceable bank figure is refused');
select throws_ok($$select record_income_verification('00000000-0000-0000-0011-0000000000a1',
                       'tax_return', -1::bigint)$$,
  '23514', 'a monthly income figure can''t be negative',
  'a negative income figure is refused');
select throws_ok($$select record_income_verification('00000000-0000-0000-0011-0000000000a2',
                       'tax_return', 300000::bigint)$$,
  'P0002', 'member not found or not active',
  'income is checked for active members only');

-- --- the member reads their own check -----------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0011-0000000000a1');
select is((select count(*) from public.income_verifications),
  2::bigint, 'the member reads both of their own checks');
