-- The dues formula's $15 cliff (followup): v1 charges 1% of ALL take-home
-- once income reaches the $1,500 floor, so a member at $1,499 pays $0 and at
-- $1,500 pays $15 — a $1 raise can cost $15, which reads as a penalty.
--
-- Version 2 charges 1% of the amount ABOVE the floor (marginal). It gets its
-- own row in `subscription_formulas` with a `marginal` flag the function
-- honours, and an effective date still ahead: switching over is the
-- actuarial review's decision (design.md keeps the figures pending review),
-- so today's dues stay v1 and nothing a member is charged changes silently.

alter table public.subscription_formulas
  add column marginal boolean not null default false;

-- v1 keeps its meaning; v2 is the marginal formula, live from 2027-01-01
-- (the actuarial review's switch, not ours).
insert into public.subscription_formulas (version, floor_income_cents, rate_bps,
                                          cap_cents, core_share_bps, effective_from, marginal)
values (2, 150000, 100, 6000, 8000, '2027-01-01', true);

-- CREATE OR REPLACE keeps the existing grants (authenticated and anon read
-- it; it's a pure figure) and the member's subscription keeps pointing at
-- whichever version was effective when it started.
create or replace function public.subscription_amount(p_monthly_income_cents bigint, p_version integer default null)
returns bigint language sql stable set search_path = '' as $$
  select case
    when p_monthly_income_cents < f.floor_income_cents then 0
    -- Marginal: only the money above the floor is charged.
    else least(f.cap_cents,
               ((p_monthly_income_cents - case when f.marginal then f.floor_income_cents else 0 end)
                * f.rate_bps) / 10000)
  end
  from public.subscription_formulas f
  where f.version = coalesce(
    p_version,
    (select max(version) from public.subscription_formulas where effective_from <= current_date)
  );
$$;
