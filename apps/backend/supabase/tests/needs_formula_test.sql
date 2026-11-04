-- Needs ranking for Home Fund applicants (20261102440000_needs_formula.sql).
--
-- Properties this file pins:
--   * the formula is published and versioned: v1 weights decide until a
--     newer effective version is filed;
--   * the score is the weighted banded points, and the inputs hash is logged
--     so the annual fairness audit can re-derive it;
--   * ranking waits for a scored Home Fund request: unscored and car requests
--     are refused, and only the service ranks;
--   * a replay at the effective version answers with the score already
--     recorded, no second row;
--   * the requester and the reviewers they may review read the ranking;
--     nobody else does.
begin;
select plan(12);

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
                    json_build_object('sub', p_id::text, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

select pg_temp.member('00000000-0000-0000-0024-0000000000a1');
select pg_temp.member('00000000-0000-0000-0024-0000000000a2', 'TX');
select pg_temp.member('00000000-0000-0000-0024-0000000000a3');

insert into public.member_roles (member_id, role)
  values ('00000000-0000-0000-0024-0000000000a2', 'reviewer');

-- Scored Home Fund applicant, waiting for review; a car request; an unscored
-- Home Fund request.
insert into public.requests (id, member_id, kind, funding, title, amount_cents,
                            incident_on)
values ('00000000-0000-0000-0024-0000000000b1', '00000000-0000-0000-0024-0000000000a1',
        'home_repair', 'pool', 'A roof to keep dry', 400000, current_date - 5),
       ('00000000-0000-0000-0024-0000000000b2', '00000000-0000-0000-0024-0000000000a1',
        'car_damage', 'pool', 'A dented fender', 80000, current_date - 4),
       ('00000000-0000-0000-0024-0000000000b3', '00000000-0000-0000-0024-0000000000a1',
        'down_payment', 'pool', 'A down payment to shrink', 150000, current_date - 3);

-- The schema only lets requests start as drafts; score them along the normal
-- path: r1 waits in review, r2 is open, r3 is still only scoring.
update public.requests set status = 'scoring'
  where id = '00000000-0000-0000-0024-0000000000b1'
     or id = '00000000-0000-0000-0024-0000000000b2'
     or id = '00000000-0000-0000-0024-0000000000b3';
update public.requests set status = 'in_review'
  where id = '00000000-0000-0000-0024-0000000000b1';
update public.requests set status = 'open'
  where id = '00000000-0000-0000-0024-0000000000b2';

-- --- the published formula decides the weights -----------------------------------

select is(public.needs_formula_version(), 1, 'the seeded v1 formula is effective');

set local role service_role;
select pg_temp.as_service();

-- --- the score is the weighted banded points, inputs logged ------------------------

select is(public.record_needs('00000000-0000-0000-0024-0000000000b1'::uuid,
                              80::smallint, 60::smallint, 90::smallint,
                              encode(extensions.digest('e', 'sha256'), 'hex')),
  78::smallint, 'v1 weights: need half, readiness and reliability a quarter each');
select is(public.needs_score('00000000-0000-0000-0024-0000000000b1'::uuid),
  78::smallint, 'the ranking reads back for the request');
select is((select count(*) from public.needs_records
           where request_id = '00000000-0000-0000-0024-0000000000b1'), 1::bigint,
  'one applicant row with its inputs hash');
select is(public.record_needs('00000000-0000-0000-0024-0000000000b1'::uuid,
                              90::smallint, 90::smallint, 90::smallint,
                              encode(extensions.digest('f', 'sha256'), 'hex')),
  78::smallint, 'a replay at the same version answers with the score on the books');
select is((select count(*) from public.needs_records
           where request_id = '00000000-0000-0000-0024-0000000000b1'), 1::bigint,
  'the replay wrote no second row');

-- --- ranking waits for a scored Home Fund request ----------------------------------

select throws_ok(
  $$select public.record_needs('00000000-0000-0000-0024-0000000000b2'::uuid,
                               80::smallint, 60::smallint, 90::smallint, encode(extensions.digest('a', 'sha256'), 'hex'))$$,
  '23514', 'only Home Fund applicants get a needs ranking');
select throws_ok(
  $$select public.record_needs('00000000-0000-0000-0024-0000000000b3'::uuid,
                               80::smallint, 60::smallint, 90::smallint, encode(extensions.digest('b', 'sha256'), 'hex'))$$,
  '23514', 'a score is needed before an applicant is ranked');

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0024-0000000000a1'::uuid);
select throws_ok(
  $$select public.record_needs('00000000-0000-0000-0024-0000000000b1'::uuid,
                               80::smallint, 60::smallint, 90::smallint, encode(extensions.digest('c', 'sha256'), 'hex'))$$,
  '42501', 'applicants are ranked by the Fund''s own service path');
reset role;

-- --- who reads the ranking ----------------------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0024-0000000000a1'::uuid);
select is((select count(*) from public.needs_records
           where request_id = '00000000-0000-0000-0024-0000000000b1'), 1::bigint,
  'the requester reads their ranking');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0024-0000000000a2'::uuid);
select is((select count(*) from public.needs_records
           where request_id = '00000000-0000-0000-0024-0000000000b1'), 1::bigint,
  'a reviewer in another region reads the ranking they may review');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0024-0000000000a3'::uuid);
select is((select count(*) from public.needs_records
           where request_id = '00000000-0000-0000-0024-0000000000b1'), 0::bigint,
  'a member with no relation sees nothing');
reset role;

rollback;
