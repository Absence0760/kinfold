-- The pool stacks after insured cover (20261102330000_pool_insured_cover.sql).
--
-- Properties this file pins, mirroring design.md's split of car help into
-- insured cover and the gift-funded repair fund:
--   * `insured_cover_cents` answers with the gross of the claims that stand
--     on a request, and a denied claim covers nothing;
--   * a request's pool need subtracts the cover BEFORE pledges: a claim of
--     300.00 on a 1,000.00 request gets a grant of 700.00 from a full fund,
--     not 1,000.00;
--   * a fully covered request gets no allocation at all (its need is zero);
--   * a request whose only claim was denied needs the whole amount back.
begin;
select plan(7);

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

create function pg_temp.payee(p_id uuid, p_kind public.payee_kind default 'repair_shop',
                              p_status public.verification_status default 'verified')
returns uuid language sql as $$
  insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at)
  values (p_id, p_kind, 'Payee ' || right(p_id::text, 4), 'CA', p_status,
          case when p_status = 'verified' then 'acct_' || p_id::text end,
          case when p_status = 'verified' then now() end)
  returning id;
$$;

create function pg_temp.request(p_id uuid, p_member uuid, p_amount bigint,
                                p_payee uuid default null)
returns uuid language sql as $$
  insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on, payee_id)
  values (p_id, p_member, 'car_damage', 'pool', 'Test request', p_amount, current_date - 5, p_payee)
  returning id;
$$;

create function pg_temp.move(p_request uuid, variadic p_path public.request_status[])
returns void language plpgsql as $$
declare
  s public.request_status;
begin
  foreach s in array p_path loop
    update public.requests set status = s where id = p_request;
  end loop;
end $$;

-- Fixtures carry a reason on every claim: a denied row must carry the person's
-- words (the table check `denials_carry_their_reason` refuses a wordless denial).
create function pg_temp.claim(p_request uuid, p_gross bigint, p_partner_ref text,
                              p_status public.claim_status default 'recorded')
returns void language sql as $$
  insert into public.claims (request_id, partner_ref, gross_cents, member_share_cents,
                             paid_cents, status, reason)
  values (p_request, p_partner_ref, p_gross, 0, p_gross, p_status,
          'the pool cover fixture stands in for a filed claim');
$$;

-- Each run starts from an empty board so only this file's requests count.
create function pg_temp.clear_board() returns void language sql as $$
  update public.requests set status = 'withdrawn' where status = 'open';
$$;

create function pg_temp.grant_of(p_run uuid, p_request uuid) returns bigint language sql as $$
  select grant_cents from public.pool_allocations where run_id = p_run and request_id = p_request;
$$;

select pg_temp.member('00000000-0000-0000-0015-0000000000a1', 'CA');
select pg_temp.payee('00000000-0000-0000-0015-0000000000c1');

-- --- cover stacks before pledges --------------------------------------------------

-- A: 1,000.00 request with a 300.00 recorded claim.
insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                             status, description, public_summary, public_summary_confirmed_at,
                             current_score, submitted_at, payee_id)
values ('00000000-0000-0000-0015-0000000000b1', '00000000-0000-0000-0015-0000000000a1',
        'car_damage', 'pool', 'Covered partly', 100000, current_date - 5, 'open',
        'A request the insurer covered partly.', 'Door panel after a lane-change rub',
        now(), 85::smallint, now() - interval '9 days',
        '00000000-0000-0000-0015-0000000000c1');
select pg_temp.claim('00000000-0000-0000-0015-0000000000b1', 30000::bigint, 'pc_1');
select is(public.insured_cover_cents('00000000-0000-0000-0015-0000000000b1'),
  30000::bigint, 'the cover read answers with the standing claim''s gross');
select pg_temp.claim('00000000-0000-0000-0015-0000000000b1', 50000::bigint, 'pc_2', 'denied');
select is(public.insured_cover_cents('00000000-0000-0000-0015-0000000000b1'),
  30000::bigint, 'the denied claim covers nothing');

-- B: 1,500.00 request fully covered by a 1,500.00 claim.
insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                             status, description, public_summary, public_summary_confirmed_at,
                             current_score, submitted_at, payee_id)
values ('00000000-0000-0000-0015-0000000000b2', '00000000-0000-0000-0015-0000000000a1',
        'car_damage', 'pool', 'Fully covered', 150000, current_date - 5, 'open',
        'A request the insurer already paid in full.', 'Roof rail after a shopping-cart storm',
        now(), 85::smallint, now() - interval '9 days',
        '00000000-0000-0000-0015-0000000000c1');
select pg_temp.claim('00000000-0000-0000-0015-0000000000b2', 150000::bigint, 'pc_3');

select set_config('test.run1', public.run_pool_allocation('protection', 400000)::text, true);
select is((select reserve_cents from public.pool_runs
           where id = current_setting('test.run1')::uuid),
  80000::bigint, 'the fund keeps its reserve as before');
select is(pg_temp.grant_of(current_setting('test.run1')::uuid, '00000000-0000-0000-0015-0000000000b1'),
  70000::bigint, 'the covered request is granted the gap, not the whole damage');
select is((select count(*) from public.pool_allocations
           where run_id = current_setting('test.run1')::uuid and request_id = '00000000-0000-0000-0015-0000000000b2'),
  0::bigint, 'the fully covered request gets no allocation at all');

-- C: a request whose only claim was denied needs the whole damage back.
select pg_temp.clear_board();
insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                             status, description, public_summary, public_summary_confirmed_at,
                             current_score, submitted_at, payee_id)
values ('00000000-0000-0000-0015-0000000000b3', '00000000-0000-0000-0015-0000000000a1',
        'car_damage', 'pool', 'Denied cover', 100000, current_date - 5, 'open',
        'A request whose insurance denial puts the whole damage on the pool.',
        'Fender after a slow corner clipping', now(), 85::smallint, now() - interval '9 days',
        '00000000-0000-0000-0015-0000000000c1');
select pg_temp.claim('00000000-0000-0000-0015-0000000000b3', 40000::bigint, 'pc_4', 'denied');
select set_config('test.run2', public.run_pool_allocation('protection', 200000)::text, true);
select is(pg_temp.grant_of(current_setting('test.run2')::uuid, '00000000-0000-0000-0015-0000000000b3'),
  100000::bigint, 'the denied-claim request is granted the whole damage');

-- --- the read is claimable by members -------------------------------------------

select ok(has_function_privilege('authenticated', 'public.insured_cover_cents(uuid)', 'execute'),
  'members can read what their insured cover paid');
