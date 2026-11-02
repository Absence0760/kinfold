-- Claim decisions are one atomic step (`decide_claim`), because `deny_claim`
-- only accepts a reviewer refusal recorded in the SAME transaction
-- (it pins `reviews.created_at = now()`, and `now()` is fixed for the whole
-- transaction): two console calls are two transactions with different
-- instants, so the two-step flow could never satisfy the rule. Recording the
-- reviewer's refusal and denying the claim together is the console's real
-- decision — no half-denied claim can exist on screen. Reviewers can also
-- read the standing claims of what they may review, so the console can show
-- the claim a denial would close.

create policy "reviewers read standing claims of reviewable requests" on public.claims for select to authenticated
  using (status = 'recorded' and private.may_review(request_id, auth.uid()));

create function public.decide_claim(p_claim uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_request uuid;
begin
  select request_id from public.claims where id = p_claim and status = 'recorded' into v_request;
  if v_request is null then
    raise exception 'claim not found, or already decided' using errcode = 'P0002';
  end if;
  -- The refusal and the denial land together: if either refuses, nothing at all
  -- was written (the transaction aborts).
  perform public.record_review(v_request, 'refuse', p_reason);
  perform public.deny_claim(p_claim, p_reason);
end $$;

-- New relation: the console (reviewers only, enforced inside) denies claims.
revoke all from function public.decide_claim(uuid, text);
revoke all from function public.decide_claim(uuid, text) to public, anon, authenticated;
grant execute on function public.decide_claim(uuid, text) to authenticated;
