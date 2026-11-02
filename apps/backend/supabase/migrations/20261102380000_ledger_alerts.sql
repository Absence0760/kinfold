-- Reconcile differences need more than a cron log (followups: the alert was
-- only a returned string). A discrepancy between the partner's statement and
-- the ledger is an alert the operators can find later; money is never moved
-- from here. Service only: the ledger side of the comparison is fund-level
-- books, money the members' RLS never should see.

create table public.ledger_differences (
  id              uuid primary key default gen_random_uuid(),
  fund            public.fund not null,
  code            text not null,
  statement_cents bigint not null,
  ledger_cents    bigint not null check (statement_cents <> ledger_cents),
  recorded_at     timestamptz not null default now()
);

create trigger ledger_differences_append_only before update or delete
  on public.ledger_differences for each row execute function private.forbid_change();

alter table public.ledger_differences enable row level security;

-- No read policies: authenticated and anon see nothing; the service holds the
-- table grants below.

create function public.record_ledger_difference(
  p_fund public.fund, p_code text, p_statement_cents bigint, p_ledger_cents bigint
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not private.is_service() then
    raise exception 'differences are recorded by the service' using errcode = '42501';
  end if;
  if p_statement_cents = p_ledger_cents then
    raise exception 'a matching statement is not a difference' using errcode = '23514';
  end if;
  insert into public.ledger_differences
    (fund, code, statement_cents, ledger_cents)
    values (p_fund, p_code, p_statement_cents, p_ledger_cents)
    returning id into v_id;
  perform private.audit('ledger.difference', 'ledger_differences', v_id,
    jsonb_build_object('fund', p_fund, 'code', p_code));
  return v_id;
end $$;

revoke all from function public.record_ledger_difference(public.fund, text, bigint, bigint);
revoke all from function public.record_ledger_difference(public.fund, text, bigint, bigint)
  to public, anon, authenticated;
grant execute on function public.record_ledger_difference(public.fund, text, bigint, bigint)
  to service_role;

grant select, insert on public.ledger_differences to service_role;
