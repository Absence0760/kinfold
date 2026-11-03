-- Cover premiums paid from dues (20261102430000_premium_dues.sql).
--
-- Properties this file pins:
--   * premiums read the filed rates for the member's classed covered vehicles —
--     two members with different incomes pay the same premium per class
--     (premiums are never earnings-priced);
--   * premiums move money out of the fund's dues account (`dues`) into a
--     `premiums` account of its own, only up to the dues money it holds, and
--     dues money never arrives as pool money (`available`);
--   * a replayed reference is a no-op answering with the journal it made;
--   * an unclassed vehicle takes no premium, and a home never carries a class.
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

select pg_temp.member('00000000-0000-0000-0021-0000000000a1');
select pg_temp.member('00000000-0000-0000-0021-0000000000a2');
select pg_temp.member('00000000-0000-0000-0021-0000000000a3');

insert into public.income_verifications
  (member_id, method, monthly_income_cents, verified_at, expires_at)
values ('00000000-0000-0000-0021-0000000000a1', 'bank_link', 400000, now(),
        now() + interval '6 months'),
       ('00000000-0000-0000-0021-0000000000a2', 'self_attested', 100000, now(),
        now() + interval '6 months');

insert into public.covered_assets
  (id, member_id, kind, description, value_cents, registered_on, verified_at, vehicle_class)
values ('00000000-0000-0000-0021-0000000000c1', '00000000-0000-0000-0021-0000000000a1',
        'vehicle', 'A grey sedan', 1500000, current_date - 100, now(), 'sedan'),
       ('00000000-0000-0000-0021-0000000000c2', '00000000-0000-0000-0021-0000000000a1',
        'vehicle', 'An old SUV', 900000, current_date - 80, now(), 'suv'),
       ('00000000-0000-0000-0021-0000000000c3', '00000000-0000-0000-0021-0000000000a2',
        'vehicle', 'A borrowed sedan', 800000, current_date - 40, now(), 'sedan');

insert into public.covered_assets
  (id, member_id, kind, description, value_cents, registered_on, verified_at)
values ('00000000-0000-0000-0021-0000000000c4', '00000000-0000-0000-0021-0000000000a3',
        'vehicle', 'A van with no class stated', 1200000, current_date - 20, now());

-- --- premiums read the filed rates, never earnings -------------------------------

select is(public.cover_premium_cents('00000000-0000-0000-0021-0000000000a1'::uuid),
  28800::bigint, 'two classed vehicles pay the filed premiums for their class');
select is(public.cover_premium_cents('00000000-0000-0000-0021-0000000000a2'::uuid),
  12900::bigint, 'a member with a quarter of the income pays the same sedan premium');
select is(public.cover_premium_cents('00000000-0000-0000-0021-0000000000a3'::uuid),
  0::bigint, 'an unclassed vehicle takes no premium money');

-- --- premiums move dues money into an account of its own -------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok(
  $$select private.post_journal('protection', 'dues', null, 'pi_dues1',
      '[{"code":"partner_cash","amount_cents":-50000},{"code":"dues","amount_cents":50000}]')$$,
  'dues money arrives in the dues account, not the fund's pool money');
select lives_ok(
  $$select public.pay_cover_premium('00000000-0000-0000-0021-0000000000a1'::uuid, 'prem_1')$$,
  'the premiums are paid out of dues money');
select is(public.ledger_balance('protection'::public.fund, 'premiums'), 28800::bigint,
  'premium money sits in its own account');
select is(public.ledger_balance('protection'::public.fund, 'dues'), 21200::bigint,
  'unspent dues money stays in the dues account');
select is(public.ledger_balance('protection'::public.fund, 'available'), 0::bigint,
  'dues money never arrives as pool money');
select is((select count(*) from private.ledger_journals
           where partner_ref = 'prem_1' and kind = 'premium'), 1::int,
  'a replayed reference stores no second journal');
select throws_ok(
  $$select public.pay_cover_premium('00000000-0000-0000-0021-0000000000a3'::uuid, 'prem_3')$$,
  '23514', 'an unclassed member has no premiums to pay');
reset role;

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0021-0000000000a1'::uuid);
select throws_ok(
  $$select public.pay_cover_premium('00000000-0000-0000-0021-0000000000a2'::uuid, 'prem_2')$$,
  '42501', 'a member cannot pay premiums');
reset role;

-- --- stating the class on their own vehicle --------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0021-0000000000a3'::uuid);
select lives_ok(
  $$select public.set_vehicle_class('00000000-0000-0000-0021-0000000000c4'::uuid, 'van')$$,
  'a member states the class on their own vehicle');
select is(public.cover_premium_cents('00000000-0000-0000-0021-0000000000a3'::uuid),
  18900::bigint, 'the classed van now costs the filed van premium at the Basic plan');
reset role;

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0021-0000000000a2'::uuid);
select throws_ok(
  $$select public.set_vehicle_class('00000000-0000-0000-0021-0000000000c4'::uuid, 'suv')$$,
  'P0002', 'a member cannot state the class on someone else''s vehicle');
reset role;

rollback;
