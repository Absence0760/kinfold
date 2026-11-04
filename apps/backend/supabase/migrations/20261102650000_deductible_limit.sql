-- The $1,000 limit on deductible cover (design.md "What it funds": insured
-- deductible cover pays "the member's deductible, up to $1,000"; roadmap 2i
-- states the same yearly figure). The annual deductible is the partner insurer's
-- filed term, but a filed number cannot be allowed to promise MORE cover than
-- the product offers: an annual above $1,000 would credit deductible dollars
-- back to one insured member-year that the group program was never priced or
-- filed for, and the feed's deductible-cover floor would then hand out cover
-- beyond the program's own limit. So the limit is a table check (a filed number
-- cannot slip past it) AND a refusal in the filing door with the reason, and
-- the seeded stand-ins are refilled to fit — a filed-term change trails a
-- history row per rate, like every other rate change.

-- Refile the stand-ins first: the annual is two claims' worth of that class's
-- per-claim cap, never more than the year's limit.
update public.cover_plans
  set annual_deductible_cents = least(cap_cents * 2, 100000);

-- The limit itself, on the column, so nothing can write past it.
alter table public.cover_plans
  add constraint annual_deductible_capped check (annual_deductible_cents is null
                                                 or annual_deductible_cents <= 100000);

-- The filing door says so too, before the update, so the partner hears the
-- reason rather than a constraint's own wording.
create or replace function public.set_annual_deductible(p_class public.vehicle_class,
  p_plan public.cover_plan, p_annual bigint, p_filed_by text,
  p_filed_on date) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_service() then
    raise exception 'filed annual deductibles are written by the service' using errcode = '42501';
  end if;
  if p_annual <= 0 then
    raise exception 'a filed annual deductible must be positive' using errcode = '23514';
  end if;
  if p_annual > 100000 then
    raise exception 'the deductible dollars one member may get back in a year are capped at 1000 dollars; a filed annual above that overstates the cover' using errcode = '23514';
  end if;
  update public.cover_plans set annual_deductible_cents = p_annual,
      filed_by = p_filed_by, filed_on = p_filed_on
  where vehicle_class = p_class and plan = p_plan;
  if not found then
    raise exception 'the filed rate row for that class and plan is not there yet' using errcode = 'P0002';
  end if;
  perform private.audit('cover_plans.annual_filed', 'cover_plans', NULL,
    jsonb_build_object('vehicle_class', p_class, 'plan', p_plan,
                       'annual_deductible_cents', p_annual));
end $$;

revoke all on function public.set_annual_deductible(public.vehicle_class, public.cover_plan, bigint, text, date) from public, anon, authenticated;
grant execute on function public.set_annual_deductible(public.vehicle_class, public.cover_plan, bigint, text, date)
  to service_role;
