-- A denied claim can be appealed: design.md says denials are a person's
-- decision WITH appeal — the requester who believes the denial was wrong
-- writes why, and the claim re-opens for a fresh decision. Only the
-- requester may appeal their own claim (the pair's names never cross a
-- console, and the appeal is audit-logged with the written reason, same
-- as every review decision).

create function public.appeal_claim(p_claim uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_request uuid;
begin
  if p_reason is null or length(p_reason) < 10 then
    raise exception 'an appeal needs the written reason (at least 10 characters)'
      using errcode = '23514';
  end if;
  update public.claims set status = 'recorded', reason = p_reason,
      decided_by = null, decided_at = null
  where id = p_claim and status = 'denied'
  returning request_id into v_request;
  if v_request is null then
    raise exception 'claim not found or not denied' using errcode = 'P0002';
  end if;
  if auth.uid() not in (
    (select member_id from public.requests where id = v_request)
  ) then
    raise exception 'only the requester can appeal their claim' using errcode = '42501';
  end if;
  perform private.audit('claim.appealed', 'claims', p_claim,
                        jsonb_build_object('reason', p_reason));
end $$;

-- New relation: claim ownership.
revoke all from function public.appeal_claim(uuid, text);
revoke all from function public.appeal_claim(uuid, text) to public, anon;
grant execute on function public.appeal_claim(uuid, text) to authenticated;
