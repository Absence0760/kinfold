-- Ledger balances (20261102280000_ledger_balance.sql).
--
-- Properties this file pins:
--   * the service can read a fund-level account's balance, and it follows the
--     journals: each two-line journal moves money between accounts of ONE
--     fund;
--   * an account nothing has moved through reads $0;
--   * a member can't read balances at all.
begin;
select plan(7);

-- Ledger figures are read as what this file moved: the seed's own journals are
-- already on the books (dues, premiums, payouts, pool grants), and a balance
-- read whole would count them too. The baseline is every account's balance
-- before this file posts anything.
create temp table seed_ledger on commit drop as
  select a.fund, a.code, public.ledger_balance(a.fund, a.code) as cents
  from (select distinct fund, code from private.ledger_accounts) a;
grant select on seed_ledger to public;
create function pg_temp.moved(p_fund public.fund, p_code text) returns bigint language sql as $$
  select public.ledger_balance(p_fund, p_code)
       - coalesce((select cents from pg_temp.seed_ledger where fund = p_fund and code = p_code), 0)
$$;

-- --- fixtures ------------------------------------------------------------------

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

-- --- journals move balances -----------------------------------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.post_journal('protection', 'subscription', null, 'pi_lb_1',
  '[{"code":"partner_cash","amount_cents":-800},{"code":"available","amount_cents":800}]')$$,
  'the service posts a subscription journal');
select is(pg_temp.moved('protection', 'partner_cash'),
  -800::bigint, 'the partner''s cash account owes what the journal moved');
select is(pg_temp.moved('protection', 'available'),
  800::bigint, 'the fund''s own money account gained the same figure');
select lives_ok($$select public.post_journal('protection', 'gift', null, 'pi_lb_2',
  '[{"code":"available","amount_cents":-500},{"code":"committed","amount_cents":500}]')$$,
  'a second journal moves money onward inside the fund');
select is(pg_temp.moved('protection', 'available'),
  300::bigint, 'the account netted both journals');
select is(pg_temp.moved('protection', 'reserve'),
  0::bigint, 'an untouched account reads $0');

select ok(not has_function_privilege('authenticated', 'public.ledger_balance(public.fund, text)',
  'execute') and has_function_privilege('service_role', 'public.ledger_balance(public.fund, text)',
  'execute'), 'only the service reads balances; members never see the books');
