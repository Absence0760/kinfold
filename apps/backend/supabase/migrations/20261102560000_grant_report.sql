-- The grant report (roadmap 3d's web half, design.md: "the transparency
-- dashboard is the grant report"). Funders and agencies get the same
-- aggregates the public sees, so grant money is reported by fund and source —
-- never a grant-to-allocation link (grants fund the Fund, not a list of
-- chosen families). Figures are fund-level only: no member data, so the
-- report is readable by everyone like the open books.

create function public.grant_report() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_found jsonb;
begin
  select coalesce((
    select jsonb_agg(
      jsonb_build_object('fund', a.fund, 'source', a.source, 'federal', a.federal,
                         'amount_cents', a.amount_cents, 'grants', a.grants)
    )
    from (
      select g.fund, g.source, g.federal,
             sum(g.amount_cents) as amount_cents, count(*) as grants
      from public.grants g
      group by g.fund, g.source, g.federal
      order by g.fund, g.source, g.federal
    ) a
  ), '[]'::jsonb) into v_found;
  return v_found;
end $$;

-- New function: hardening.sql's blanket client grants don't cover it. Public
-- by design — funders are supposed to see what they funded.
revoke all on function public.grant_report() from public, anon, authenticated;
grant execute on function public.grant_report() to anon, authenticated, service_role;