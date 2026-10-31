-- The community pool run: parity with the TypeScript reference
-- (apps/web/src/lib/requests/allocation.ts and allocation.test.ts), in cents.
--
-- Properties this file pins, one scenario per block, each mirroring a case in
-- allocation.test.ts (amounts x100, and the pool grossed up so that what's
-- left after the fund's reserve equals the TS pool):
--   * the top band is fully filled before the next band gets anything;
--   * a short band is split by need, the same share each, floored to the cent;
--   * requests below min_score are never paid, however full the pool;
--   * money already pledged reduces need, so the pool only covers the gap;
--   * reserve_bps is held back, and allocated + reserve never exceeds available;
--   * pool contributions are created and fully covered requests flip to funded;
--   * people-only requests and requests of the other fund are ignored.
-- Protection fund settings: min_score 70, band_size 10, reserve_bps 2000 (20%).
begin;
select plan(24);

-- --- fixtures ------------------------------------------------------------------
-- Temporary helpers, gone at rollback. They run as postgres (the owner), standing
-- in for the service role and the partner webhooks; clients can't do any of this.

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

-- An income check, a subscription and its first captured payment `p_ago` back:
-- cover starts on that date.
create function pg_temp.cover(p_member uuid, p_ago interval default '200 days')
returns void language sql as $$
  with iv as (
    insert into public.income_verifications (member_id, method, monthly_income_cents)
    values (p_member, 'bank_link', 400000) returning id
  ), sub as (
    insert into public.subscriptions (member_id, formula_version, income_verification_id, monthly_cents, starts_on)
    select p_member, 1, iv.id, 4000, (now() - p_ago)::date from iv returning id
  )
  insert into public.subscription_payments (subscription_id, member_id, period, amount_cents, status, captured_at)
  select sub.id, p_member, date_trunc('month', now() - p_ago)::date, 4000, 'captured', now() - p_ago from sub;
$$;

create function pg_temp.payee(p_id uuid, p_kind public.payee_kind default 'repair_shop',
                              p_status public.verification_status default 'verified')
returns uuid language sql as $$
  insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at)
  values (p_id, p_kind, 'Payee ' || right(p_id::text, 4), 'CA', p_status,
          case when p_status = 'verified' then 'acct_' || p_id::text end,
          case when p_status = 'verified' then now() end)
  returning id;
$$;

create function pg_temp.vehicle(p_id uuid, p_member uuid, p_registered date default current_date - 200)
returns uuid language sql as $$
  insert into public.covered_assets (id, member_id, kind, description, value_cents, registered_on, verified_at)
  values (p_id, p_member, 'vehicle', 'Test car', 1200000, p_registered, now())
  returning id;
$$;

create function pg_temp.request(p_id uuid, p_member uuid, p_funding public.funding_mode default 'pool',
                                p_amount bigint default 100000, p_kind public.request_kind default 'car_damage',
                                p_payee uuid default null, p_asset uuid default null)
returns uuid language sql as $$
  insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on, payee_id, asset_id)
  values (p_id, p_member, p_kind, p_funding, 'Test request', p_amount, current_date - 5, p_payee, p_asset)
  returning id;
$$;

create function pg_temp.evidence(p_request uuid, p_kind public.evidence_kind default 'photo',
                                 p_status public.redaction_status default 'confirmed')
returns uuid language sql as $$
  insert into public.evidence (request_id, kind, original_path, redacted_path, sha256, redaction_status)
  values (p_request, p_kind, gen_random_uuid()::text || '/original.jpg',
          case when p_status in ('auto_done', 'confirmed') then gen_random_uuid()::text || '/redacted.jpg' end,
          repeat('a', 64), p_status)
  returning id;
$$;

-- Walk a request through allowed transitions (the status guard still applies).
create function pg_temp.move(p_request uuid, variadic p_path public.request_status[])
returns void language plpgsql as $$
declare
  s public.request_status;
begin
  foreach s in array p_path loop
    update public.requests set status = s where id = p_request;
  end loop;
end $$;

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;

-- Each scenario starts from an empty board: close whatever else is open
-- (seed data included) so only this file's requests are candidates.
create function pg_temp.clear_board() returns void language sql as $$
  update public.requests set status = 'withdrawn' where status = 'open';
$$;

create function pg_temp.open_request(p_id uuid, p_amount bigint, p_score smallint,
                                     p_funding public.funding_mode default 'pool',
                                     p_kind public.request_kind default 'car_damage')
returns uuid language sql as $$
  select pg_temp.request(p_id, '00000000-0000-0000-0005-0000000000a1', p_funding, p_amount, p_kind,
                         '00000000-0000-0000-0005-0000000000c1');
  select pg_temp.move(p_id, 'scoring', 'open');
  update public.requests set current_score = p_score where id = p_id;
  select p_id;
$$;

create function pg_temp.grant_of(p_run uuid, p_request uuid) returns bigint language sql as $$
  select grant_cents from public.pool_allocations where run_id = p_run and request_id = p_request;
$$;

select pg_temp.member('00000000-0000-0000-0005-0000000000a1', 'CA');
select pg_temp.member('00000000-0000-0000-0005-0000000000a2', 'NY');
-- Every request's shop is verified: the pool waits for a verified payee (hardening_test).
select pg_temp.payee('00000000-0000-0000-0005-0000000000c1');

select throws_ok($$select public.run_pool_allocation('people', 1000)$$,
  '22023', 'no pooled fund people', 'the people fund has no pool to run');
select throws_ok($$select public.run_pool_allocation('protection', -1)$$,
  '22023', 'available balance cannot be negative', 'a negative balance is refused');

-- --- 1. fills every request in the top band before the next band ---------------------
-- TS: a 1000 @95, b 500 @91, c 400 @85, pool 1700 -> 1000, 500, 200.
select pg_temp.clear_board();
select pg_temp.open_request('00000000-0000-0000-0005-0000000001b1', 100000, 95::smallint);
select pg_temp.open_request('00000000-0000-0000-0005-0000000001b2', 50000, 91::smallint);
select pg_temp.open_request('00000000-0000-0000-0005-0000000001b3', 40000, 85::smallint);
-- Never paid or not this run's business:
select pg_temp.open_request('00000000-0000-0000-0005-0000000001b4', 10000, 69::smallint);                       -- below min_score
select pg_temp.open_request('00000000-0000-0000-0005-0000000001b5', 10000, 99::smallint, 'people');             -- not a pool request
select pg_temp.open_request('00000000-0000-0000-0005-0000000001b6', 10000, 99::smallint, 'pool', 'home_repair'); -- other fund
select set_config('test.run1', public.run_pool_allocation('protection', 212500)::text, true);

select is((select (available_cents, reserve_cents, allocated_cents)::text from public.pool_runs
           where id = current_setting('test.run1')::uuid), '(212500,42500,170000)',
  'the run holds back reserve_bps and allocates the rest');
select is(pg_temp.grant_of(current_setting('test.run1')::uuid, '00000000-0000-0000-0005-0000000001b1'), 100000::bigint,
  'top band: first request fully funded');
select is(pg_temp.grant_of(current_setting('test.run1')::uuid, '00000000-0000-0000-0005-0000000001b2'), 50000::bigint,
  'top band: second request fully funded');
select is(pg_temp.grant_of(current_setting('test.run1')::uuid, '00000000-0000-0000-0005-0000000001b3'), 20000::bigint,
  'next band gets what is left');
select is((select array_agg(band order by request_id) from public.pool_allocations
           where run_id = current_setting('test.run1')::uuid), array[90, 90, 80]::smallint[],
  'bands are score floored to band_size');
select is((select count(*) from public.pool_allocations where run_id = current_setting('test.run1')::uuid
           and request_id in ('00000000-0000-0000-0005-0000000001b4', '00000000-0000-0000-0005-0000000001b5',
                              '00000000-0000-0000-0005-0000000001b6')), 0::bigint,
  'below-min, people-only and other-fund requests are not allocated');
select results_eq(
  $$select request_id, amount_cents, status::text from public.contributions
    where source = 'pool' and pool_allocation_id in
      (select id from public.pool_allocations where run_id = current_setting('test.run1')::uuid)
    order by request_id$$,
  $$values ('00000000-0000-0000-0005-0000000001b1'::uuid, 100000::bigint, 'pledged'::text),
           ('00000000-0000-0000-0005-0000000001b2', 50000, 'pledged'),
           ('00000000-0000-0000-0005-0000000001b3', 20000, 'pledged')$$,
  'each grant becomes a pool contribution');
select results_eq(
  $$select status::text from public.requests where id in
     ('00000000-0000-0000-0005-0000000001b1', '00000000-0000-0000-0005-0000000001b2',
      '00000000-0000-0000-0005-0000000001b3', '00000000-0000-0000-0005-0000000001b4') order by id$$,
  $$values ('funded'::text), ('funded'), ('open'), ('open')$$,
  'fully covered requests flip to funded, the partial and the low score stay open');

-- --- 2. splits a short pool by need within a band ----------------------------------------
-- TS: a 1000 @99, b 3000 @90, pool 2000 -> 500, 1500.
select pg_temp.clear_board();
select pg_temp.open_request('00000000-0000-0000-0005-0000000002b1', 100000, 99::smallint);
select pg_temp.open_request('00000000-0000-0000-0005-0000000002b2', 300000, 90::smallint);
select set_config('test.run2', public.run_pool_allocation('protection', 250000)::text, true);
select is(pg_temp.grant_of(current_setting('test.run2')::uuid, '00000000-0000-0000-0005-0000000002b1'), 50000::bigint,
  'short band: the smaller request gets the same share of its need');
select is(pg_temp.grant_of(current_setting('test.run2')::uuid, '00000000-0000-0000-0005-0000000002b2'), 150000::bigint,
  'short band: the larger request gets the same share of its need');
select is((select status from public.requests where id = '00000000-0000-0000-0005-0000000002b1'),
  'open'::public.request_status, 'a partly granted request stays open');

-- --- 3. never grants more than the pool holds (integer floor) -------------------------
-- TS: 333.33 @92, 333.33 @94, 333.34 @97, pool 100 -> each floor(need * 100/1000).
select pg_temp.clear_board();
select pg_temp.open_request('00000000-0000-0000-0005-0000000003b1', 33333, 92::smallint);
select pg_temp.open_request('00000000-0000-0000-0005-0000000003b2', 33333, 94::smallint);
select pg_temp.open_request('00000000-0000-0000-0005-0000000003b3', 33334, 97::smallint);
select set_config('test.run3', public.run_pool_allocation('protection', 12500)::text, true);
select is((select array_agg(grant_cents order by request_id) from public.pool_allocations
           where run_id = current_setting('test.run3')::uuid), array[3333, 3333, 3333]::bigint[],
  'shares are floored to whole cents');
select is((select allocated_cents from public.pool_runs where id = current_setting('test.run3')::uuid), 9999::bigint,
  'rounding dust stays in the pool, not over-granted');
select ok((select allocated_cents + reserve_cents <= available_cents from public.pool_runs
           where id = current_setting('test.run3')::uuid), 'allocated + reserve never exceeds available');

-- --- 4. counts money already raised from family and friends -------------------------------
-- TS: a 1000 @95 with 800 raised, pool 5000 -> 200, funded.
select pg_temp.clear_board();
select pg_temp.open_request('00000000-0000-0000-0005-0000000004b1', 100000, 95::smallint);
insert into public.contributions (request_id, contributor_id, source, amount_cents)
values ('00000000-0000-0000-0005-0000000004b1', '00000000-0000-0000-0005-0000000000a2', 'gift', 80000);
select set_config('test.run4', public.run_pool_allocation('protection', 625000)::text, true);
select is((select (need_cents, grant_cents)::text from public.pool_allocations
           where run_id = current_setting('test.run4')::uuid), '(20000,20000)',
  'existing pledges reduce need; the pool covers only the gap');
select is((select allocated_cents from public.pool_runs where id = current_setting('test.run4')::uuid), 20000::bigint,
  'the rest of the pool is left unallocated');
select is((select status from public.requests where id = '00000000-0000-0000-0005-0000000004b1'),
  'funded'::public.request_status, 'pledges plus the pool grant fund the request');

-- --- 5. leaves lower bands waiting when the pool runs out ----------------------------------
-- TS: a 1000 @95, b 1000 @75, pool 1000 -> b gets 0.
select pg_temp.clear_board();
select pg_temp.open_request('00000000-0000-0000-0005-0000000005b1', 100000, 95::smallint);
select pg_temp.open_request('00000000-0000-0000-0005-0000000005b2', 100000, 75::smallint);
select set_config('test.run5', public.run_pool_allocation('protection', 125000)::text, true);
select is(coalesce(pg_temp.grant_of(current_setting('test.run5')::uuid, '00000000-0000-0000-0005-0000000005b2'), 0), 0::bigint,
  'a lower band waits when the pool runs out');
select is((select count(*) from public.contributions where request_id = '00000000-0000-0000-0005-0000000005b2'), 0::bigint,
  'a waiting request gets no pool contribution');

-- --- 6. never pays requests below the minimum score ----------------------------------------
-- TS: low 100 @69, pool 10000 -> nothing paid, pool untouched.
select pg_temp.clear_board();
select pg_temp.open_request('00000000-0000-0000-0005-0000000006b1', 10000, 69::smallint);
select set_config('test.run6', public.run_pool_allocation('protection', 1250000)::text, true);
select is((select allocated_cents from public.pool_runs where id = current_setting('test.run6')::uuid), 0::bigint,
  'a below-min request is never paid, however full the pool');

-- --- 7. the other fund uses its own settings and its own requests ---------------------
-- Home fund: reserve_bps 1000 (10%).
select pg_temp.clear_board();
select pg_temp.open_request('00000000-0000-0000-0005-0000000007b1', 10000, 80::smallint, 'both', 'home_repair');
select pg_temp.open_request('00000000-0000-0000-0005-0000000007b2', 10000, 99::smallint);  -- protection
select set_config('test.run7', public.run_pool_allocation('home_fund', 100000)::text, true);
select is((select (reserve_cents, allocated_cents)::text from public.pool_runs
           where id = current_setting('test.run7')::uuid), '(10000,10000)',
  'the home fund holds back its own reserve and pays its own (''both'') request');
select is((select array_agg(request_id) from public.pool_allocations where run_id = current_setting('test.run7')::uuid),
  array['00000000-0000-0000-0005-0000000007b1'::uuid], 'a home fund run ignores protection requests');

reset role;
select * from finish();
rollback;
