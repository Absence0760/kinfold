-- The daily reconcile job compares ledger balances with the partners'
-- statements (launch tests: "books reconcile daily"). The ledger lives in
-- `private`, which PostgREST never exposes, and the schema had no way to ask
-- what's in a fund-level account. `ledger_balance` is that read: service
-- only (it sees money the members' RLS never should), fund-level accounts
-- only (member/payee money stays theirs).

create function public.ledger_balance(p_fund public.fund, p_code text) returns bigint
language sql stable security definer set search_path = '' as $$
  select coalesce(sum(l.amount_cents), 0)
  from private.ledger_lines l
  join private.ledger_accounts a on a.id = l.account_id
  where a.fund = p_fund and a.code = p_code and a.member_id is null and a.payee_id is null;
$$;

-- New relation: claim ownership, service only.
revoke all from function public.ledger_balance(public.fund, text);
revoke all from function public.ledger_balance(public.fund, text) to public, anon, authenticated;
grant execute on function public.ledger_balance(public.fund, text) to service_role;
