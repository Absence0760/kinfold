-- `evidence-url` hands reviewers a short-lived signed URL for a request's
-- original evidence (followups: originals stay owner-only; reviewers see
-- them only through the edge function). The URL itself is minted by
-- storage's sign endpoint; what the schema owns is the AUDIT of every
-- issuing: which request, which file, so a PII read leaves a trail
-- (design.md: PII reads are audit-logged). Only the service calls it.

create function public.record_evidence_url(
  p_request uuid, p_path text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.requests;
begin
  if not private.is_service() then
    raise exception 'evidence URLs are issued by the service' using errcode = '42501';
  end if;
  select * into r from public.requests where id = p_request;
  if r.id is null then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if p_path is null or p_path = '' then
    raise exception 'an evidence URL needs the file it points at' using errcode = '23514';
  end if;
  perform private.audit('evidence.url_issued', 'requests', p_request,
                        jsonb_build_object('path', p_path));
end $$;

-- New relation: claim ownership, service only.
revoke all on function public.record_evidence_url(uuid, text) from public, anon, authenticated;
grant execute on function public.record_evidence_url(uuid, text) to service_role;
