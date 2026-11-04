-- Panel answers on needs edge cases (20261102470000_needs_review.sql).
--
-- Properties this file pins:
--   * only a reviewer from another state answers, and only an applicant the
--     Fund has ranked; the requester and members with no relation are refused;
--   * the decision names the formula version it was made against and sits
--     beside the score, which it never edits;
--   * one decision per reviewer per formula version; decisions are history;
--   * the requester and the reviewers they may review read the decisions.
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
                    json_build_object('sub', p_id::text, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

select pg_temp.member('00000000-0000-0000-0027-0000000000a1');
select pg_temp.member('00000000-0000-0000-0027-0000000000a2', 'TX');
select pg_temp.member('00000000-0000-0000-0027-0000000000a3');

insert into public.member_roles (member_id, role)
  values ('00000000-0000-0000-0027-0000000000a2', 'reviewer');

insert into public.requests (id, member_id, kind, funding, title, amount_cents,
                            incident_on)
values ('00000000-0000-0000-0027-0000000000b1', '00000000-0000-0000-0027-0000000000a1',
        'home_repair', 'pool', 'A roof on a band boundary', 400000, current_date - 5),
       ('00000000-0000-0000-0027-0000000000b2', '00000000-0000-0000-0027-0000000000a1',
        'down_payment', 'pool', 'An applicant the Fund has not ranked', 150000, current_date - 3);

update public.requests set status = 'scoring'
  where id = '00000000-0000-0000-0027-0000000000b1'
     or id = '00000000-0000-0000-0027-0000000000b2';
update public.requests set status = 'in_review'
  where id = '00000000-0000-0000-0027-0000000000b1';

set local role service_role;
select pg_temp.as_service();
select is(public.record_needs('00000000-0000-0000-0027-0000000000b1'::uuid,
                              80::smallint, 60::smallint, 90::smallint,
                              encode(extensions.digest('e', 'sha256'), 'hex')),
  78::smallint, 'the Fund ranks the applicant');
reset role;

-- --- a reviewer answers the edge case ---------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0027-0000000000a2'::uuid);
select lives_ok($$select public.record_needs_decision(
  '00000000-0000-0000-0027-0000000000b1'::uuid, 'needs', 'the home floods every storm')$$,
  'a reviewer in another state answers the edge case');
select is((select count(*) from public.needs_reviews), 1::bigint, 'one decision on the books');
select is((select formula_version from public.needs_reviews), 1::int,
  'the decision names the formula version it was made against');
select throws_ok($$select public.record_needs_decision(
  '00000000-0000-0000-0027-0000000000b1'::uuid, 'not_needs', 'a second answer this month')$$,
  '23514', 'one answer per reviewer per formula version');
select throws_ok($$select public.record_needs_decision(
  '00000000-0000-0000-0027-0000000000b1'::uuid, 'needs', 'too short')$$,
  '23514', 'a decision carries a written reason');
reset role;

-- --- who cannot answer -------------------------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0027-0000000000a1'::uuid);
select throws_ok($$select public.record_needs_decision(
  '00000000-0000-0000-0027-0000000000b1'::uuid, 'needs', 'their own applicant')$$,
  '42501', 'the applicant is never answered by their own region');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0027-0000000000a3'::uuid);
select throws_ok($$select public.record_needs_decision(
  '00000000-0000-0000-0027-0000000000b1'::uuid, 'needs', 'no relation to this one')$$,
  '42501', 'a member with no relation answers nothing');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0027-0000000000a2'::uuid);
select throws_ok($$select public.record_needs_decision(
  '00000000-0000-0000-0027-0000000000b2'::uuid, 'needs', 'nothing on the books yet')$$,
  'P0002', 'an applicant the Fund has not ranked cannot be answered');
reset role;

set local role service_role;
select pg_temp.as_service();
select throws_ok($$select public.record_needs_decision(
  '00000000-0000-0000-0027-0000000000b1'::uuid, 'needs', 'the Fund ranks, a reviewer answers')$$,
  '42501', 'the service role cannot answer edge cases');
reset role;

-- --- decisions are history ----------------------------------------------------------

set local role service_role;
select pg_temp.as_service();
select throws_ok($$update public.needs_reviews set decision = 'not_needs'$$,
  '42501', 'needs_reviews is append-only');
reset role;

-- --- who reads the decisions ---------------------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0027-0000000000a1'::uuid);
select is((select count(*) from public.needs_reviews), 1::bigint,
  'the requester reads the decision made about their applicant');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0027-0000000000a2'::uuid);
select is((select count(*) from public.needs_reviews), 1::bigint,
  'the reviewer reads the decisions they may review');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0027-0000000000a3'::uuid);
select is((select count(*) from public.needs_reviews), 0::bigint,
  'a member with no relation reads nothing');
reset role;

rollback;
