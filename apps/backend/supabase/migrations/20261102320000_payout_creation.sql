-- Opening a payout had no door: inserts into `public.payouts` are service
-- exclusive (RLS, no insert policy), so the console — and the payments
-- webhook's payout-created event — had nothing to call. `create_payout`
-- is that door: service only, keyed by the partner payout reference so a
-- replayed event is a no-op that answers with the payout it already made.
-- A payout row starts `pending` — money only moves when it's `sent`, and
-- `report_payout` owns the rest of the steps. Everything else stays with
-- guard_payout: funded request, the named verified payee, the final
-- invoice on this request, and the captured-contributions ceiling.

create function public.create_payout(
  p_request uuid, p_payee uuid, p_amount_cents bigint,
  p_invoice_evidence uuid, p_partner_ref text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not private.is_service() then
    raise exception 'payouts are opened by the service' using errcode = '42501';
  end if;
  if p_partner_ref is null or p_partner_ref = '' then
    raise exception 'a payout needs the partner''s payout reference' using errcode = '23514';
  end if;
  -- A replayed event is a no-op: the reference is unique.
  if exists (select 1 from public.payouts where partner_ref = p_partner_ref) then
    return (select id from public.payouts where partner_ref = p_partner_ref);
  end if;
  insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id, partner_ref)
  values (p_request, p_payee, p_amount_cents, p_invoice_evidence, p_partner_ref)
  returning id into v_id;
  return v_id;
end $$;

-- New relation: claim ownership, service only.
revoke all from function public.create_payout(uuid, uuid, bigint, uuid, text);
revoke all from function public.create_payout(uuid, uuid, bigint, uuid, text) to public, anon, authenticated;
grant execute on function public.create_payout(uuid, uuid, bigint, uuid, text) to service_role;
