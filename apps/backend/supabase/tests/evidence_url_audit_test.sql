-- Evidence URL audit (20261102310000_evidence_url_audit.sql).
--
-- Properties this file pins:
--   * the service records every evidence-URL issuing with the file it points
--     at, so a PII read leaves a trail;
--   * a missing request and an empty path are refused;
--   * a member can't issue anything.
begin;
select plan(5);

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
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

select pg_temp.member('00000000-0000-0000-0013-0000000000a1');
insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                             status, description, public_summary, public_summary_confirmed_at,
                             current_score, submitted_at)
values ('00000000-0000-0000-0013-0000000000b1', '00000000-0000-0000-0013-0000000000a1',
        'car_damage', 'pool', 'A request under review', 123456, current_date - 3, 'draft',
        'A dented fender after a shopping trolley clipped it.',
        'Fender after a slow corner clipping', now(), 72::smallint, now() - interval '2 days');
update public.requests set status = 'scoring' where id = '00000000-0000-0000-0013-0000000000b1';
update public.requests set status = 'in_review' where id = '00000000-0000-0000-0013-0000000000b1';

-- --- the audit follows every issuing ---------------------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.record_evidence_url('00000000-0000-0000-0013-0000000000b1',
  '00000000-0000-0000-0013-0000000000a1/00000000-0000-0000-0013-0000000000b1/capture.jpg')$$,
  'the service records an issuing for the request under review');
reset role;
select is((select count(*) from private.audit_log where action = 'evidence.url_issued'),
  1::bigint, 'the audit row carries the trail (request and path in jsonb)');
set local role service_role;
select pg_temp.as_service();

-- --- refusals ------------------------------------------------------------------

select throws_ok($$select public.record_evidence_url('00000000-0000-0000-0013-00000000ffff', 'x/y.jpg')$$,
  'P0002', 'request not found', 'a missing request is refused');
select throws_ok($$select public.record_evidence_url('00000000-0000-0000-0013-0000000000b1', '')$$,
  '23514', 'an evidence URL needs the file it points at', 'an empty path is refused');

-- --- a member can't issue anything ---------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0013-0000000000a1');
select throws_ok($$select public.record_evidence_url('00000000-0000-0000-0013-0000000000b1', 'x/y.jpg')$$,
  '42501', 'permission denied for function record_evidence_url', 'a member cannot issue an evidence URL');
