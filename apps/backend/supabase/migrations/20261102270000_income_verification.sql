-- Income checks get a guarded owner (followups: earnings pricing had no
-- write path, so the verify-income function had nowhere honest to post to).
-- `income_verifications` records what the vendor read; the member's
-- subscription then prices against it. The bank-link leg needs the vendor's
-- reference (so the check can be traced), a self-attested figure doesn't.
-- Only the service writes: the vendor's webhook and the verify-income
-- function are the service. Members read their own checks (existing policy).

create function public.record_income_verification(
  p_member uuid, p_method public.income_method, p_monthly_income_cents bigint,
  p_provider_ref text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not private.is_service() then
    raise exception 'income checks are recorded by the service' using errcode = '42501';
  end if;
  if not exists (select 1 from public.members where id = p_member and status = 'active') then
    raise exception 'member not found or not active' using errcode = 'P0002';
  end if;
  if p_monthly_income_cents < 0 then
    raise exception 'a monthly income figure can''t be negative' using errcode = '23514';
  end if;
  -- A bank-linked figure has to be traceable to the vendor's read; a
  -- self-attested or tax-return figure carries no vendor reference.
  if p_method = 'bank_link' and (p_provider_ref is null or p_provider_ref = '') then
    raise exception 'a bank-linked income check needs the vendor''s reference' using errcode = '23514';
  end if;
  insert into public.income_verifications (member_id, method, monthly_income_cents, provider_ref)
  values (p_member, p_method, p_monthly_income_cents, p_provider_ref)
  returning id into v_id;
  perform private.audit('income.verified', 'income_verifications', v_id,
                        jsonb_build_object('method', p_method, 'member_id', p_member));
  return v_id;
end $$;

revoke all from function public.record_income_verification(uuid, public.income_method, bigint, text);
revoke all from function public.record_income_verification(uuid, public.income_method, bigint, text)
  to public, anon, authenticated;
grant execute on function public.record_income_verification(uuid, public.income_method, bigint, text)
  to service_role;
