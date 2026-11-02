-- The insurer's feed confirms a recorded claim was paid in full (less the
-- member's share, which is already stored on the row as the gap to the shop):
-- `mark_claim_paid` is the service's closing step, idempotent by the partner
-- reference of the payment event. The webhook journals the money the feed
-- says moved; this function only states the outcome on the row, and it is
-- refused for claims that were denied — no money moves on a denial.

create function public.mark_claim_paid(p_claim uuid, p_partner_ref text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_service() then
    raise exception 'claim payments are confirmed by the service' using errcode = '42501';
  end if;
  if p_partner_ref is null or p_partner_ref = '' then
    raise exception 'a claim payment needs the partner''s reference' using errcode = '23514';
  end if;
  if not exists (select 1 from public.claims where id = p_claim) then
    raise exception 'claim not found' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.claims where id = p_claim and status = 'paid') then
    return; -- a replayed confirmation changes nothing, and says nothing more
  end if;
  update public.claims set status = 'paid'
  where id = p_claim and status = 'recorded';
  if not exists (select 1 from public.claims where id = p_claim and status = 'paid') then
    raise exception 'a denied claim pays nothing' using errcode = '23514';
  end if;
  perform private.audit('claim.paid', 'claims', p_claim,
                        jsonb_build_object('partner_ref', p_partner_ref));
end $$;

-- New relation: claim ownership, service only.
revoke all from function public.mark_claim_paid(uuid, text);
revoke all from function public.mark_claim_paid(uuid, text) to public, anon, authenticated;
grant execute on function public.mark_claim_paid(uuid, text) to service_role;
