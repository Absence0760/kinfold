-- The ops console reads the recorded reconcile differences (roadmap 1e: "reconciliation
-- and reserve panels join in 2h"). `ledger_differences` is service-only by design —
-- a reviewer needs to SEE an alert, not re-derive one, and the ledger books behind
-- it stay behind the service. So this door answers the alert itself: fund, account,
-- the partner's statement, the ledger's own figure, and when it was recorded. Fund-
-- level aggregates only, the same class of figures open_books publishes to everyone;
-- no member, payee or vendor reference crosses.
--
-- Reading the alerts is itself audit-logged, like every privileged read, so the
-- trail shows that an operator looked.

create function public.review_ledger_differences(p_limit integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_found jsonb;
begin
  if not private.is_service() and not exists (
    select 1 from public.member_roles
    where member_id = auth.uid() and role in ('reviewer', 'admin')
  ) then
    raise exception 'ledger differences are read by the operations console'
      using errcode = '42501';
  end if;
  select coalesce((
    select jsonb_agg(
      jsonb_build_object('fund', d.fund, 'code', d.code,
                         'statement_cents', d.statement_cents,
                         'ledger_cents', d.ledger_cents,
                         'recorded_at', d.recorded_at)
      order by d.recorded_at desc
    )
    from public.ledger_differences d
    limit least(greatest(p_limit, 1), 100)
  ), '[]'::jsonb) into v_found;
  perform private.audit('ledger_differences.read', 'ledger_differences', NULL,
    jsonb_build_object('limit', least(greatest(p_limit, 1), 100),
                       'count', jsonb_length(v_found)));
  return v_found;
end $$;

revoke all on function public.review_ledger_differences(integer) from public, anon, authenticated;
grant execute on function public.review_ledger_differences(integer)
  to authenticated, service_role;