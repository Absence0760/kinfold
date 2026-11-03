-- The annual deductible floor (20261102580000_annual_deductible.sql).
--
-- Properties this file pins:
--   * the annual deductible is filed by the service, never by a member;
--   * a claim records while the member's deductible dollars are left;
--   * a denial uses none of the annual deductible, so the next claim still
--     records with the FULL deductible available;
--   * once the annual deductible is spent, the member's share must rise to
--     the whole loss — a share under the floor is refused, not accepted;
--   * a request with no classed covered vehicle has no annual deductible;
--   * paid is exactly gross minus share on every recorded claim.
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

select pg_temp.member('00000000-0000-0000-0058-0000000000b1');
select pg_temp.member('00000000-0000-0000-0058-0000000000b2');  -- reviewer

insert into public.covered_assets
  (id, member_id, kind, description, value_cents, registered_on, verified_at, vehicle_class)
values ('00000000-0000-0000-0058-0000000000d1', '00000000-0000-0000-0058-0000000000b1',
        'vehicle', 'A grey sedan', 1500000, current_date - 120, now(), 'sedan');

insert into public.requests
  (id, member_id, kind, funding, title, amount_cents, incident_on, asset_id, status)
values ('00000000-0000-0000-0058-0000000000e1', '00000000-0000-0000-0058-0000000000b1',
        'car_deductible', 'pool', 'A scraped door', 50000, current_date - 10,
        '00000000-0000-0000-0058-0000000000d1', 'in_review'),
       ('00000000-0000-0000-0058-0000000000e2', '00000000-0000-0000-0058-0000000000b1',
        'home_repair', 'pool', 'A leaking roof', 500000, current_date - 10,
        'in_review');

-- --- the annual deductible is the partner's to file ---------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0058-0000000000b1');
select throws_ok($$select public.set_annual_deductible('sedan', 'basic', 50000::bigint, 'partner_insurer', '2026-01-01'::date)$$,
  '42501', 'filed annual deductibles are written by the service',
  'a member cannot file the annual deductible');
select throws_ok($$select public.set_annual_deductible('sedan', 'basic', 0::bigint, 'partner_insurer', '2026-01-01'::date)$$,
  '23514', 'a filed annual deductible must be positive',
  'a zero annual deductible is refused');

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.set_annual_deductible('sedan', 'basic', 50000::bigint, 'partner_insurer', '2026-01-01'::date)$$,
  'the service files the annual deductible beside the rate');

-- --- a claim records while the deductible dollars are left ---------------------------

select lives_ok($$select public.record_claim('00000000-0000-0000-0058-0000000000e1'::uuid,
       'ad_c1', 50000, 0)$$,
  'the first claim records with the whole annual deductible left');
select is((select paid_cents from public.claims where partner_ref = 'ad_c1'),
  50000::bigint, 'paid is exactly gross minus the member''s share');

-- --- a denial uses none of the annual deductible -------------------------------------

insert into public.reviews (request_id, reviewer_id, decision, reason)
values ('00000000-0000-0000-0058-0000000000e1', '00000000-0000-0000-0058-0000000000b2', 'refuse',
        'The photos show parking damage, not a collision.');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0058-0000000000b2');
select lives_ok($$select public.deny_claim((select id from public.claims where partner_ref = 'ad_c1'), 'the reviewer''s photos show parking damage')$$,
  'a denial right after a recorded refuse review goes through');
select is((select count(*) from private.audit_log where action = 'claim.denied'),
  1::bigint, 'the denial is audit-logged');

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.record_claim('00000000-0000-0000-0058-0000000000e1'::uuid,
       'ad_c2', 50000, 0)$$,
  'the denied claim used none of the annual deductible, so the next claim records with the FULL deductible available');
select is((select paid_cents from public.claims where partner_ref = 'ad_c2'),
  50000::bigint, 'the second claim paid in full again: it is the paid claims, not the recorded ones, that spend the annual');

-- --- once the annual deductible runs out, the share must rise ------------------------

select throws_ok($$select public.record_claim('00000000-0000-0000-0058-0000000000e1'::uuid,
       'ad_c3', 50000, 10000)$$,
  '23514', 'a member cannot take deductible cover beyond the annual deductible; the share rises with claims',
  'a share under the annual floor is refused, not accepted');
select lives_ok($$select public.record_claim('00000000-0000-0000-0058-0000000000e1'::uuid,
       'ad_c3', 50000, 50000)$$,
  'once the deductible dollars are spent, the member''s share rises to the whole loss');
select is((select paid_cents from public.claims where partner_ref = 'ad_c3'),
  0::bigint, 'the exhausted claim pays nothing: the member carries it');

-- --- a home request carries no annual deductible --------------------------------------

select lives_ok($$select public.record_claim('00000000-0000-0000-0058-0000000000e2'::uuid,
       'ad_home', 500000, 0)$$,
  'a request with no classed covered vehicle has no annual deductible');

-- --- every recorded claim pays exactly gross minus share ------------------------------

select is((select count(*) from public.claims
           where paid_cents <> gross_cents - member_share_cents)::int, 0::int,
  'no claim stored a paid figure off gross minus share');
select is((select count(*) from private.audit_log where action = 'claim.recorded'),
  4::bigint, 'the four accepted claims wrote their caps onto the trail');
reset role;

rollback;
