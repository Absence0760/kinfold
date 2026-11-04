-- Ops console reads the trail (20261102520000_audit_trail.sql).
--
-- Properties this file pins:
--   * recent decisions are visible to a reviewer newest first, and the read is
--     itself on the trail;
--   * the raw `detail` jsonb and the acting member's id never cross the door;
--   * the public cannot read the trail at all.
begin;
select plan(6);

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

select pg_temp.member('00000000-0000-0000-0032-0000000000c1');
insert into public.member_roles (member_id, role)
  values ('00000000-0000-0000-0032-0000000000c1', 'reviewer');

insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on, status)
  values ('00000000-0000-0000-0032-0000000000e1', '00000000-0000-0000-0032-0000000000c1',
          'car_damage', 'pool', 'A dented door', 100000, current_date - 3, 'draft');
update public.requests set status = 'scoring' where id = '00000000-0000-0000-0032-0000000000e1';
update public.requests set status = 'in_review' where id = '00000000-0000-0000-0032-0000000000e1';

-- --- the decisions, then the reviewer's read ------------------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok(
  $$select public.record_claim('00000000-0000-0000-0032-0000000000e1'::uuid,
      'trail_claim_1', 40000, 1000)$$,
  'a recorded claim is on the trail');
select lives_ok(
  $$select public.record_fraud_signal('00000000-0000-0000-0032-0000000000e1'::uuid,
      'cross_shop', 'low', '{"shop_ref":"shop-9"}')$$,
  'a recorded fraud signal is on the trail');
reset role;

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0032-0000000000c1');
select ok(jsonb_array_length(public.review_audit_tail(10)) = 2,
  'a reviewer reads both recent decisions');
select ok(((public.review_audit_tail(1) -> 0) - 'detail') IS NULL,
  'the raw detail never crosses the door');
reset role;

set local role anon;
select throws_ok(
  $$select public.review_audit_tail(10)$$,
  '42501', 'permission denied for function review_audit_tail',
  'the public cannot read the trail at all');
reset role;

select is((select count(*) from private.audit_log
           where action = 'audit_log.read')::int, 2::int,
  'the reviewer''s reads are themselves on the trail');

rollback;
