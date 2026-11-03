-- The ops console's reserve panel (20261102640000_reserve_console.sql, over the
-- `pool_runs` table from 20261030120200_funding.sql).
--
-- Properties this file pins:
--   * the door answers the LATEST run per fund only: a superseded run of the
--     same fund never appears;
--   * the figures cross exactly as the run wrote them, newest first - the
--     console never re-derives them;
--   * the money line the door hands out still adds up (allocated + reserve
--     within the fund's money), so the panel can't show an impossible fund;
--   * no member-level key crosses the door;
--   * the service reads them too (the reconciliation job's own view);
--   * a member without console standing and the public are refused outright;
--   * the read is itself on the audit trail.
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

select pg_temp.member('00000000-0000-0000-0064-0000000000c1');
insert into public.member_roles (member_id, role)
  values ('00000000-0000-0000-0064-0000000000c1', 'reviewer');
select pg_temp.member('00000000-0000-0000-0064-0000000000c2');  -- a member, no console role

-- The fund's money as it stands: an older protection run the newer one supersedes,
-- the newer protection run, and one home_fund run between them in time.
insert into public.pool_runs (fund, available_cents, reserve_cents, allocated_cents,
                              settings, algorithm_version, run_at)
  values ('protection', 40000, 8000, 32000, '{"bands": [70]}', 'v1',
          current_timestamp - interval '10 days');
insert into public.pool_runs (fund, available_cents, reserve_cents, allocated_cents,
                              settings, algorithm_version, run_at)
  values ('protection', 51000, 21000, 30000, '{"bands": [70]}', 'v1',
          current_timestamp - interval '1 day');
insert into public.pool_runs (fund, available_cents, reserve_cents, allocated_cents,
                              settings, algorithm_version, run_at)
  values ('home_fund', 25000, 5000, 20000, '{"bands": [70]}', 'v1',
          current_timestamp - interval '5 days');

-- --- the console reads the fund's money ----------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0064-0000000000c1');
select ok((
  select d IS NOT NULL
         and jsonb_length(d) = 2
         and (d -> 0 -> 'fund') = '"protection"'::jsonb
         and ((d -> 0 -> 'reserve_cents'))::int = 21000
         and ((d -> 0 -> 'allocated_cents'))::int = 30000
         and (d -> 1 -> 'fund') = '"home_fund"'::jsonb
  from (select public.review_pool_runs(10) as d)
), 'a reviewer reads the latest run per fund, newest first, figures as written');

select ok((
  select ((d -> 0 -> 'allocated_cents'))::int + ((d -> 0 -> 'reserve_cents'))::int
       <= ((d -> 0 -> 'available_cents'))::int
  from (select public.review_pool_runs(10) as d)
), 'the money line the door hands out still adds up');

select ok(((public.review_pool_runs(10) -> 0) - 'member_id') IS NULL,
  'no member-level key crosses the door');
reset role;

-- --- the service reads them too ------------------------------------------------

set local role service_role;
select pg_temp.as_service();
select is(jsonb_length(public.review_pool_runs(10))::int, 2::int,
  'the service reads the same two runs (the reconciliation job''s own view)');
reset role;

-- --- who cannot read them -----------------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0064-0000000000c2');
select throws_ok(
  $$select public.review_pool_runs(10)$$,
  '42501', 'pool runs are read by the operations console',
  'a member without console standing gets a refusal');
reset role;

set local role anon;
select throws_ok(
  $$select public.review_pool_runs(10)$$,
  '42501', 'pool runs are read by the operations console',
  'the public cannot read the runs at all');
reset role;

select is((select count(*) from private.audit_log where action = 'pool_runs.read')::int,
  4::int, 'every console read of the runs is itself on the trail');

rollback;