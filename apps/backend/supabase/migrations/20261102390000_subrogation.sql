-- Subrogation (roadmap 2g): when another driver is at fault, THEIR insurer
-- should pay — Kinfold's deductible cover must not subsidise other insurers
-- (design.md "When another driver is at fault, their insurer should pay").
-- The partner insurer claims from the at-fault insurer and reports the money
-- that moved; the schema records that recovery ALREADY verified (one step, so
-- a webhook retry can't leave a half-verified row) and the pledge caps and
-- pool needs subtract it through `private.recovered_cents`.

-- Service-only write: this money moved between insurers, not through a member.
create function public.record_partner_recovery(
  p_request uuid, p_source public.recovery_source, p_amount_cents bigint,
  p_on date, p_partner_ref text, p_note text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not private.is_service() then
    raise exception 'partner money is recorded by the service' using errcode = '42501';
  end if;
  if p_partner_ref is null or p_partner_ref = '' then
    raise exception 'partner money needs the partner''s reference' using errcode = '23514';
  end if;
  if p_amount_cents <= 0 then
    raise exception 'money covered must be positive' using errcode = '23514';
  end if;
  perform 1 from public.requests where id = p_request for update;
  if not found then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  -- Webhook retries: the same partner reference is a no-op, never a second row.
  if exists (select 1 from public.request_recoveries where partner_ref = p_partner_ref) then
    return null;
  end if;
  insert into public.request_recoveries
    (request_id, source, amount_cents, recovered_on, note, partner_ref, verified_at)
    values (p_request, p_source, p_amount_cents, p_on, p_note,
            p_partner_ref, now())
    returning id into v_id;
  perform private.audit('recovery.partner', 'request_recoveries', v_id,
    jsonb_build_object('request_id', p_request, 'source', p_source,
                       'amount_cents', p_amount_cents));
  return v_id;
end $$;

revoke all on function public.record_partner_recovery(uuid, public.recovery_source, bigint, date, text, text) from public, anon, authenticated;
grant execute on function public.record_partner_recovery(uuid, public.recovery_source, bigint, date, text, text)
  to service_role;
