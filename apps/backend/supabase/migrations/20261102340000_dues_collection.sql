-- Dues collection: the cooperative charges each member's monthly dues through
-- the payment partner (design.md: the cooperative pays premiums, the member
-- side never calls it a premium). The pending row is the ask — `enqueue_dues`
-- creates it with the member's own figure from their active subscription —
-- and `capture_dues` closes it once the partner confirms the money moved,
-- answering with the figure so the webhook journals the schema's number,
-- never the partner's word. Service only; the monthly cron and webhook own
-- the schedule, so members can't invent dues.

create function public.enqueue_dues(p_member uuid, p_period date) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  m       public.members;
  sub     public.subscriptions;
  v_id    uuid;
begin
  if not private.is_service() then
    raise exception 'dues are collected by the service' using errcode = '42501';
  end if;
  if p_period is null or extract(day from p_period) <> 1 then
    raise exception 'a dues period must start on the first of a month' using errcode = '23514';
  end if;
  select * into m from public.members where id = p_member;
  if m.id is null or m.status <> 'active' then
    raise exception 'member not found or not active' using errcode = 'P0002';
  end if;
  select * into sub from public.subscriptions
  where member_id = p_member and ends_on is null;
  if sub.id is null then
    raise exception 'the member has no active subscription to collect' using errcode = 'P0002';
  end if;
  if sub.monthly_cents = 0 then
    raise exception 'a $0 dues subscription has nothing to collect' using errcode = '23514';
  end if;
  -- Idempotent per member per period: the cron replaying a month changes nothing.
  if exists (select 1 from public.subscription_payments
             where subscription_id = sub.id and period = p_period) then
    return (select id from public.subscription_payments
            where subscription_id = sub.id and period = p_period);
  end if;
  insert into public.subscription_payments (subscription_id, member_id, period, amount_cents, status)
  values (sub.id, p_member, p_period, sub.monthly_cents, 'pending')
  returning id into v_id;
  perform private.audit('dues.collected', 'subscription_payments', v_id,
                        jsonb_build_object('member_id', p_member, 'period', p_period));
  return v_id;
end $$;

create function public.capture_dues(p_payment uuid, p_partner_ref text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_amount bigint;
begin
  if not private.is_service() then
    raise exception 'dues are collected by the service' using errcode = '42501';
  end if;
  if p_partner_ref is null or p_partner_ref = '' then
    raise exception 'a dues capture needs the partner''s reference' using errcode = '23514';
  end if;
  update public.subscription_payments
  set status = 'captured', captured_at = now(),
      partner_ref = case when partner_ref is null then p_partner_ref else partner_ref end
  where id = p_payment and status = 'pending'
  returning amount_cents into v_amount;
  if v_amount is null then
    -- Already captured: answer with the stored figure, change nothing.
    select amount_cents from public.subscription_payments where id = p_payment limit 1 into v_amount;
    if v_amount is null then
      raise exception 'payment not found' using errcode = 'P0002';
    end if;
  end if;
  perform private.audit('dues.captured', 'subscription_payments', p_payment,
                        jsonb_build_object('partner_ref', p_partner_ref));
  return v_amount;
end $$;

-- New relations: claim ownership, service only.
revoke all on function public.enqueue_dues(uuid, date) from public, anon, authenticated;
grant execute on function public.enqueue_dues(uuid, date) to service_role;

revoke all on function public.capture_dues(uuid, text) from public, anon, authenticated;
grant execute on function public.capture_dues(uuid, text) to service_role;
