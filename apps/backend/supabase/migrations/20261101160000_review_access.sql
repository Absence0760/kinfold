-- Reviewer and panel access: closes gaps found building the operations console
-- and the appeals panel (roadmap steps 1e and 1i).
--
--   * reviewers can read the evidence of the requests they may review (kind,
--     redaction status, in-app capture and date are what the console shows),
--     and can fetch the redacted copy or an audited view of the original;
--   * a reviewer learns whether they may review a request (a boolean, so the
--     queue can grey the ones blocked by the anti-collusion rule) without
--     learning the requester's region;
--   * a panel member can read the request and score they are deciding an open
--     appeal on, even when they are on the panel only;
--   * appeal decisions carry a written reason, like every other decision.

-- --- 1. one place decides "may this member review this request?" -----------------

create function private.may_review(p_request uuid, p_reviewer uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.requests r
    join public.members m on m.id = r.member_id
    where r.id = p_request
      and r.member_id <> p_reviewer
      and r.status in ('in_review', 'needs_evidence', 'refused')
      and exists (select 1 from public.member_roles mr
                  where mr.member_id = p_reviewer and mr.role = 'reviewer')
      and (select mm.region from public.members mm where mm.id = p_reviewer) <> m.region
  );
$$;

-- The queue asks once for the whole page. Values only: the requester's region
-- never crosses the line into the response.
create function public.review_flags(p_requests uuid[]) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id  uuid;
  v_out jsonb = '{}';
begin
  foreach v_id in array p_requests loop
    v_out := v_out || jsonb_build_object(v_id::text, private.may_review(v_id, auth.uid()));
  end loop;
  return v_out;
end $$;

-- --- 2. reviewers read the evidence of what they may review ----------------------

create policy "reviewers read evidence of reviewable requests" on public.evidence for select to authenticated
  using (private.may_review(request_id, auth.uid()));

-- Redacted copies go to the console with the same rule.
create policy "reviewers read redacted evidence" on storage.objects for select to authenticated
  using (bucket_id = 'evidence-redacted' and exists (
    select 1 from public.evidence e
    where e.redacted_path = storage.objects.name and private.may_review(e.request_id, auth.uid())
  ));

-- Originals: the same reach, but every open is written down (PII read). The
-- console calls this before asking storage for the signed URL.
create function public.evidence_view(p_evidence uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_request uuid;
begin
  v_request := (select request_id from public.evidence where id = p_evidence);
  if v_request is null or not private.may_review(v_request, auth.uid()) then
    raise exception 'evidence not found or not reviewable by this member' using errcode = 'P0002';
  end if;
  perform private.audit('evidence.view', 'evidence', p_evidence);
  return p_evidence;
end $$;

-- --- 3. the appeal panel reads what it decides -----------------------------------

-- "Does this request have an open appeal waiting for the panel?" A function
-- rather than an inline subquery: `id` names two columns (appeals has one too),
-- so the name would resolve to the wrong row inside the subquery.
create function private.has_open_appeal(p_request uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.appeals a
                 where a.request_id = p_request and a.status = 'open');
$$;

create policy "panel reads requests with an open appeal to decide" on public.requests for select to authenticated
  using (public.has_role('panel'::public.member_role) and private.has_open_appeal(id));

create policy "panel reads scores of requests with an open appeal" on public.scores for select to authenticated
  using (public.has_role('panel'::public.member_role) and private.has_open_appeal(request_id));

-- --- 4. appeal decisions carry a reason ------------------------------------------

alter table public.appeals
  add column decision_note text
    check (decision_note is null or length(decision_note) between 10 and 2000);

-- The old two-argument form is gone with its missing reason; the panel's
-- decision is upheld/denied plus the reason it was written down in.
drop function public.decide_appeal(uuid, boolean);

create function public.decide_appeal(p_appeal uuid, p_uphold boolean, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  a public.appeals;
begin
  if not public.has_role('panel'::public.member_role) then
    raise exception 'appeal panel only' using errcode = '42501';
  end if;
  if p_reason is null or length(p_reason) < 10 then
    raise exception 'an appeal decision is written down in at least 10 characters' using errcode = '23514';
  end if;
  select * into a from public.appeals where id = p_appeal and status = 'open' for update;
  if a.id is null then
    raise exception 'appeal not found or already decided' using errcode = 'P0002';
  end if;
  if a.member_id = auth.uid() then
    raise exception 'you cannot decide your own appeal' using errcode = '42501';
  end if;
  if exists (select 1 from public.reviews where request_id = a.request_id and reviewer_id = auth.uid()) then
    raise exception 'you reviewed this request; another panel member decides the appeal' using errcode = '42501';
  end if;
  update public.appeals
  set status = case when p_uphold then 'upheld'::public.appeal_status else 'denied' end,
      decided_by = auth.uid(), decided_at = now(), decision_note = p_reason
  where id = p_appeal;
  if p_uphold then
    update public.requests set status = 'in_review' where id = a.request_id;
  end if;
  perform private.audit(case when p_uphold then 'appeal.upheld' else 'appeal.denied' end,
                        'appeals', p_appeal, jsonb_build_object('reason', p_reason));
end $$;

-- --- grants ---------------------------------------------------------------------

grant execute on function
  public.review_flags(uuid[]), public.evidence_view(uuid)
to authenticated;
grant execute on function
  public.decide_appeal(uuid, boolean, text)
to authenticated;