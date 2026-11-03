-- The "how often paid" record is dated by the payout actually sent, not by
-- when the payout row was opened: a request that waited months for the fund
-- was paid when the money went out (the board already counts payouts by
-- `sent_at`, and `paid_share_test`'s rule reads this count). Counting by
-- `created_at` put a payout that had to wait months outside the three-year
-- window the comment promises, quietly shrinking a member's share.

create or replace function public.pool_requests_paid_3y(p_member uuid) returns integer
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is not null and p_member is distinct from auth.uid() then
    raise exception 'you can only see your own record' using errcode = '42501';
  end if;
  return (
    select count(*)::integer from public.requests r
    where r.member_id = p_member and r.status = 'paid' and r.funding in ('pool', 'both')
      and exists (select 1 from public.payouts p
                  where p.request_id = r.id and p.status = 'sent'
                    and coalesce(p.sent_at, p.created_at) > now() - interval '3 years'));
end $$;

revoke all from function public.pool_requests_paid_3y(uuid);
revoke all from function public.pool_requests_paid_3y(uuid) to public, anon, authenticated;
grant execute on function public.pool_requests_paid_3y(uuid) to authenticated;
