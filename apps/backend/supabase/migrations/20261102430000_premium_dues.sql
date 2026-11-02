-- Cover premiums come from dues (design.md: the cooperative pays every member's
-- premium from dues, never called a premium on the member side, anti-rebating
-- law). The filed rates from `cover_plans` say what a member's covered vehicles
-- cost; that money moves out of the fund's dues money (`available`) into a
-- `premiums` account of its own — so premiums and pool money never double-count
-- each other, and premium money is money the fund holds as cover commitments.

-- A covered vehicle carries its rating-law class once the member states it;
-- homes never have one. Unclassed vehicles have no filed premium yet, so they
-- take no premium money — the honest stand-in until the class is given.
alter table public.covered_assets
  add vehicle_class public.vehicle_class,
  add constraint covered_assets_class_only_for_vehicles check (kind = 'vehicle' or vehicle_class is null);

-- Premium money is money the fund has committed to the insurer's cover.
insert into private.ledger_accounts (fund, code) values ('protection', 'premiums');

-- The premiums a member's covered, classed vehicles cost at their filed rates.
create function public.cover_premium_cents(p_member uuid) returns bigint
language sql stable security definer set search_path = '' as $$
  select coalesce((select sum(public.premium_for(p_member, a.vehicle_class))
                   from public.covered_assets a
                   where a.member_id = p_member
                     and a.vehicle_class is not null
                     and a.kind = 'vehicle'
                     and a.removed_on is null), 0);
$$;

-- Service only: pay a member's premiums out of the fund's dues money. The
-- reference makes a replayed cron a no-op. The fund's dues money has to
-- actually cover them, so premiums are paid from dues — never minted.
create function public.pay_cover_premium(p_member uuid, p_partner_ref text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_amount bigint;
  v_avail  bigint;
  v_id     uuid;
begin
  if not private.is_service() then
    raise exception 'premiums are paid by the service' using errcode = '42501';
  end if;
  if p_partner_ref is null or p_partner_ref = '' then
    raise exception 'a premium payment needs the partner''s reference' using errcode = '23514';
  end if;
  -- A replayed cron is a no-op answering with the journal it already made.
  if exists (select 1 from private.ledger_journals
             where partner_ref = p_partner_ref and kind = 'premium') then
    return (select id from private.ledger_journals
            where partner_ref = p_partner_ref and kind = 'premium');
  end if;
  v_amount := public.cover_premium_cents(p_member);
  if v_amount <= 0 then
    raise exception 'a member without classed covered vehicles has no premiums to pay' using errcode = '23514';
  end if;
  v_avail := public.ledger_balance('protection'::public.fund, 'available');
  if v_avail < v_amount then
    raise exception 'premiums must be paid from dues money the fund already holds' using errcode = '23514';
  end if;
  v_id := private.post_journal('protection', 'premium', p_member, p_partner_ref,
    jsonb_build_array(
      jsonb_build_object('code', 'available', 'amount_cents', -v_amount),
      jsonb_build_object('code', 'premiums', 'amount_cents', v_amount)));
  perform private.audit('premiums.paid', 'ledger_journals', v_id,
    jsonb_build_object('member_id', p_member, 'amount_cents', v_amount));
  return v_id;
end $$;

revoke all from function public.cover_premium_cents(uuid);
revoke all from function public.cover_premium_cents(uuid) to public, anon;
grant execute on function public.cover_premium_cents(uuid) to authenticated, service_role;

revoke all from function public.pay_cover_premium(uuid, text);
revoke all from function public.pay_cover_premium(uuid, text) to public, anon, authenticated;
grant execute on function public.pay_cover_premium(uuid, text) to service_role;
