-- The $1,000 limit on deductible cover (20261102650000_deductible_limit.sql).
--
-- Properties this file pins:
--   * the refiled stand-in annuals sit at the year's limit, and nothing on the
--     table promises deductible dollars above it;
--   * a filed annual above the limit is refused BY THE DOOR with the reason,
--     writes nothing to the rate row and nothing to the trail;
--   * the limit is also a table check, so a filed number cannot slip past it;
--   * the boundary at exactly $1,000 files, and is audit-logged;
--   * a member cannot file the annual at all;
--   * deductible dollars paid back to one member in a year never exceed the
--     limit, and once they are spent the member's share rises to the whole
--     loss rather than the claim being refused.
begin;
select plan(17);

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

select pg_temp.member('00000000-0000-0000-0065-0000000000b1');

insert into public.covered_assets
  (id, member_id, kind, description, value_cents, registered_on, verified_at, vehicle_class)
values ('00000000-0000-0000-0065-0000000000d1', '00000000-0000-0000-0065-0000000000b1',
        'vehicle', 'A grey sedan', 1500000, current_date - 120, now(), 'sedan');

insert into public.requests
  (id, member_id, kind, funding, title, amount_cents, incident_on, asset_id, status)
values ('00000000-0000-0000-0065-0000000000e1', '00000000-0000-0000-0065-0000000000b1',
        'car_deductible', 'pool', 'A scraped door', 50000, current_date - 10,
        '00000000-0000-0000-0065-0000000000d1', 'in_review');

-- --- the refiled stand-ins sit at the limit, and nothing exceeds it ------------------

select is((select annual_deductible_cents from public.cover_plans
           where vehicle_class = 'van' and plan = 'basic'),
  100000::bigint, 'the refiled stand-in annual sits at the year''s $1,000 limit');
select is((select count(*) from public.cover_plans
           where coalesce(annual_deductible_cents, 0) > 100000)::int, 0::int,
  'no filed annual on the table promises cover above the year''s limit');
select is_ok((select count(*) from private.cover_plans_history) >= 10,
  'the refiling trailed a history row per rate, like every other filed change');

-- --- an over-limit filing is refused by the door, with the reason --------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0065-0000000000b1');
select throws_ok($$select public.set_annual_deductible('sedan', 'basic', 200000::bigint,
  'partner_insurer', '2026-01-01'::date)$$,
  '42501', 'filed annual deductibles are written by the service',
  'a member cannot file the annual deductible at all');

set local role service_role;
select pg_temp.as_service();
select throws_ok($$select public.set_annual_deductible('sedan', 'basic', 200000::bigint,
  'partner_insurer', '2026-01-01'::date)$$,
  '23514', 'the deductible dollars one member may get back in a year are capped at 1000 dollars; a filed annual above that overstates the cover',
  'an annual above the year''s limit is refused with the reason, not applied');
select is((select annual_deductible_cents from public.cover_plans
           where vehicle_class = 'sedan' and plan = 'basic'),
  100000::bigint, 'the refused filing left the filed annual at the limit');
select is((select count(*) from private.audit_log where action = 'cover_plans.annual_filed')::int,
  0::int, 'the refused filing wrote nothing to the trail');

-- --- the boundary at exactly the limit files ----------------------------------------

select lives_ok($$select public.set_annual_deductible('sedan', 'basic', 100000::bigint,
  'partner_insurer', '2026-01-01'::date)$$,
  'an annual at exactly the year''s limit files');
select is((select count(*) from private.audit_log where action = 'cover_plans.annual_filed'),
  1::bigint, 'the accepted filing is audit-logged');

-- --- claims spend the annual up to the limit, then the share rises -------------------

select lives_ok($$select public.record_claim('00000000-0000-0000-0065-0000000000e1'::uuid,
  'dl_c1', 50000, 0)$$,
  'the first claim records with the whole annual deductible still left');
select lives_ok($$select public.mark_claim_paid((select id from public.claims
  where partner_ref = 'dl_c1'), 'dl_p1')$$,
  'the feed confirms the first claim paid in full');
select lives_ok($$select public.record_claim('00000000-0000-0000-0065-0000000000e1'::uuid,
  'dl_c2', 50000, 0)$$,
  'a second claim records while the annual still has its dollars left');
select lives_ok($$select public.mark_claim_paid((select id from public.claims
  where partner_ref = 'dl_c2'), 'dl_p2')$$,
  'the feed confirms the second claim, spending the annual to its limit');
select throws_ok($$select public.record_claim('00000000-0000-0000-0065-0000000000e1'::uuid,
  'dl_c3', 50000, 10000)$$,
  '23514', 'a member cannot take deductible cover beyond the annual deductible; the share rises with claims',
  'a share under the floor once the annual is spent is refused, not accepted');
select lives_ok($$select public.record_claim('00000000-0000-0000-0065-0000000000e1'::uuid,
  'dl_c3', 50000, 50000)$$,
  'once the annual is spent the member''s share rises to the whole loss');
select is((select paid_cents from public.claims where partner_ref = 'dl_c3'),
  0::bigint, 'the exhausted claim pays nothing: the member carries the loss');
select is_ok((select sum(c.paid_cents) from public.claims c
              where c.status = 'paid' and c.request_id = '00000000-0000-0000-0065-0000000000e1')
              <= 100000,
  'a member-year of deductible cover never exceeds the $1,000 limit');
reset role;

rollback;
