-- In-person inspection (20261102410000_in_person_inspection.sql).
--
-- Properties this file pins:
--   * a request at or above its fund's large-amount line cannot become funded
--     until an inspection reports it clear; an issue-found or missing visit
--     leaves the door closed, and a clear one opens it;
--   * the partner's statement is service-written, append-only, and a retried
--     reference answers with the visit already made;
--   * a member reads only their own request's inspections and cannot record one.
begin;
select plan(14);

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

select pg_temp.member('00000000-0000-0000-0019-0000000000a1');
select pg_temp.member('00000000-0000-0000-0019-0000000000a2');

insert into public.requests (id, member_id, kind, funding, title, amount_cents,
                             incident_on, status, created_at)
values ('00000000-0000-0000-0019-0000000000b1', '00000000-0000-0000-0019-0000000000a1',
        'car_damage', 'pool', 'A large request', 5000000, current_date - 5, 'draft', now());
update public.requests set status = 'scoring' where id = '00000000-0000-0000-0019-0000000000b1';
update public.requests set status = 'open' where id = '00000000-0000-0000-0019-0000000000b1';

insert into public.requests (id, member_id, kind, funding, title, amount_cents,
                             incident_on, status, created_at)
values ('00000000-0000-0000-0019-0000000000b2', '00000000-0000-0000-0019-0000000000a2',
        'car_damage', 'pool', 'A small request', 4999999, current_date - 5, 'draft', now());
update public.requests set status = 'scoring' where id = '00000000-0000-0000-0019-0000000000b2';
update public.requests set status = 'open' where id = '00000000-0000-0000-0019-0000000000b2';

-- --- the large-amount line reads the fund's setting -----------------------------

select is(public.needs_inspection('00000000-0000-0000-0019-0000000000b1'::uuid), true,
  'a request at the line is large enough to need the visit');
select is(public.needs_inspection('00000000-0000-0000-0019-0000000000b2'::uuid), false,
  'a request just under the line can go without a visit');

-- --- the door stays shut until a clear visit ------------------------------------

select throws_ok($$update public.requests set status = 'funded'
  where id = '00000000-0000-0000-0019-0000000000b1'::uuid$$, '23514',
  'a large request cannot be funded without a clear inspection');
select is((select status from public.requests
           where id = '00000000-0000-0000-0019-0000000000b1'::uuid), 'open',
  'the refused change left the request open');

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.record_inspection('00000000-0000-0000-0019-0000000000b1'::uuid,
  'issue_found', 'insp_1', 'The shop has no such invoice')$$, 'the service records a visit');
select is((select result from public.inspections limit 1), 'issue_found',
  'what the inspector found is stored as they said it');
select throws_ok($$update public.requests set status = 'funded'
  where id = '00000000-0000-0000-0019-0000000000b1'::uuid$$, '23514',
  'an issue-found inspection still does not open the door');
select lives_ok($$select public.record_inspection('00000000-0000-0000-0019-0000000000b1'::uuid,
  'clear', 'insp_2')$$, 'the service records the clear visit');
select lives_ok($$update public.requests set status = 'funded'
  where id = '00000000-0000-0000-0019-0000000000b1'::uuid$$,
  'a clear inspection opens the door');

-- --- a retried statement is a no-op that answers with the visit ------------------

select is(public.record_inspection('00000000-0000-0000-0019-0000000000b1'::uuid,
  'clear', 'insp_2'),
  (select id from public.inspections where inspector_ref = 'insp_2'),
  'the retried reference answers with the visit it already made');
select is((select count(*) from public.inspections), 2::bigint,
  'the retry stored no second row');

-- --- members read their own and cannot write -------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0019-0000000000a1'::uuid);
select throws_ok($$select public.record_inspection('00000000-0000-0000-0019-0000000000b1'::uuid,
  'clear', 'insp_3')$$, '42501', 'a member cannot record an inspection');
select is((select count(*) from public.inspections), 2::bigint,
  'the requester reads what was found on their request');
reset role;

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0019-0000000000a2'::uuid);
select is((select count(*) from public.inspections), 0::bigint,
  'a member who isn''t the requester and isn''t a reviewer reads nothing');
reset role;

rollback;
