-- The ops console's reserve panel (roadmap 1e: "reconciliation and reserve panels join
-- in 2h"). The weekly allocation run leaves part of each fund's money in reserve for
-- the next band; the console's operators need to SEE what a run left, not re-derive it,
-- and `pool_runs` is written by the service alone. So this door answers the run itself:
-- fund-level figures only — the fund's money, what the run allocated, what it left in
-- reserve, the algorithm version, and when it ran. Fund-level aggregates are the same
-- class of figures open_books publishes to everyone; no member, payee or vendor
-- reference crosses, and nothing here moves money.
--
-- Only the LATEST run per fund is listed: a panel that shows the fund's money as it is
-- now, not a history of runs (the history is the books' own trail, reconciled in 2h).
--
-- Reading the runs is itself audit-logged, like every privileged read, so the trail
-- shows that an operator looked.

create function public.review_pool_runs(p_limit integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_found jsonb;
begin
  if not private.is_service() and not exists (
    select 1 from public.member_roles
    where member_id = auth.uid() and role in ('reviewer', 'admin')
  ) then
    raise exception 'pool runs are read by the operations console'
      using errcode = '42501';
  end if;
  select coalesce((
    select jsonb_agg(
      jsonb_build_object('fund', r.fund, 'available_cents', r.available_cents,
                         'reserve_cents', r.reserve_cents, 'allocated_cents', r.allocated_cents,
                         'algorithm_version', r.algorithm_version, 'run_at', r.run_at)
      order by r.run_at desc
    )
    from public.pool_runs r
    where not exists (
      select 1 from public.pool_runs n
      where n.fund = r.fund and n.run_at > r.run_at
    )
    limit least(greatest(p_limit, 1), 100)
  ), '[]'::jsonb) into v_found;
  perform private.audit('pool_runs.read', 'pool_runs', NULL,
    jsonb_build_object('limit', least(greatest(p_limit, 1), 100),
                       'count', jsonb_length(v_found)));
  return v_found;
end $$;

revoke all on function public.review_pool_runs(integer) from public, anon, authenticated;
grant execute on function public.review_pool_runs(integer)
  to authenticated, service_role;