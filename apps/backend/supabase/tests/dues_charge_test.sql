-- Dues collection (20261102340000_dues_collection.sql).
--
-- Properties this file pins:
--   * the service asks a member's dues for a month at the member's own
--     figure, and a $0 subscription has nothing to collect;
--   * the ask is idempotent per member per period (a replayed cron month
--     returns the payment it already made);
--   * capturing answers with the stored figure, marks it captured, and a
--     replay keeps the figure;
--   * a period that isn't a month start is refused; members can't collect.
begin;
select plan(9);

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

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

-- A member with an income check and an active subscription at $40.00 a month.
create function pg_temp.subscribe(p_member uuid, p_monthly bigint)
returns void language sql as $$
  with iv as (
    insert into public.income_verifications (member_id, method, monthly_income_cents)
    values (p_member, 'bank_link', 400000) returning id
  ), sub as (
    insert into public.subscriptions (member_id, formula_version, income_verification_id, monthly_cents, starts_on)
    select p_member, 1, iv.id, p_monthly, (now() - interval '60 days')::date from iv returning id
  ) select;
$$;

select pg_temp.member('00000000-0000-0000-0016-0000000000a1');
select pg_temp.member('00000000-0000-0000-0016-0000000000a2');
select pg_temp.subscribe('00000000-0000-0000-0016-0000000000a1', 4000::bigint);
select pg_temp.subscribe('00000000-0000-0000-0016-0000000000a2', 0::bigint);

-- --- the service asks dues for the month -------------------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.enqueue_dues('00000000-0000-0000-0016-0000000000a1',
  (date_trunc('month', now() - interval '20 days'))::date)$$,
  'the service asks the member''s dues for the month');
select is((select amount_cents from public.subscription_payments
           where member_id = '00000000-0000-0000-0016-0000000000a1'
             and period = (date_trunc('month', now() - interval '20 days'))::date),
  4000::bigint, 'the dues ask carries the member''s own figure');
select is(public.enqueue_dues('00000000-0000-0000-0016-0000000000a1',
                              (date_trunc('month', now() - interval '20 days'))::date),
  (select id from public.subscription_payments
     where member_id = '00000000-0000-0000-0016-0000000000a1'),
  'the same month replayed returns the payment it already made');
select is((select count(*) from public.subscription_payments
           where member_id = '00000000-0000-0000-0016-0000000000a1'),
  1::bigint, 'the replay added no second ask');

-- --- captures answer with the figure ----------------------------------------

select is(public.capture_dues((select id from public.subscription_payments
        where member_id = '00000000-0000-0000-0016-0000000000a1'), 'dues_p1'),
  4000::bigint, 'the capture answers with the figure the schema stored');
select is((select status from public.subscription_payments
           where member_id = '00000000-0000-0000-0016-0000000000a1'),
  'captured'::public.payment_status, 'the confirmed dues period is marked captured');
select is(public.capture_dues((select id from public.subscription_payments
        where member_id = '00000000-0000-0000-0016-0000000000a1'), 'dues_p1'),
  4000::bigint, 'a replayed capture answers with the stored figure');

-- --- refusals ------------------------------------------------------------------

select throws_ok($$select public.enqueue_dues('00000000-0000-0000-0016-0000000000a2',
  (date_trunc('month', now()))::date)$$,
  '23514', 'a $0 dues subscription has nothing to collect',
  'a $0 subscription has no dues to ask for');
select throws_ok($$select public.enqueue_dues('00000000-0000-0000-0016-0000000000a1',
  (now() - interval '10 days')::date)$$,
  '23514', 'a dues period must start on the first of a month',
  'a dues period must start on the first of a month');
