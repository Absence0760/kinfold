-- The annual deductible (followups: "a yearly per-member cap" and "a member
-- share rising with claims"). Rating law caps the deductible dollars ONE
-- insured member may get back in an insurance year: claims pay in full only
-- up to that year's deductible, and once its dollars run out the member's
-- share of the next claim rises to the whole loss — frequent claimants pay
-- more of their own repair (design.md: the same way a deductible works); a
-- claim is never refused for it and the member never waits longer. The feed
-- carries the partner's gross figure; the floor on the member's share is
-- computed here from the filed annual deductible, so the books can never
-- credit deductible dollars beyond what the filed terms would pay. Like
-- every other number on this table, the seeded annuals are local stand-ins.

alter table public.cover_plans
  add annual_deductible_cents bigint
  add constraint annual_deductible_positive check (annual_deductible_cents is null
                                                   or annual_deductible_cents > 0);

-- The seeded stand-ins file their annual deductible: three claims' worth of
-- that class and plan's per-claim cap (a history row trails the filed change).
update public.cover_plans
  set annual_deductible_cents = cap_cents * 3;

-- The annual deductible is a filed term, so the partner files it through the
-- service; the rate row must already exist, since the annual sits beside its
-- premium and cap.
create function public.set_annual_deductible(p_class public.vehicle_class,
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

revoke all from function public.set_annual_deductible(public.vehicle_class, public.cover_plan, bigint, text, date);
revoke all from function public.set_annual_deductible(public.vehicle_class, public.cover_plan, bigint, text, date)
  to public, anon, authenticated;
grant execute on function public.set_annual_deductible(public.vehicle_class, public.cover_plan, bigint, text, date)
  to service_role;

-- The current feed door gains two things: the annual deductible floor (above),
-- and it now WRITES paid_cents on the row — the previous door left that column
-- unset, which would have failed the NOT NULL at insert time (the pgTAP suites
-- run only in CI, so it was caught here before it ever ran).
drop function public.record_claim(uuid, text, bigint, bigint);

create function public.record_claim(
  p_request uuid, p_partner_ref text, p_gross_cents bigint, p_member_share_cents bigint
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id       uuid;
  v_limit    bigint;
  v_member   uuid;
  v_annual   bigint;
  v_used     bigint;
begin
  if not private.is_service() then
    raise exception 'claims are recorded by the partner''s feed, in the service' using errcode = '42501';
  end if;
  if not exists (select 1 from public.requests where id = p_request) then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if p_partner_ref is null or p_partner_ref = '' then
    raise exception 'a claim needs the partner''s reference' using errcode = '23514';
  end if;
  -- A replayed feed entry is a no-op: the reference is unique.
  if exists (select 1 from public.claims where partner_ref = p_partner_ref) then
    return (select id from public.claims where partner_ref = p_partner_ref);
  end if;
  v_member := (select member_id from public.requests r where r.id = p_request);
  -- The per-claim cap: the filed cap for the member's plan and the vehicle's
  -- class, and the vehicle's own value. A request with no classed covered
  -- asset (a home, a down payment) carries no car cap.
  select least(
    (select cap_cents from public.cover_plans
       where vehicle_class = (select vehicle_class from public.covered_assets a
                              where a.id = (select asset_id from public.requests r where r.id = p_request))
         and plan = public.member_plan(v_member)),
    (select value_cents from public.covered_assets a
       where a.id = (select asset_id from public.requests r where r.id = p_request))
  ) into v_limit;
  if v_limit is not null and p_gross_cents > v_limit then
    raise exception 'a claim cannot exceed the filed cap for the member''s plan, or the vehicle''s value'
      using errcode = '23514';
  end if;
  -- The annual deductible floor: deductible dollars this member has already
  -- PAID back this insurance year (calendar year; a denial pays nothing so it
  -- uses none, and a claim the feed hasn't confirmed as paid yet has recovered
  -- nothing), and what the filed annual has left. The member's share must
  -- cover everything the filed annual has left unpaid.
  select (select annual_deductible_cents from public.cover_plans
          where vehicle_class = (select vehicle_class from public.covered_assets a
                                 where a.id = (select asset_id from public.requests r where r.id = p_request))
            and plan = public.member_plan(v_member)) into v_annual;
  if v_annual is not null then
    v_used := coalesce((select sum(c.paid_cents)
                        from public.claims c
                        where c.status = 'paid'
                          and extract(year from c.recorded_at) = extract(year from current_date)
                          and exists (select 1 from public.requests r
                                      where r.id = c.request_id and r.member_id = v_member)), 0::bigint);
    if p_member_share_cents < greatest(0, p_gross_cents - greatest(0, v_annual - v_used)) then
      raise exception 'a member cannot take deductible cover beyond the annual deductible; the share rises with claims'
        using errcode = '23514';
    end if;
  end if;
  insert into public.claims (request_id, partner_ref, gross_cents, member_share_cents,
                             paid_cents)
  values (p_request, p_partner_ref, p_gross_cents, p_member_share_cents,
          p_gross_cents - p_member_share_cents)
  returning id into v_id;
  perform private.audit('claim.recorded', 'claims', v_id,
                        jsonb_build_object('partner_ref', p_partner_ref, 'request_id', p_request,
                                           'cap_cents', coalesce(v_limit, 0)));
  return v_id;
end $$;

grant execute on function public.record_claim(uuid, text, bigint, bigint) to service_role;
