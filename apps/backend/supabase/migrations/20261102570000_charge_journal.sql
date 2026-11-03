-- Captured charges get a journalled path of their own (followups item 19:
-- gifts had none). Money the payment partner confirms for a funded request is
-- money the cooperative put in motion — a member's gift pledge or a pool grant,
-- paid to a verified payee — and it arrives from the partner's side into the
-- fund's `available` account, which is exactly the account the pool allocates
-- from and payouts pay out of. The repair fund is gift-funded (design.md: banded
-- allocation applies only to the gift-funded repair fund, which promises nothing),
-- so this is how its money actually arrives. One door does the capture and the
-- journal in one transaction, so money is never captured without its ledger
-- entry; the figure journaled is the schema's own sum, never the partner's word.

create function public.record_charge_confirmation(p_request uuid, p_partner_ref text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_fund   public.fund;
  v_amount bigint;
begin
  if not private.is_service() then
    raise exception 'charge confirmations come in from the service' using errcode = '42501';
  end if;
  if p_partner_ref is null or p_partner_ref = '' then
    raise exception 'a charge confirmation needs the partner''s reference' using errcode = '23514';
  end if;
  select fund_for_kind(r.kind) into v_fund from public.requests where id = p_request;
  if v_fund is null then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  -- The figure is the schema's own: what stands pledged on the request now.
  select coalesce(sum(c.amount_cents), 0) from public.contributions
    where request_id = p_request and status = 'pledged' into v_amount;
  if v_amount = 0 then
    raise exception 'a charge confirmation captures money' using errcode = '23514';
  end if;
  -- capture_contributions owns the rules: a funded request, and every loan
  -- behind it signed by both sides before money is captured.
  perform public.capture_contributions(p_request);
  perform private.post_journal(v_fund, 'charges', p_request, p_partner_ref,
    jsonb_build_array(jsonb_build_object('code', 'partner_cash', 'amount_cents', -v_amount),
                      jsonb_build_object('code', 'available', 'amount_cents', v_amount)));
  perform private.audit('charges.journaled', 'requests', p_request,
    jsonb_build_object('amount_cents', v_amount, 'partner_ref', p_partner_ref));
  return v_amount;
end $$;

-- --- access --------------------------------------------------------------------

-- New function: hardening.sql revokes all public functions from the client
-- roles; this door is service-only, like every money-moving door.
revoke all from function public.record_charge_confirmation(uuid, text);
revoke all from function public.record_charge_confirmation(uuid, text) to public, anon, authenticated;
grant execute on function public.record_charge_confirmation(uuid, text) to service_role;