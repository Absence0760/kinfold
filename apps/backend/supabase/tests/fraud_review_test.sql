-- Reviewer read of fraud signals (20261102500000_fraud_review.sql).
--
-- Properties this file pins:
--   * the checks' findings are visible to the operations console and to nobody
--     else: a reviewer sees them, a plain member is refused;
--   * the read answers kind and severity only — the match detail (photo hashes,
--     cross-reference ids) never crosses into the response;
--   * high-severity findings read first, and resolved findings are gone.
begin;
select plan(9);

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

select pg_temp.member('00000000-0000-0000-0025-0000000000f1');
select pg_temp.member('00000000-0000-0000-0025-0000000000f2');

insert into public.member_roles (member_id, role)
  values ('00000000-0000-0000-0025-0000000000f1', 'reviewer');

insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on, status)
  values ('00000000-0000-0000-0025-0000000000e1', '00000000-0000-0000-0025-0000000000f2',
          'car_damage', 'people', 'A dented door', 100000, current_date - 3, 'draft');
update public.requests set status = 'scoring' where id = '00000000-0000-0000-0025-0000000000e1';
update public.requests set status = 'in_review' where id = '00000000-0000-0000-0025-0000000000e1';

-- --- the checks' findings, and the reviewer's read ------------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok(
  $$select public.record_fraud_signal('00000000-0000-0000-0025-0000000000e1'::uuid,
      'duplicate_photos', 'high', '{"photo_sha256":"deadbeef"}')$$,
  'the high-severity finding is recorded');
select lives_ok(
  $$select public.record_fraud_signal('00000000-0000-0000-0025-0000000000e1'::uuid,
      'cross_shop', 'low', '{"shop_ref":"shop-9"}')$$,
  'a low-severity finding is recorded too');
reset role;

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0025-0000000000f1');
select is(
  public.review_fraud_signals('00000000-0000-0000-0025-0000000000e1'::uuid),
  '[{"kind": "duplicate_photos", "severity": "high"},
    {"kind": "cross_shop", "severity": "low"}]'::jsonb,
  'a reviewer sees both findings, high severity first');
select ok(
  ((public.review_fraud_signals('00000000-0000-0000-0025-0000000000e1'::uuid)
    -> 0) - 'detail') IS NULL,
  'the match detail never crosses into the read');
select is(
  public.review_fraud_signals('00000000-0000-0000-0025-0000000000e2'::uuid),
  '[]'::jsonb,
  'a request with no findings reads as nothing found');
reset role;

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0025-0000000000f2');
select throws_ok(
  $$select public.review_fraud_signals('00000000-0000-0000-0025-0000000000e1'::uuid)$$,
  '42501', 'the requester cannot read the findings against their own request');
reset role;

-- --- the read leaves a trail, and resolution takes a finding away ---------------

select is((select count(*) from private.audit_log
           where action = 'fraud_signals.read')::int, 3::int,
  'a reviewer''s read of the findings is on the trail');

set local role service_role;
select pg_temp.as_service();
select lives_ok(
  $$select public.resolve_fraud_signal(
      (select id from private.fraud_signals
       where request_id = '00000000-0000-0000-0025-0000000000e1'::uuid
         and severity = 'high'))$$,
  'the checks or the console resolve the finding');
reset role;

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0025-0000000000f1');
select is(
  public.review_fraud_signals('00000000-0000-0000-0025-0000000000e1'::uuid),
  '[{"kind": "cross_shop", "severity": "low"}]'::jsonb,
  'a resolved finding is gone from the read');
reset role;

rollback;
