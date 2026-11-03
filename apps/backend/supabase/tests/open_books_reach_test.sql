-- The published fairness measure on the open books (20261102660000_open_books_reach.sql).
--
-- Properties this file pins:
--   * a month publishes its pool-grant request count and the money of those
--     grants that went to households with no family lender of their own;
--   * a family loan only makes a household "has a lender" once it actually
--     carried money: a 'signed' loan does, a 'proposed' or 'cancelled' one
--     does not, so a refused or never-signed loan keeps the household on the
--     help-reached side;
--   * the small-numbers rules apply to the new cells the same way as to the
--     old ones: a month with 1 to 10 granted requests hides the count AND both
--     dollar totals, and dollars round to $1,000;
--   * the no-lender money never exceeds the month's allocated money.
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

-- A paid pool request with no family loan of its own: the household help
-- reached because nobody was lending it money.
create function pg_temp.request_in(p_id uuid, p_member uuid) returns void
language plpgsql as $$
begin
  set local session_replication_role = replica;
  insert into public.requests (id, member_id, kind, funding, title, amount_cents,
                               incident_on, status, current_score)
  values (p_id, p_member, 'car_damage', 'pool', 'Test request', 100000,
          current_date - 5, 'paid', 92);
  set local session_replication_role = origin;
end $$;

select pg_temp.member('00000000-0000-0000-0066-0000000000a1');  -- no loans at all
select pg_temp.member('00000000-0000-0000-0066-0000000000a2');  -- a carried family loan
select pg_temp.member('00000000-0000-0000-0066-0000000000a3');  -- only loans that never carried

insert into public.family_loans (id, borrower_id, lender_id, principal_cents, status)
values ('00000000-0000-0000-0066-0000000000d1', '00000000-0000-0000-0066-0000000000a2',
        '00000000-0000-0000-0066-0000000000a1', 400000, 'signed'),
       ('00000000-0000-0000-0066-0000000000d2', '00000000-0000-0000-0066-0000000000a3',
        '00000000-0000-0000-0066-0000000000a1', 400000, 'proposed'),
       ('00000000-0000-0000-0066-0000000000d3', '00000000-0000-0000-0066-0000000000a3',
        '00000000-0000-0000-0066-0000000000a1', 400000, 'cancelled');

-- Twelve paid pool requests in the month that ended over a week ago: four for the
-- member with no loans, four for the member whose only loans never carried money,
-- four for the member with a carried family loan.
select pg_temp.request_in(('00000000-0000-0000-0066-' || sprintf('%012d', i))::uuid,
  case when i <= 4 then '00000000-0000-0000-0066-0000000000a1'::uuid
       when i <= 8 then '00000000-0000-0000-0066-0000000000a3'::uuid
       else '00000000-0000-0000-0066-0000000000a2'::uuid end)
from generate_series(1, 12) i;

-- Three paid pool requests in an older small month: too small a
-- month to publish any count or dollar figure.
select pg_temp.request_in(('00000000-0000-0000-0066-' || sprintf('%012d', 20 + i))::uuid,
  '00000000-0000-0000-0066-0000000000a1'::uuid)
from generate_series(1, 3) i;

insert into public.pool_runs (id, fund, available_cents, reserve_cents, allocated_cents, settings,
                              algorithm_version, run_at)
values ('00000000-0000-0000-0066-0000000000f1', 'protection', 2000000, 300000, 1200000, '{}',
        'test', date_trunc('month', now()) - interval '2 months' + interval '3 days'),
       ('00000000-0000-0000-0066-0000000000f2', 'protection', 400000, 100000, 300000, '{}',
        'test', date_trunc('month', now()) - interval '3 months' + interval '3 days');

-- One grant of $1,000 per request, under a need of $1,500 so the run fell short.
insert into public.pool_allocations (run_id, request_id, score, band, need_cents, grant_cents)
select '00000000-0000-0000-0066-0000000000f1',
       ('00000000-0000-0000-0066-' || sprintf('%012d', i))::uuid, 92, 90, 150000, 100000
from generate_series(1, 12) i;

insert into public.pool_allocations (run_id, request_id, score, band, need_cents, grant_cents)
select '00000000-0000-0000-0066-0000000000f2',
       ('00000000-0000-0000-0066-' || sprintf('%012d', 20 + i))::uuid, 92, 90, 150000, 100000
from generate_series(1, 3) i;

-- --- publishing a big month --------------------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0066-0000000000a1');
select throws_ok($$select public.publish_open_books(date_trunc('month', now() - interval '2 months')::date)$$,
  '42501', 'permission denied for function publish_open_books',
  'a member cannot publish the open books');

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.publish_open_books(date_trunc('month', now() - interval '2 months')::date)$$,
  'the service publishes the month that ended over a week ago');

reset role;
select is((select pool_requests from public.open_books
           where fund = 'protection' and month = date_trunc('month', now() - interval '2 months')::date),
  12::bigint, 'the month publishes its pool-grant request count');
select is((select no_lender_cents from public.open_books
           where fund = 'protection' and month = date_trunc('month', now() - interval '2 months')::date),
  800000::bigint, 'the grants to the two households without a carried family loan are published');
select is((select allocated_cents from public.open_books
           where fund = 'protection' and month = date_trunc('month', now() - interval '2 months')::date),
  1200000::bigint, 'the all-grants figure stays as its own cell');
select is(((select allocated_cents from public.open_books
            where fund = 'protection' and month = date_trunc('month', now() - interval '2 months')::date)
          - (select no_lender_cents from public.open_books
             where fund = 'protection' and month = date_trunc('month', now() - interval '2 months')::date))::bigint,
  400000::bigint, 'only the grants to the member with a signed family loan stay off the no-lender figure');
select is_ok((select no_lender_cents from public.open_books
              where fund = 'protection' and month = date_trunc('month', now() - interval '2 months')::date)
             <= (select allocated_cents from public.open_books
                 where fund = 'protection' and month = date_trunc('month', now() - interval '2 months')::date),
  'the no-lender money never exceeds the month''s allocated money');
select is((select (requests_paid, paid_out_cents, reserve_cents, pool_runs, pool_runs_short)::text
           from public.open_books
           where fund = 'protection' and month = date_trunc('month', now() - interval '2 months')::date),
  '(0,0,300000,1,1)', 'the other cells of the month still publish as before');

-- --- a month too small to publish counts or dollars ---------------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.publish_open_books(date_trunc('month', now() - interval '3 months')::date)$$,
  'the service publishes the smaller month';

reset role;
select isnull((select pool_requests from public.open_books
               where fund = 'protection' and month = date_trunc('month', now() - interval '3 months')::date),
  'a month with three granted requests hides its pool-grant count');
select isnull((select no_lender_cents from public.open_books
               where fund = 'protection' and month = date_trunc('month', now() - interval '3 months')::date),
  'and the same month hides the no-lender money');
select isnull((select allocated_cents from public.open_books
               where fund = 'protection' and month = date_trunc('month', now() - interval '3 months')::date),
  'and the all-grants money, so no share can be worked out by subtraction');
select is((select pool_runs from public.open_books
           where fund = 'protection' and month = date_trunc('month', now() - interval '3 months')::date),
  1::bigint, 'the run count still publishes, as it never identified anyone');

-- --- a month is published once ------------------------------------------------------

set local role service_role;
select pg_temp.as_service();
select throws_ok($$select public.publish_open_books(date_trunc('month', now() - interval '2 months')::date)$$,
  '23505', null,
  'the month is published once, even with the new cells');

-- --- anyone reads the published books ------------------------------------------------

reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select is_ok((select count(*) from public.open_books) >= 4,
  'anon still reads every published month and fund');
reset role;

rollback;
