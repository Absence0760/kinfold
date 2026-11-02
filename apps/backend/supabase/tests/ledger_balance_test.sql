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
select is(public.ledger_balance('protection', 'partner_cash'),
  -800::bigint, 'the partner''s cash account owes what the journal moved');
select is(public.ledger_balance('protection', 'available'),
  800::bigint, 'the fund''s own money account gained the same figure');
select lives_ok($$select public.post_journal('protection', 'gift', null, 'pi_lb_2',
  '[{"code":"available","amount_cents":-500},{"code":"committed","amount_cents":500}]')$$,
  'a second journal moves money onward inside the fund');
select is(public.ledger_balance('protection', 'available'),
  300::bigint, 'the account netted both journals');
select is(public.ledger_balance('protection', 'reserve'),
  0::bigint, 'an untouched account reads $0');

select ok(not has_function_privilege('authenticated', 'public.ledger_balance(public.fund, text)',
  'execute') and has_function_privilege('service_role', 'public.ledger_balance(public.fund, text)',
  'execute'), 'only the service reads balances; members never see the books');
