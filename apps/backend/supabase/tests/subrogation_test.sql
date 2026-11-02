-- Subrogation: the partner insurer's claim money (20261102390000_subrogation.sql).
--
-- Properties this file pins:
--   * the service records a partner recovery ALREADY verified, in one step;
--   * a webhook retry with the same partner reference is a no-op, never a
--     second row (money can't be counted twice against the same damage);
--   * an empty reference or a non-positive amount is refused; an unknown
--     request is refused;
--   * members cannot call this at all: this money moved between insurers.
begin;
select plan(9);

-- --- fixtures ------------------------------------------------------------------

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

create function pg_temp.member(p_id uuid) returns uuid language sql as $$
  insert into public.members (id, handle, display_name, region, status, joined_via, created_at)
  values (p_id, 'm' || right(p_id::text, 6), 'Test', 'CA', 'active', 'invite', now())
  returning id;
$$;

create function pg_temp.request(p_id uuid, p_member uuid) returns uuid language sql as $$
  insert into public.requests (id, member_id, kind, funding, title, amount_cents,
                               incident_on, status, created_at)
  values (p_id, p_member, 'car_damage', 'people', 'Test request', 100000,
          current_date - 5, 'open', now())
  returning id;
$$;

-- Fixtures are created once with literal ids so the later calls can reuse them.
select pg_temp.member('00000000-0000-0000-0015-0000000000a1'::uuid);
select pg_temp.request('00000000-0000-0000-0015-000000000001'::uuid,
  '00000000-0000-0000-0015-0000000000a1'::uuid);

-- --- the partner's money lands verified ----------------------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.record_partner_recovery('00000000-0000-0000-0015-000000000001'::uuid,
  'insurance', 30000::bigint, current_date - 5::date, 'pi_sub_1')$$,
  'the service records the partner insurer''s claim money');
select is((select count(*) from public.request_recoveries), 1::int, 'the recovery landed once');
select is((select partner_ref from public.request_recoveries limit 1), 'pi_sub_1',
  'the partner''s reference is stored, so the money is traceable');

-- --- a retried webhook adds nothing --------------------------------------------

select lives_ok($$select public.record_partner_recovery('00000000-0000-0000-0015-000000000001'::uuid,
  'insurance', 30000::bigint, current_date - 5::date, 'pi_sub_1')$$,
  'the same partner reference is a no-op');
select is((select count(*) from public.request_recoveries), 1::int,
  'the retry stored no second row');

-- --- refusals --------------------------------------------------------------------

select throws_ok($$select public.record_partner_recovery('00000000-0000-0000-0015-000000000001'::uuid,
  'insurance', 30000::bigint, current_date - 5::date, '')$$, '23514',
  'partner money with no reference is refused');
select throws_ok($$select public.record_partner_recovery('00000000-0000-0000-0015-000000000001'::uuid,
  'insurance', 0::bigint, current_date - 5::date, 'pi_sub_2')$$, '23514',
  'a non-positive amount is refused');
select throws_ok($$select public.record_partner_recovery('00000000-0000-0000-0015-000000000000'::uuid,
  'insurance', 30000::bigint, current_date - 5::date, 'pi_sub_3')$$, 'P0002',
  'an unknown request is refused');

select ok(has_function_privilege('service_role',
    'record_partner_recovery(uuid, public.recovery_source, bigint, date, text, text)', 'execute')
    and not has_function_privilege('authenticated',
    'record_partner_recovery(uuid, public.recovery_source, bigint, date, text, text)', 'execute'),
  'only the service records partner money; members never claim between insurers');

rollback;
