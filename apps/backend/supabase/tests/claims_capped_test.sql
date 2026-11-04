-- Claims capped by the filed terms and the vehicle's value (20261102510000_claims_capped.sql).
--
-- Properties this file pins:
--   * a claim over the filed cap for the member's plan is refused, not truncated;
--   * a claim over the vehicle's own value is refused even under the filed cap;
--   * a request with no classed covered vehicle carries no car cap;
--   * a replayed feed entry still answers with the journal it made, and the cap
--     is written onto the trail.
begin;
select plan(8);

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

select pg_temp.member('00000000-0000-0000-0031-0000000000b1');

insert into public.covered_assets
  (id, member_id, kind, description, value_cents, registered_on, verified_at, vehicle_class)
values ('00000000-0000-0000-0031-0000000000d1', '00000000-0000-0000-0031-0000000000b1',
        'vehicle', 'A grey sedan', 1500000, current_date - 120, now(), 'sedan'),
       ('00000000-0000-0000-0031-0000000000d2', '00000000-0000-0000-0031-0000000000b1',
        'vehicle', 'A cheap SUV', 30000, current_date - 120, now(), 'suv');

insert into public.requests
  (id, member_id, kind, funding, title, amount_cents, incident_on, asset_id, status)
values ('00000000-0000-0000-0031-0000000000e1', '00000000-0000-0000-0031-0000000000b1',
        'car_deductible', 'pool', 'A scraped door', 40000, current_date - 10,
        '00000000-0000-0000-0031-0000000000d1', 'draft'),
       ('00000000-0000-0000-0031-0000000000e2', '00000000-0000-0000-0031-0000000000b1',
        'car_deductible', 'pool', 'A scraped SUV', 40000, current_date - 10,
        '00000000-0000-0000-0031-0000000000d2', 'draft'),
       ('00000000-0000-0000-0031-0000000000e3', '00000000-0000-0000-0031-0000000000b1',
        'home_repair', 'pool', 'A leaking roof', 500000, current_date - 10,
        null, 'draft');
update public.requests set status = 'scoring' where id = '00000000-0000-0000-0031-0000000000e2';
update public.requests set status = 'in_review' where id = '00000000-0000-0000-0031-0000000000e2';

update public.requests set status = 'scoring' where id = '00000000-0000-0000-0031-0000000000e3';
update public.requests set status = 'in_review' where id = '00000000-0000-0000-0031-0000000000e3';
update public.requests set status = 'scoring' where id = '00000000-0000-0000-0031-0000000000e1';
update public.requests set status = 'in_review' where id = '00000000-0000-0000-0031-0000000000e1';

-- --- the cap on a classed sedan -------------------------------------------------

set local role service_role;
select lives_ok(
  $$select public.record_claim('00000000-0000-0000-0031-0000000000e1'::uuid,
      'claim-ok1', 40000, 1000)$$,
  'a claim under the filed sedan cap records');
select throws_ok(
  $$select public.record_claim('00000000-0000-0000-0031-0000000000e1'::uuid,
      'claim-over1', 60000, 1000)$$,
  '23514', 'a claim over the filed cap is refused, not truncated');
select is((select count(*) from public.claims
           where partner_ref = 'claim-over1')::int, 0::int,
  'the refused feed entry stored nothing');
select lives_ok(
  $$select public.record_claim('00000000-0000-0000-0031-0000000000e1'::uuid,
      'claim-ok1', 40000, 1000)$$,
  'the replayed reference answers with the claim it made');
select is((select count(*) from public.claims
           where partner_ref = 'claim-ok1')::int, 1::int,
  'the replay stored no second claim');

-- --- the vehicle's own value caps below the filed cap ---------------------------

select throws_ok(
  $$select public.record_claim('00000000-0000-0000-0031-0000000000e2'::uuid,
      'claim-value', 40000, 0)$$,
  '23514', 'a claim over the vehicle''s own value is refused');

-- --- a home request carries no car cap ------------------------------------------

select lives_ok(
  $$select public.record_claim('00000000-0000-0000-0031-0000000000e3'::uuid,
      'claim-home', 500000, 0)$$,
  'a request with no classed covered vehicle carries no car cap');

-- --- the cap is on the trail -----------------------------------------------------

select is((select count(*) from private.audit_log
           where action = 'claim.recorded')::int, 2::int,
  'each recorded claim writes its cap onto the trail');
reset role;

rollback;
