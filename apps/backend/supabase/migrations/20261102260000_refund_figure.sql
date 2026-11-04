-- The payments webhook journals refunds; the ledger must mirror the SCHEMA's
-- split, not the partner's word (followup: partial refunds). `mark_refunded`
-- used to answer "void", so the webhook could only journal what the partner
-- claimed — money could be journaled wrong against the row it owns. It now
-- returns the figure it stored (`refunded_cents`, computed by `refunds_due`),
-- and the webhook journals exactly that.
--
-- CREATE OR REPLACE also resets the function's grants (they live on the
-- function object), so the grants are re-claimed right below — service only,
-- as hardening_test and service_paths_test demand.

create or replace function public.mark_refunded(p_contribution uuid, p_partner_ref text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_cents bigint;
begin
  if p_partner_ref is null or p_partner_ref = '' then
    raise exception 'a refund needs the partner''s reference' using errcode = '23514';
  end if;
  -- Webhooks retry: the same refund reported twice is a no-op, and it still
  -- answers with the figure already stored.
  if exists (select 1 from public.contributions where id = p_contribution and status = 'refunded'
             and refund_partner_ref = p_partner_ref) then
    return (select refunded_cents from public.contributions where id = p_contribution);
  end if;
  perform 1 from public.contributions where id = p_contribution for update;
  select refund_cents into v_cents from public.refunds_due where contribution_id = p_contribution;
  if v_cents is null then
    raise exception 'contribution not found or not due a refund' using errcode = 'P0002';
  end if;
  update public.contributions
  set status = 'refunded', refunded_cents = v_cents, refund_partner_ref = p_partner_ref, refunded_at = now()
  where id = p_contribution;
  perform private.audit('contribution.refunded', 'contributions', p_contribution,
                        jsonb_build_object('partner_ref', p_partner_ref, 'refunded_cents', v_cents));
  return v_cents;
end $$;

revoke all on function public.mark_refunded(uuid, text) from public, anon, authenticated;
grant execute on function public.mark_refunded(uuid, text) to service_role;
