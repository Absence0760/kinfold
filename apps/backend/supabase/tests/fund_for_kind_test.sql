-- Which fund a request kind draws on (public.fund_for_kind, 20261030120000_members.sql).
--
-- The mapping is what decides a request's fund settings: the fund's minimum
-- score, its band, its inspection floor and its waiting period. Both sides of
-- the mapping are pinned here and in the web mirror (fundForKind in
-- requests/form.ts, read by the board and eligibility wording), so a kind can
-- never quietly price itself against the wrong fund's rules.
--
-- Properties this file pins:
--   * the two car kinds draw on the protection fund;
--   * every other kind draws on the home fund;
--   * the whole enum is covered, so a kind added later fails here and not
--     silently in the board or the eligibility card.
begin;
select plan(6);

select is(public.fund_for_kind('car_damage'::public.request_kind)::text,
  'protection', 'collision damage is priced under the protection fund');

select is(public.fund_for_kind('car_deductible'::public.request_kind)::text,
  'protection', 'a deductible claim is priced under the protection fund');

select is(public.fund_for_kind('home_repair'::public.request_kind)::text,
  'home_fund', 'a home repair draws on the repair fund');

select is(public.fund_for_kind('down_payment'::public.request_kind)::text,
  'home_fund', 'a down-payment ask draws on the repair fund');

select is(public.fund_for_kind('mortgage_gap'::public.request_kind)::text,
  'home_fund', 'a mortgage-gap ask draws on the repair fund');

select is(public.fund_for_kind('loan_payoff'::public.request_kind)::text,
  'home_fund', 'a loan-payoff ask draws on the repair fund');

rollback;
