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

-- The class is a person's statement, so the member states it on their own
-- covered vehicle; homes never take one, a removed vehicle keeps nothing.
create function public.set_vehicle_class(p_asset uuid, p_class public.vehicle_class)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'the class is stated by the member who owns the vehicle' using errcode = '42501';
  end if;
  update public.covered_assets set vehicle_class = p_class
  where id = p_asset and member_id = auth.uid() and kind = 'vehicle' and removed_on is null;
  if not found then
    raise exception 'asset not found, not yours, already removed, or not a vehicle' using errcode = 'P0002';
  end if;
  perform private.audit('covered_assets.class', 'covered_assets', p_asset,
    jsonb_build_object('member_id', auth.uid(), 'vehicle_class', p_class));
end $$;

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

revoke all on function public.set_vehicle_class(uuid, public.vehicle_class) from public, anon;
revoke all on function public.cover_premium_cents(uuid) from public, anon;
grant execute on function public.cover_premium_cents(uuid) to authenticated, service_role;

revoke all on function public.pay_cover_premium(uuid, text) from public, anon, authenticated;
grant execute on function public.pay_cover_premium(uuid, text) to service_role;
grant execute on function public.set_vehicle_class(uuid, public.vehicle_class) to authenticated;
