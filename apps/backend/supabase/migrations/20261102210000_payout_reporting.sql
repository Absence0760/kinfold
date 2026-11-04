-- Payout reporting has an owner: the payments webhook says a payout was sent,
-- failed or came back, and today that's a bare table write for the service
-- role. A guarded function is a better home: the same idempotence webhooks
-- need (the same report twice is a no-op), the honest transitions, and the
-- rule followups.md flagged open — a payout can't be reported returned or
-- failed once the request already has refunded contributions, because `refunds_due`
-- splits captured money across live payouts oldest first and a late return
-- wouldn't re-run that split. Refusing sends it to a person: the console can
-- read the audit row and decide.
--
-- Only `sent_at` bookkeeping stays where it is (`private.stamp_payout_sent`
-- from …120600): this function only moves status, and the trigger stamps it.

create function public.report_payout(p_payout uuid, p_outcome public.payout_status)
returns void language plpgsql security definer set search_path = '' as $$
declare
  p public.payouts;
begin
  if not private.is_service() then
    raise exception 'payout outcomes are reported by the service' using errcode = '42501';
  end if;
  if p_outcome = 'pending' then
    raise exception 'a payout starts pending; the partner only reports an outcome' using errcode = '23514';
  end if;
  select * into p from public.payouts where id = p_payout for update;
  if p.id is null then
    raise exception 'payout not found' using errcode = 'P0002';
  end if;
  -- Webhooks retry: the same outcome reported twice is a no-op.
  if p.status = p_outcome then
    return;
  end if;
  if p_outcome in ('returned', 'failed') then
    if exists (select 1 from public.contributions c
               where c.request_id = p.request_id and c.status = 'refunded') then
      raise exception 'a payout cannot be reported % once money was refunded on its request; the console decides what happens next'
        , p_outcome using errcode = '23514';
    end if;
  end if;
  -- Honest moves only: pending becomes an outcome, sent can come back,
  -- failed and returned are terminal.
  if p.status = 'pending' and p_outcome in ('sent', 'failed') then
    update public.payouts set status = p_outcome where id = p_payout;
  elsif p.status = 'sent' and p_outcome = 'returned' then
    update public.payouts set status = p_outcome where id = p_payout;
  else
    raise exception 'a payout moves % -> % in no honest step', p.status, p_outcome using errcode = '23514';
  end if;
  perform private.audit('payout.reported', 'payouts', p_payout,
                        jsonb_build_object('outcome', p_outcome, 'request_id', p.request_id));
end $$;

-- New relations get default grants from Supabase: take them back, then hand
-- this to the service only — a member never reports an outcome.
revoke all on function public.report_payout(uuid, public.payout_status) from public, anon, authenticated;
grant execute on function public.report_payout(uuid, public.payout_status) to service_role;