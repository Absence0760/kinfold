-- Panel review for needs edge cases (the rest of 3b): the formula ranks
-- applicants, but a score on a band boundary is a judgement call, so a
-- reviewer may record a needs decision with a written reason beside the
-- ranking. The decision is history, never an edit of the score: the score
-- stays what the published formula said, and the decision sits next to it.

create type public.needs_decision as enum ('needs', 'not_needs');

create table public.needs_reviews (
  id              uuid primary key default gen_random_uuid(),
  request_id      uuid not null references public.requests (id) on delete cascade,
  reviewer_id     uuid not null references public.members (id),
  formula_version integer not null references public.needs_formulas (version),
  decision        public.needs_decision not null,
  reason          text not null check (length(reason) between 10 and 1000),
  created_at      timestamptz not null default now(),
  unique (request_id, reviewer_id, formula_version)
);

create trigger needs_reviews_append_only before update or delete on public.needs_reviews
  for each row execute function private.forbid_change();

-- A reviewer answers an edge case beside the ranking the Fund published: their
-- own region never decides their own applicant, and the decision names the
-- formula version it was made against, so it can be read next to the score.
create function public.record_needs_decision(p_request uuid, p_decision public.needs_decision,
  p_reason text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  r  public.needs_records;
begin
  select * into r from public.needs_records
  where request_id = p_request
  order by formula_version desc limit 1;
  if r.id is null then
    raise exception 'only an applicant the Fund has ranked can be answered' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.requests req
                 where req.id = p_request
                 and public.fund_for_kind(req.kind) = 'home_fund'
                 and req.status in ('in_review', 'needs_evidence')) then
    raise exception 'request not found, not a Home Fund applicant, or not awaiting review' using errcode = 'P0002';
  end if;
  if not private.may_review(p_request, auth.uid()) then
    raise exception 'only a reviewer from another state answers an edge case' using errcode = '42501';
  end if;
  -- A written reason is the input check the table's length constraint
  -- backstops; the door runs it first so bad input is refused in the console's
  -- words, and a duplicate attempt is refused in its own.
  if p_reason is null or length(p_reason) < 10 or length(p_reason) > 1000 then
    raise exception 'a needs decision needs a written reason (at least 10 characters)' using errcode = '23514';
  end if;
  -- The table's unique (request, reviewer, version) is the backstop, but the
  -- door names the rule in the reviewer's words first, so a second answer in
  -- the console reads as "one answer per reviewer per formula version" rather
  -- than the raw constraint.
  if exists (select 1 from public.needs_reviews
             where request_id = p_request and reviewer_id = auth.uid()
             and formula_version = r.formula_version) then
    raise exception 'one answer per reviewer per formula version' using errcode = '23514';
  end if;
  insert into public.needs_reviews
    (request_id, reviewer_id, formula_version, decision, reason)
    values (p_request, auth.uid(), r.formula_version, p_decision, p_reason);
  perform private.audit('needs_reviews.decided', 'needs_reviews', p_request,
    jsonb_build_object('reviewer_id', auth.uid(), 'decision', p_decision,
                       'formula_version', r.formula_version, 'score', r.score));
end $$;

-- --- access --------------------------------------------------------------------

alter table public.needs_reviews enable row level security;
revoke all on public.needs_reviews from anon, authenticated;

create policy "reviewers read needs decisions" on public.needs_reviews for select to authenticated
  using (exists (select 1 from public.requests r
                 where r.id = request_id
                 and (r.member_id = auth.uid() or private.may_review(request_id, auth.uid()))));
grant select on public.needs_reviews to authenticated;

revoke all on function public.record_needs_decision(uuid, public.needs_decision, text) from public, anon;
grant execute on function public.record_needs_decision(uuid, public.needs_decision, text)
  to authenticated;
