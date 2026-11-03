-- Captured charges get a journalled path (20261102570000_charge_journal.sql).
--
-- Properties this file pins:
--   * the partner's charge confirmation captures the pledges AND journals their
--     money in one transaction: out of the partner's side and into the fund's
--     `available` account, the account the pool allocates from;
--   * the figure journaled is the schema's own pledged sum, so both sides of
--     the ledger move together and a replayed confirmation has nothing left to
--     capture;
--   * members get nothing, a confirmation without the partner's reference is
--     refused, and an unknown request is refused.
begin;
select plan(10);

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

create function pg_temp.member(p_id uuid) returns void language sql as $$
  insert into public.members (id, display_name, region, status)
    values (p_id, 'Test member', 'CA', 'active');
$$;

create function pg_temp.request(p_id uuid, p_member uuid, p_amount bigint) returns void language sql as $$
  insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on)
    values (p_id, p_member, 'car_damage', 'people', 'Charge test', p_amount, current_date - 5);
$$;

-- --- the fixtures -------------------------------------------------------------

set local role service_role;
select pg_temp.as_service();
select pg_temp.member('00000000-0000-0000-0009-0000000000a1');
select pg_temp.request('00000000-0000-0000-0009-0000000000b1', '00000000-0000-0000-0009-0000000000a1', 100000);
update public.requests set status = 'scoring' where id = '00000000-0000-0000-0009-0000000000b1';
update public.requests set status = 'open' where id = '00000000-0000-0000-0009-0000000000b1';
update public.requests set status = 'funded' where id = '00000000-0000-0000-0009-0000000000b1';
insert into public.contributions (request_id, contributor_id, source, amount_cents, status)
  values ('00000000-0000-0000-0009-0000000000b1', '00000000-0000-0000-0009-0000000000a1', 'gift', 30000, 'pledged'),
         ('00000000-0000-0000-0009-0000000000b1', '00000000-0000-0000-0009-0000000000a1', 'gift', 25000, 'pledged');

-- --- money arrives only with the partner's confirmation -----------------------

select is(public.ledger_balance('protection'::public.fund, 'available'), 0::bigint,
  'the pool''s account is empty before the partner confirms anything');
select is(public.ledger_balance('protection'::public.fund, 'partner_cash'), 0::bigint,
  'nothing had reached the partner''s side either');

set local role anon;
select throws_ok($$select public.record_charge_confirmation('00000000-0000-0000-0009-0000000000b1', 'pi_1')$$,
  '42501', 'permission denied for function record_charge_confirmation',
  'members cannot confirm charges');

set local role service_role;
select pg_temp.as_service();
select is(public.record_charge_confirmation('00000000-0000-0000-0009-0000000000b1', 'pi_1'), 55000::bigint,
  'the confirmation answers with the pledged money the schema captured');
select is(public.ledger_balance('protection'::public.fund, 'available'), 55000::bigint,
  'the captured money reaches the account the pool allocates from');
select is(public.ledger_balance('protection'::public.fund, 'partner_cash'), -55000::bigint,
  'and the journal records the side it left, so it balances');
select is((select count(*) from public.contributions
           where request_id = '00000000-0000-0000-0009-0000000000b1' and status = 'pledged'), 0::int,
  'every pledge on the request is captured');

-- --- a replayed confirmation has nothing to capture ---------------------------

select throws_ok($$select public.record_charge_confirmation('00000000-0000-0000-0009-0000000000b1', 'pi_2')$$,
  '23514', 'a charge confirmation captures money',
  'a replayed confirmation journals nothing a second time');
select throws_ok($$select public.record_charge_confirmation('00000000-0000-0000-0009-0000000000b1', '')$$,
  '23514', 'a charge confirmation needs the partner''s reference',
  'a confirmation the ledger can be replayed against is refused');
select throws_ok($$select public.record_charge_confirmation('00000000-0000-0000-0009-0000000000b9', 'pi_1')$$,
  'P0002', 'request not found',
  'a confirmation of a request that is not there is refused');

rollback;