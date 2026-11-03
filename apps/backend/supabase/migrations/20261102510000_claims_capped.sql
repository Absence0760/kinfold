-- Claims are capped by the filed terms and by the vehicle itself (roadmap 2b/2c):
-- an insured claim can never exceed the filed deductible cap for the member's
-- plan and the vehicle's rating-law class, nor the vehicle's own value. A feed
-- entry that ignores the caps is refused loudly — it is not silently truncated
-- — so the books can never show a claim the filed terms would not pay.
drop function public.record_claim(uuid, text, bigint, bigint);

create function public.record_claim(
  p_request uuid, p_partner_ref text, p_gross_cents bigint, p_member_share_cents bigint
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id     uuid;
  v_limit  bigint;
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
  -- The cap: the filed cap for the member's plan and the vehicle's class,
  -- and the vehicle's own value. A request with no classed covered asset
  -- (a home, a down payment) carries no car cap.
  select least(
    (select cap_cents from public.cover_plans
     where vehicle_class = (select vehicle_class from public.covered_assets a
                            where a.id = (select asset_id from public.requests r where r.id = p_request))
       and plan = public.member_plan((select member_id from public.requests r where r.id = p_request))),
    (select value_cents from public.covered_assets a
     where a.id = (select asset_id from public.requests r where r.id = p_request))
  ) into v_limit;
  if v_limit is not null and p_gross_cents > v_limit then
    raise exception 'a claim cannot exceed the filed cap for the member''s plan, or the vehicle''s value'
      using errcode = '23514';
  end if;
  insert into public.claims (request_id, partner_ref, gross_cents, member_share_cents)
  values (p_request, p_partner_ref, p_gross_cents, p_member_share_cents)
  returning id into v_id;
  perform private.audit('claim.recorded', 'claims', v_id,
                        jsonb_build_object('partner_ref', p_partner_ref, 'request_id', p_request,
                                           'cap_cents', coalesce(v_limit, 0)));
  return v_id;
end $$;

grant execute on function public.record_claim(uuid, text, bigint, bigint) to service_role;
