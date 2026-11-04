-- Dues money gets its own fund account (roadmap 2b/2d, followups: the pool
-- must not be fed by dues). design.md: dues pay premiums (paid in full to the
-- insurer), gifts and grants fund capped repair grants, and dues left over go
-- to reserves or back to members by vote. Today dues money journalled straight
-- into `available`, the account the pool allocation draws from — dues money
-- could therefore buy a pool grant, which is neither lawful nor designed. New
-- fund-level `dues` account: dues money arrives there, premiums move out of it,
-- and `available` only ever holds money the fund itself holds (gifts, grants,
-- partner transfers). The `premiums` account from premium_dues stays as the
-- paying side.

insert into private.ledger_accounts (fund, code)
  values ('protection', 'dues');

-- pay_cover_premium now reads and moves dues money from the dues account.
create or replace function public.pay_cover_premium(p_member uuid, p_partner_ref text)
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
  v_avail := public.ledger_balance('protection'::public.fund, 'dues');
  if v_avail < v_amount then
    raise exception 'premiums must be paid from dues money the fund already holds' using errcode = '23514';
  end if;
  v_id := private.post_journal('protection', 'premium', p_member, p_partner_ref,
    jsonb_build_array(
      jsonb_build_object('code', 'dues', 'amount_cents', -v_amount),
      jsonb_build_object('code', 'premiums', 'amount_cents', v_amount)));
  perform private.audit('premiums.paid', 'ledger_journals', v_id,
    jsonb_build_object('member_id', p_member, 'amount_cents', v_amount));
  return v_id;
end $$;

revoke all on function public.pay_cover_premium(uuid, text) from public, anon, authenticated;
grant execute on function public.pay_cover_premium(uuid, text) to service_role;
