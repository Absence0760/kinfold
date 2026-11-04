-- The ops console reads the recorded reconcile differences
-- (20261102630000_ledger_alert_console.sql, over the table from
-- 20261102380000_ledger_alerts.sql).
--
-- Properties this file pins:
--   * the service records a difference and refuses a matching statement as an
--     alert at all;
--   * a reviewer reads the alerts newest first, with both figures exactly as
--     recorded - the console never re-derives the comparison;
--   * no member-level key crosses the door;
--   * a member without console standing and the public are refused outright;
--   * the reviewer's read is itself on the audit trail.
begin;
select plan(7);

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

select pg_temp.member('00000000-0000-0000-0063-0000000000c1');
insert into public.member_roles (member_id, role)
  values ('00000000-0000-0000-0063-0000000000c1', 'reviewer');
select pg_temp.member('00000000-0000-0000-0063-0000000000c2');  -- a member, no console role

-- --- the alert, and what is not an alert ---------------------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok(
  $$select public.record_ledger_difference('protection', 'available', 100000::bigint, 99000::bigint)$$,
  'the service records the difference the reconcile found');
select throws_ok(
  $$select public.record_ledger_difference('protection', 'reserve', 70000::bigint, 70000::bigint)$$,
  '23514', 'a matching statement is not a difference',
  'a statement that matches the ledger never becomes an alert');
reset role;

-- an older alert, written directly so the two differ in time (the table's check
-- still applies: a matching statement can't be inserted at all)
insert into public.ledger_differences (fund, code, statement_cents, ledger_cents, recorded_at)
  values ('home_fund', 'dues', 50000, 60000, current_timestamp - interval '1 day');

-- --- the console reads them, newest first --------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0063-0000000000c1');
select ok((
  select d IS NOT NULL
         and jsonb_array_length(d) = 2
         and (d -> 0 -> 'code') = '"available"'::jsonb
         and ((d -> 0 -> 'statement_cents'))::int = 100000
         and ((d -> 0 -> 'ledger_cents'))::int = 99000
  from (select public.review_ledger_differences(10) as d)
), 'a reviewer reads both alerts newest first, with the figures exactly as recorded');
select ok(((public.review_ledger_differences(10) -> 0) -> 'member_id') IS NULL,
  'no member-level key crosses the door');
reset role;

-- --- who cannot read them -----------------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0063-0000000000c2');
select throws_ok(
  $$select public.review_ledger_differences(10)$$,
  '42501', 'ledger differences are read by the operations console',
  'a member without console standing gets a refusal');
reset role;

set local role anon;
select throws_ok(
  $$select public.review_ledger_differences(10)$$,
  '42501', 'permission denied for function review_ledger_differences',
  'the public cannot read the alerts at all');
reset role;

select is((select count(*) from private.audit_log where action = 'ledger_differences.read')::int,
  2::int, 'the reviewer''s read is itself on the trail');

rollback;
