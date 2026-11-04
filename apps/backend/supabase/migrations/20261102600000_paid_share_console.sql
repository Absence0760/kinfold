-- design.md's promise, made visible: the member's own share rule answers on the
-- reliability card the same way the reliability record itself does, so a member
-- can see WHY the fund's grant to them is smaller than what their request still
-- needs - and that the difference is money they carry themselves, never a
-- refusal or a wait. No new facts: the same three numbers the schema computes.

create function public.my_share() returns table (
  requests_paid_3y integer, share_bps integer, rule_version integer
) language sql stable security definer set search_path = '' as $$
  select
    public.pool_requests_paid_3y(auth.uid()),
    public.member_share_bps(auth.uid()),
    public.share_rule_version();
$$;

revoke all on function public.my_share() from public, anon, authenticated;
grant execute on function public.my_share() to authenticated;
