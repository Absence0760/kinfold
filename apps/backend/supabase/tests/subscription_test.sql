-- Subscriptions: the published formula, allocation preferences, one active plan.
--
-- Properties this file pins:
--   * subscription_amount is $0 below the income floor, 1% at and above it,
--     capped, and readable by anyone (it's the published formula);
--   * a formula version is a row: older and future versions price as written;
--   * a member's allocation preferences total exactly 100 (or are empty),
--     checked at commit, and members only manage their own;
--   * a member has at most one active subscription.
-- v1: floor 1,500.00/month, rate 100 bps, cap 60.00.
begin;
select plan(21);

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

select is(public.subscription_amount(0), 0::bigint, 'no income, no subscription');
select is(public.subscription_amount(149999), 0::bigint, '$0 just below the floor');
select is(public.subscription_amount(150000), 1500::bigint, '1% at the floor');
select is(public.subscription_amount(300000), 3000::bigint, '1% above the floor');
select is(public.subscription_amount(333333), 3333::bigint, '1% rounds down to the cent');
select is(public.subscription_amount(600000), 6000::bigint, 'reaches the cap at 6,000.00 of income');
select is(public.subscription_amount(10000000), 6000::bigint, 'capped at 60.00 however high the income');

-- A future formula doesn't apply yet, but can be asked for by version.
insert into public.subscription_formulas values (2, 200000, 150, 9000, 8000, current_date + 30);
select is(public.subscription_amount(300000), 3000::bigint, 'a formula not yet effective is not used');
select is(public.subscription_amount(300000, 2), 4500::bigint, 'an explicit version prices with that version');
select is(public.subscription_amount(190000, 2), 0::bigint, 'each version has its own floor');

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select is(public.subscription_amount(300000), 3000::bigint, 'anon can price a subscription (the calculator)');
reset role;

-- --- allocation preferences ---------------------------------------------------------
select pg_temp.member('00000000-0000-0000-0007-0000000000a1');
select pg_temp.member('00000000-0000-0000-0007-0000000000a2');
select pg_temp.member('00000000-0000-0000-0007-0000000000a3');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0007-0000000000a1');
select lives_ok(
  $$insert into public.allocation_preferences (member_id, target, weight_pct) values
      ('00000000-0000-0000-0007-0000000000a1', 'car_damage', 60),
      ('00000000-0000-0000-0007-0000000000a1', 'highest_score', 40);
    set constraints all immediate$$,
  'preferences totalling 100 are accepted');
-- A successful `set constraints all immediate` sticks; restore commit-time checks.
set constraints all deferred;
select throws_ok(
  $$delete from public.allocation_preferences
    where member_id = '00000000-0000-0000-0007-0000000000a1' and target = 'highest_score';
    set constraints all immediate$$,
  '23514', 'allocation weights must add up to 100 (got 60)', 'removing one leaves a total that isn''t 100');
select lives_ok(
  $$update public.allocation_preferences set weight_pct = 50 where member_id = '00000000-0000-0000-0007-0000000000a1';
    set constraints all immediate$$,
  'rebalancing to 50/50 is accepted');
set constraints all deferred;
select throws_ok(
  $$insert into public.allocation_preferences (member_id, target, weight_pct) values
      ('00000000-0000-0000-0007-0000000000a1', 'home_help', 10);
    set constraints all immediate$$,
  '23514', 'allocation weights must add up to 100 (got 110)', 'a total over 100 is refused');
select throws_ok(
  $$insert into public.allocation_preferences (member_id, target, weight_pct) values
      ('00000000-0000-0000-0007-0000000000a2', 'car_damage', 100)$$,
  '42501', 'new row violates row-level security policy for table "allocation_preferences"',
  'a member cannot set another member''s preferences');

select pg_temp.login('00000000-0000-0000-0007-0000000000a2');
select throws_ok(
  $$insert into public.allocation_preferences (member_id, target, weight_pct) values
      ('00000000-0000-0000-0007-0000000000a2', 'car_damage', 50),
      ('00000000-0000-0000-0007-0000000000a2', 'home_help', 40);
    set constraints all immediate$$,
  '23514', 'allocation weights must add up to 100 (got 90)', 'a total under 100 is refused');
select is((select count(*) from public.allocation_preferences), 0::bigint,
  'a member sees only their own preferences');

-- --- one active subscription --------------------------------------------------------
reset role;
select pg_temp.cover('00000000-0000-0000-0007-0000000000a3');
select throws_ok(
  $$insert into public.subscriptions (member_id, formula_version, income_verification_id, monthly_cents)
    select member_id, 1, income_verification_id, 4000 from public.subscriptions
    where member_id = '00000000-0000-0000-0007-0000000000a3'$$,
  '23505', null, 'a member cannot hold two active subscriptions');
update public.subscriptions set ends_on = current_date where member_id = '00000000-0000-0000-0007-0000000000a3';
select lives_ok(
  $$insert into public.subscriptions (member_id, formula_version, income_verification_id, monthly_cents)
    select member_id, 1, income_verification_id, 3000 from public.subscriptions
    where member_id = '00000000-0000-0000-0007-0000000000a3'$$,
  'after the old one ends, a new subscription can start');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0007-0000000000a3');
select throws_ok(
  $$insert into public.subscriptions (member_id, formula_version, income_verification_id, monthly_cents)
    select member_id, 1, income_verification_id, 0 from public.subscriptions limit 1$$,
  '42501', 'permission denied for table subscriptions', 'a member cannot write their own subscription (price)');

reset role;
select * from finish();
rollback;
