-- Dues formula v2, marginal (20261102250000_dues_marginal.sql).
--
-- Properties this file pins:
--   * v1's cliff stays where it was and v1 stays the live formula today:
--     the switch is dated 2027-01-01, so nobody's dues change silently;
--   * v2 charges 1% of the amount ABOVE the floor: income at the floor costs
--     $0 (no jump), and a cent more income costs at most a cent more dues;
--   * v2 still pays $0 below the floor and caps at $60 like v1.
begin;
select plan(10);

-- --- v1 keeps its meaning, and stays live today -------------------------------

select is(public.subscription_amount(150000, 1), 1500::bigint, 'v1 still jumps in at the floor');
select is(public.subscription_amount(149999, 1), 0::bigint, 'v1 is $0 just below the floor');
select is(public.subscription_amount(150000), 1500::bigint,
  'the live formula is still v1: v2 is only effective from 2027-01-01');

-- --- v2 is marginal: the floor is subtracted ----------------------------------

select is(public.subscription_amount(149999, 2), 0::bigint, 'v2 is $0 below the floor');
select is(public.subscription_amount(150000, 2), 0::bigint, 'v2 at the floor costs $0: no jump');
select is(public.subscription_amount(155000, 2), 50::bigint, 'v2 charges 1% of the 50 dollars above the floor');
select is(public.subscription_amount(750000, 2), 6000::bigint, 'v2 reaches the $60 cap $10,000 above the floor');
select is(public.subscription_amount(10000000, 2), 6000::bigint, 'v2 caps like v1 however high the income');

-- --- more income never costs much more dues -----------------------------------

select is(public.subscription_amount(150001, 2), 0::bigint,
  'a cent more income costs no more dues at all');
select is(public.subscription_amount(600000, 2) <= public.subscription_amount(600001, 2),
  true, 'more income never lowers dues');
