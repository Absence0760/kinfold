-- Claim decisions are one atomic step (`decide_claim`), because `deny_claim`
-- only accepts a reviewer refusal recorded in the SAME transaction
-- (it pins `reviews.created_at = now()`, and `now()` is fixed for the whole
-- transaction): two console calls are two transactions with different
-- instants, so the two-step flow could never satisfy the rule. Recording the
-- reviewer's refusal and denying the claim together is the console's real
-- decision — no half-denied claim can exist on screen. Reviewers can also
-- read the standing claims of what they may review, so the console can show
-- the claim a denial would close.

-- A reviewer's reach for CLAIMS follows `record_review`'s reviewable set
-- (`may_review`'s narrower set drives the review QUEUE: only what awaits a
-- review). A claim stands beside money that has already moved, so its denial
-- lives on a request the queue would no longer show; the console still has
-- to read the standing claim to deny it, so the claims door matches the
-- door that records the refusal the denial leans on.
create function private.may_review_claims(p_request uuid, p_reviewer uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.requests r
    join public.members m on m.id = r.member_id
    where r.id = p_request
      and r.member_id <> p_reviewer
      and r.status in ('in_review', 'needs_evidence', 'open', 'funded', 'refused')
      and exists (select 1 from public.member_roles mr
                  where mr.member_id = p_reviewer and mr.role = 'reviewer')
      and (select mm.region from public.members mm where mm.id = p_reviewer) <> m.region
  );
$$;

create policy "reviewers read standing claims of reviewable requests" on public.claims for select to authenticated
  using (status = 'recorded' and private.may_review_claims(request_id, auth.uid()));

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
revoke all on function public.decide_claim(uuid, text) from public, anon, authenticated;
grant execute on function public.decide_claim(uuid, text) to authenticated;
