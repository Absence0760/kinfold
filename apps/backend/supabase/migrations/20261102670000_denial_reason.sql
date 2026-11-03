-- A denial always carries the person's words (design.md, "Only a person can
-- deny a claim, with appeal" and, in declared disasters, "a decision with a
-- payment statement or decline letter"). Today `deny_claim` takes a reason but
-- never asks for one, so a claim can be denied with nothing but a status: the
-- member's card shows a closed badge and no words, an appeal has nothing to
-- answer, and there is nothing a decline letter could quote. So the reason
-- becomes a table check AND a door refusal, asked for BEFORE anything is
-- written — the same floor an appeal asks for (ten characters), because the
-- two halves of a disagreement are meant to be readable in both directions.

alter table public.claims
  add constraint denials_carry_their_reason check (
    status <> 'denied'
    or (reason is not null and length(trim(reason)) >= 10));

-- The door names the reason it wants, and refuses before the update, so a
-- short reason leaves nothing half-written (the reviewer's own refusal rides
-- the same transaction, and an aborted transaction writes neither).
create or replace function public.deny_claim(p_claim uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_request uuid;
begin
  if p_reason is null or length(trim(p_reason)) < 10 then
    raise exception 'a denial needs the person''s written reason (at least 10 characters)' using errcode = '23514';
  end if;
  update public.claims set status = 'denied', reason = p_reason, decided_by = auth.uid(), decided_at = now()
  where id = p_claim and status = 'recorded'
  returning request_id into v_request;
  if v_request is null then
    raise exception 'claim not found or already decided' using errcode = 'P0002';
  end if;
  if not exists (
    select 1 from public.reviews where request_id = v_request and decision = 'refuse' and created_at = now()
  ) then
    raise exception 'only a reviewer''s recorded decision can deny a claim' using errcode = '42501';
  end if;
  perform private.audit('claim.denied', 'claims', p_claim, jsonb_build_object('reason', p_reason));
end $$;

-- The console door is refiled the same way: the reason is checked before the
-- refusal and the denial are attempted, so a refusal without words writes
-- neither a review nor a denial.
create or replace function public.decide_claim(p_claim uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_request uuid;
begin
  if p_reason is null or length(trim(p_reason)) < 10 then
    raise exception 'a denial needs the person''s written reason (at least 10 characters)' using errcode = '23514';
  end if;
  select request_id from public.claims where id = p_claim and status = 'recorded' into v_request;
  if v_request is null then
    raise exception 'claim not found, or already decided' using errcode = 'P0002';
  end if;
  -- The refusal and the denial land together: if either refuses, nothing at all
  -- was written (the transaction aborts).
  perform public.record_review(v_request, 'refuse', p_reason);
  perform public.deny_claim(p_claim, p_reason);
end $$;

revoke all from function public.deny_claim(uuid, text);
revoke all from function public.deny_claim(uuid, text) to public, anon;
grant execute on function public.deny_claim(uuid, text) to authenticated, service_role;

revoke all from function public.decide_claim(uuid, text);
revoke all from function public.decide_claim(uuid, text) to public, anon, authenticated;
grant execute on function public.decide_claim(uuid, text) to authenticated;