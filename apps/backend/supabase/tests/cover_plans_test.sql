-- Cover terms (20261102400000_cover_plans.sql).
--
-- Properties this file pins:
--   * the filed rates read as the class and plan the cooperative pays;
--   * a member with no choice runs Basic; choosing Standard raises the figure;
--   * a member can choose their plan but can never write a filed rate;
--   * within a class a change that prices Standard at or below Basic is refused,
--     leaving the row and its history untouched;
--   * only the service files rates.
begin;
select plan(12);

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

select pg_temp.member('00000000-0000-0000-0018-0000000000a1');
select pg_temp.member('00000000-0000-0000-0018-0000000000a2', 'NY');

-- --- the filed rates and the member's own plan ----------------------------------

select is(public.premium_cents('sedan', 'basic'), 12900::bigint,
  'Basic for a sedan reads the filed figure');
select is(public.member_plan('00000000-0000-0000-0018-0000000000a1'::uuid), 'basic',
  'a member who has not chosen a plan runs Basic');
select is(public.premium_for('00000000-0000-0000-0018-0000000000a1'::uuid, 'sedan'),
  12900::bigint, 'the cooperative pays the Basic premium for their sedan');

-- --- the member may choose their plan, not the insurer's rates ------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0018-0000000000a1'::uuid);
select lives_ok($$select public.set_my_plan('standard')$$, 'the member chooses Standard');
reset role;
select is(public.member_plan('00000000-0000-0000-0018-0000000000a1'::uuid), 'standard',
  'the choice lands as their plan');
select is(public.premium_for('00000000-0000-0000-0018-0000000000a1'::uuid, 'sedan'),
  18900::bigint, 'their sedan now costs the Standard premium');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0018-0000000000a2'::uuid);
select throws_ok($$select public.set_cover_plan('sedan', 'standard', 20000::bigint,
  100000::bigint, 'partner_insurer', current_date)$$, '42501',
  'permission denied for function set_cover_plan');
reset role;

-- --- the plan order inside a class survives a change -----------------------------

-- The stack itself trails filed changes (the seeded annuals trail history rows),
-- so the history counts below are DELTAS against a baseline taken here: the
-- transaction's own refused/lawful changes must move the history by 0 and 1
-- whatever the books already carry.
create table pg_temp.history_base (baseline bigint);
insert into pg_temp.history_base (baseline)
values ((select count(*) from private.cover_plans_history));

set local role service_role;
select pg_temp.as_service();
select throws_ok($$select public.set_cover_plan('sedan', 'standard', 10000::bigint,
  100000::bigint, 'partner_insurer', current_date)$$, '23514',
  'within a class the standard plan must pay more premium for at least as much cap');
select is((select premium_cents from public.cover_plans
           where vehicle_class = 'sedan' and plan = 'standard'), 18900::bigint,
  'the refused change left the row alone');
reset role;
select is((select count(*) from private.cover_plans_history) -
          (select baseline from pg_temp.history_base), 0::bigint,
  'a refused change wrote no history row');
set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.set_cover_plan('sedan', 'basic', 12000::bigint,
  50000::bigint, 'partner_insurer', current_date)$$, 'a lawful Basic change goes through');
reset role;
select is((select count(*) from private.cover_plans_history) -
          (select baseline from pg_temp.history_base), 1::bigint,
  'the lawful change logged exactly one history row');

rollback;
