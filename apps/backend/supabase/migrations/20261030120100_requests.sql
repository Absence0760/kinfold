-- Requests, evidence, scores, reviews and appeals.
--
-- A request moves through a fixed state machine (request_transitions). Clients
-- edit only drafts; every status change goes through a security definer function
-- or the service role, and is recorded in request_events. Two rules the schema
-- itself enforces, not just the app:
--   * a score never refuses: only a person's recorded review can set 'refused';
--   * money goes to a verified payee, never to the member (see funding migration).

create type public.request_status as enum (
  'draft', 'scoring', 'needs_evidence', 'in_review', 'open', 'funded', 'paid',
  'refused', 'withdrawn', 'expired'
);
create type public.funding_mode as enum ('people', 'pool', 'both');
create type public.payee_kind as enum ('repair_shop', 'lender', 'seller', 'contractor', 'title_company');
create type public.verification_status as enum ('pending', 'verified', 'suspended');
create type public.evidence_kind as enum (
  'photo', 'police_report', 'estimate', 'invoice', 'statement', 'contract', 'other'
);
create type public.redaction_status as enum ('pending', 'auto_done', 'confirmed', 'rejected');
create type public.review_decision as enum ('approve', 'needs_evidence', 'refuse', 'escalate');
create type public.appeal_status as enum ('open', 'upheld', 'denied');

-- --- payees -------------------------------------------------------------------
-- Shops, lenders and sellers that receive money. Members can propose one; only
-- the service role (after business and bank verification) can verify it.

create table public.payees (
  id                   uuid primary key default gen_random_uuid(),
  kind                 public.payee_kind not null,
  legal_name           text not null check (length(legal_name) between 1 and 200),
  region               text not null check (region ~ '^[A-Z]{2}$'),
  status               public.verification_status not null default 'pending',
  partner_account_ref  text unique,
  verified_at          timestamptz,
  proposed_by          uuid references public.members (id) on delete set null,
  created_at           timestamptz not null default now(),
  check ((status = 'verified') = (verified_at is not null and partner_account_ref is not null)
         or status = 'suspended')
);

-- --- requests -----------------------------------------------------------------

create function public.fund_for_kind(p_kind public.request_kind) returns public.fund
language sql immutable set search_path = '' as $$
  select case
    when p_kind in ('car_damage', 'car_deductible') then 'protection'::public.fund
    else 'home_fund'::public.fund
  end;
$$;

create table public.requests (
  id              uuid primary key default gen_random_uuid(),
  member_id       uuid not null references public.members (id) on delete restrict,
  kind            public.request_kind not null,
  funding         public.funding_mode not null default 'people',
  title           text not null check (length(title) between 1 and 120),
  description     text not null default '' check (length(description) <= 5000),
  amount_cents    bigint not null check (amount_cents > 0),
  incident_on     date not null,
  asset_id        uuid references public.covered_assets (id),
  payee_id        uuid references public.payees (id),
  status          public.request_status not null default 'draft',
  -- Written by the redaction step; the board shows only this, never `title`.
  public_summary  text check (length(public_summary) <= 160),
  current_score   smallint check (current_score between 0 and 100),
  created_at      timestamptz not null default now(),
  submitted_at    timestamptz,
  check (incident_on <= created_at::date)
);

create index requests_member on public.requests (member_id);
create index requests_status on public.requests (status);

create table public.request_transitions (
  from_status public.request_status not null,
  to_status   public.request_status not null,
  primary key (from_status, to_status)
);

insert into public.request_transitions values
  ('draft', 'scoring'), ('draft', 'withdrawn'),
  ('scoring', 'open'), ('scoring', 'needs_evidence'), ('scoring', 'in_review'),
  ('needs_evidence', 'scoring'), ('needs_evidence', 'in_review'), ('needs_evidence', 'withdrawn'),
  ('needs_evidence', 'expired'),
  ('in_review', 'open'), ('in_review', 'needs_evidence'), ('in_review', 'refused'),
  ('open', 'funded'), ('open', 'in_review'), ('open', 'withdrawn'), ('open', 'expired'),
  ('funded', 'paid'), ('funded', 'in_review'),
  ('refused', 'in_review');

create table public.request_events (
  id          bigint generated always as identity primary key,
  request_id  uuid not null references public.requests (id) on delete cascade,
  from_status public.request_status,
  to_status   public.request_status not null,
  actor       uuid,
  at          timestamptz not null default now()
);

create trigger request_events_append_only before update or delete on public.request_events
  for each row execute function private.forbid_change();

create function private.guard_request_status() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then
      raise exception 'requests start as drafts' using errcode = '23514';
    end if;
    return new;
  end if;

  if new.status = old.status then
    return new;
  end if;

  if not exists (
    select 1 from public.request_transitions where from_status = old.status and to_status = new.status
  ) then
    raise exception 'a request cannot move from % to %', old.status, new.status using errcode = '23514';
  end if;

  -- The AI never refuses. Refusal needs a person's review, recorded in this
  -- same transaction, with a written reason (the reviews table requires one).
  if new.status = 'refused' and not exists (
    select 1 from public.reviews
    where request_id = new.id and decision = 'refuse' and created_at = now()
  ) then
    raise exception 'only a reviewer''s recorded decision can refuse a request' using errcode = '42501';
  end if;

  return new;
end $$;

-- Logged after the row exists, so the event's foreign key can see it.
create function private.log_request_status() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.request_events (request_id, from_status, to_status, actor)
  values (new.id, case when tg_op = 'UPDATE' then old.status end, new.status, auth.uid());
  return null;
end $$;

-- --- evidence -----------------------------------------------------------------

create table public.evidence (
  id                   uuid primary key default gen_random_uuid(),
  request_id           uuid not null references public.requests (id) on delete cascade,
  kind                 public.evidence_kind not null,
  -- Object paths: originals in the private `evidence-original` bucket under the
  -- member's id; redacted copies in `evidence-redacted`, written by the service.
  original_path        text not null unique,
  redacted_path        text unique,
  sha256               text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  perceptual_hash      text,
  captured_in_app      boolean not null default false,
  content_credentials  jsonb,
  redaction_status     public.redaction_status not null default 'pending',
  created_at           timestamptz not null default now()
);

create index evidence_request on public.evidence (request_id);
-- Not unique: the same photo on two requests is a fraud signal, not an error.
create index evidence_sha256 on public.evidence (sha256);
create index evidence_phash on public.evidence (perceptual_hash) where perceptual_hash is not null;

-- --- scores, reviews, appeals, fraud signals ----------------------------------

create table public.scores (
  id              uuid primary key default gen_random_uuid(),
  request_id      uuid not null references public.requests (id) on delete cascade,
  score           smallint not null check (score between 0 and 100),
  reasons         jsonb not null check (jsonb_typeof(reasons) = 'array' and jsonb_array_length(reasons) > 0),
  model           text not null,
  model_version   text not null,
  prompt_version  text not null,
  inputs_sha256   text not null,
  created_at      timestamptz not null default now()
);

create trigger scores_append_only before update or delete on public.scores
  for each row execute function private.forbid_change();

create table public.reviews (
  id           uuid primary key default gen_random_uuid(),
  request_id   uuid not null references public.requests (id) on delete cascade,
  reviewer_id  uuid not null references public.members (id),
  decision     public.review_decision not null,
  reason       text not null check (length(reason) between 10 and 2000),
  created_at   timestamptz not null default now()
);

create trigger reviews_append_only before update or delete on public.reviews
  for each row execute function private.forbid_change();

create table public.appeals (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references public.requests (id) on delete cascade,
  member_id   uuid not null references public.members (id),
  reason      text not null check (length(reason) between 10 and 2000),
  status      public.appeal_status not null default 'open',
  decided_by  uuid references public.members (id),
  decided_at  timestamptz,
  created_at  timestamptz not null default now()
);

create unique index appeals_one_open on public.appeals (request_id) where status = 'open';

create table private.fraud_signals (
  id          bigint generated always as identity primary key,
  request_id  uuid not null references public.requests (id) on delete cascade,
  kind        text not null,
  severity    text not null check (severity in ('low', 'high')),
  detail      jsonb not null default '{}',
  resolved_at timestamptz,
  created_at  timestamptz not null default now()
);

-- Statuses moved by the trigger above need the reviews table to exist first.
create trigger requests_status_guard before insert or update of status on public.requests
  for each row execute function private.guard_request_status();
create trigger requests_status_log_insert after insert on public.requests
  for each row execute function private.log_request_status();
create trigger requests_status_log_update after update of status on public.requests
  for each row when (old.status is distinct from new.status)
  execute function private.log_request_status();

-- --- functions: the only ways a request changes status ------------------------

-- Member submits a draft (or resubmits after more evidence).
create function public.submit_request(p_request uuid) returns public.request_status
language plpgsql security definer set search_path = '' as $$
declare
  r        public.requests;
  s        public.fund_settings;
  v_start  date;
  v_asset  public.covered_assets;
begin
  select * into r from public.requests where id = p_request for update;
  if r.id is null or r.member_id <> auth.uid() then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if not public.is_active_member() then
    raise exception 'verify your identity before submitting a request' using errcode = '42501';
  end if;
  if r.status not in ('draft', 'needs_evidence') then
    raise exception 'only drafts and requests needing evidence can be submitted' using errcode = '23514';
  end if;
  if r.payee_id is null then
    raise exception 'name who should be paid (a shop, lender or seller)' using errcode = '23514';
  end if;
  if not exists (select 1 from public.evidence where request_id = r.id) then
    raise exception 'add at least one piece of evidence' using errcode = '23514';
  end if;
  if exists (select 1 from public.evidence where request_id = r.id and redaction_status <> 'confirmed') then
    raise exception 'check and confirm the redacted copy of every piece of evidence' using errcode = '23514';
  end if;

  -- Pool eligibility: cover must have started, and the asset must have been
  -- registered, at least `waiting_days` before the incident. Stops joining
  -- the day after a crash.
  if r.funding in ('pool', 'both') then
    select * into s from public.fund_settings where fund = public.fund_for_kind(r.kind);
    if not r.kind = any (s.kinds) then
      raise exception 'the community pool does not cover % requests yet', r.kind using errcode = '23514';
    end if;
    if r.amount_cents > s.max_request_cents then
      raise exception 'the pool pays at most % cents per request', s.max_request_cents using errcode = '23514';
    end if;
    v_start := public.coverage_started_on(r.member_id);
    if v_start is null or r.incident_on < v_start + s.waiting_days then
      raise exception 'pool cover starts % days after your first payment; ask your people instead', s.waiting_days
        using errcode = '23514';
    end if;
    if public.fund_for_kind(r.kind) = 'protection' then
      select * into v_asset from public.covered_assets
      where id = r.asset_id and member_id = r.member_id and removed_on is null;
      if v_asset.id is null or r.incident_on < v_asset.registered_on + s.waiting_days then
        raise exception 'the vehicle must be registered with Kinfold % days before the incident', s.waiting_days
          using errcode = '23514';
      end if;
    end if;
  end if;

  update public.requests
  set status = 'scoring', submitted_at = coalesce(submitted_at, now())
  where id = r.id;
  return 'scoring';
end $$;

create function public.withdraw_request(p_request uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.requests set status = 'withdrawn'
  where id = p_request and member_id = auth.uid() and status in ('draft', 'needs_evidence', 'open');
  if not found then
    raise exception 'request not found or can no longer be withdrawn' using errcode = 'P0002';
  end if;
end $$;

create function public.confirm_redaction(p_evidence uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.evidence e set redaction_status = 'confirmed'
  from public.requests r
  where e.id = p_evidence and r.id = e.request_id and r.member_id = auth.uid()
    and e.redaction_status = 'auto_done' and e.redacted_path is not null;
  if not found then
    raise exception 'evidence not found or not ready to confirm' using errcode = 'P0002';
  end if;
end $$;

-- Service role only: the scoring edge function records a score and routes the
-- request. A low score asks for evidence; an open high-severity fraud signal
-- sends it to a person. Nothing here can refuse.
create function public.record_score(
  p_request uuid, p_score smallint, p_reasons jsonb,
  p_model text, p_model_version text, p_prompt_version text, p_inputs_sha256 text
) returns public.request_status
language plpgsql security definer set search_path = '' as $$
declare
  r       public.requests;
  v_min   smallint;
  v_next  public.request_status;
begin
  select * into r from public.requests where id = p_request for update;
  if r.status <> 'scoring' then
    raise exception 'request is not waiting for a score' using errcode = '23514';
  end if;

  insert into public.scores (request_id, score, reasons, model, model_version, prompt_version, inputs_sha256)
  values (p_request, p_score, p_reasons, p_model, p_model_version, p_prompt_version, p_inputs_sha256);

  select coalesce(min_score, 70) into v_min
  from public.fund_settings where fund = public.fund_for_kind(r.kind);

  v_next := case
    when exists (select 1 from private.fraud_signals
                 where request_id = p_request and severity = 'high' and resolved_at is null) then 'in_review'
    when p_score < v_min then 'needs_evidence'
    else 'open'
  end;

  update public.requests set status = v_next, current_score = p_score where id = p_request;
  return v_next;
end $$;

-- Reviewers decide requests sent to a person. A reviewer can't review their own
-- request or one from their own region (anti-collusion), and every decision is
-- written down with a reason and audit-logged.
create function public.record_review(p_request uuid, p_decision public.review_decision, p_reason text)
returns public.request_status
language plpgsql security definer set search_path = '' as $$
declare
  r       public.requests;
  v_me    public.members;
  v_next  public.request_status;
begin
  if not public.has_role('reviewer') then
    raise exception 'reviewers only' using errcode = '42501';
  end if;
  select * into r from public.requests where id = p_request for update;
  select * into v_me from public.members where id = auth.uid();
  if r.member_id = v_me.id then
    raise exception 'you cannot review your own request' using errcode = '42501';
  end if;
  if (select region from public.members where id = r.member_id) = v_me.region then
    raise exception 'requests are reviewed by someone outside the member''s region' using errcode = '42501';
  end if;
  if r.status not in ('in_review', 'needs_evidence', 'open', 'funded', 'refused') then
    raise exception 'request is not reviewable in status %', r.status using errcode = '23514';
  end if;

  insert into public.reviews (request_id, reviewer_id, decision, reason)
  values (p_request, v_me.id, p_decision, p_reason);
  perform private.audit('review.' || p_decision, 'requests', p_request, jsonb_build_object('reason', p_reason));

  v_next := case p_decision
    when 'approve' then 'open'
    when 'needs_evidence' then 'needs_evidence'
    when 'refuse' then 'refused'
    when 'escalate' then 'in_review'
  end;

  -- Reaching some targets takes two steps (e.g. open -> in_review -> refused).
  if r.status <> 'in_review' and v_next <> r.status
     and not exists (select 1 from public.request_transitions where from_status = r.status and to_status = v_next) then
    update public.requests set status = 'in_review' where id = p_request;
  end if;
  if v_next <> (select status from public.requests where id = p_request) then
    update public.requests set status = v_next where id = p_request;
  end if;
  -- Approving a request whose pledges already cover it (e.g. a funded request
  -- sent back for review) returns it to funded; left 'open' it could never
  -- take another pledge or pool grant, nor reach payout.
  if v_next = 'open' then
    update public.requests set status = 'funded'
    where id = p_request and status = 'open'
      and (select coalesce(sum(c.amount_cents), 0) from public.contributions c
           where c.request_id = p_request and c.status in ('pledged', 'captured')) >= amount_cents;
  end if;
  return (select status from public.requests where id = p_request);
end $$;

create function public.file_appeal(p_request uuid, p_reason text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not exists (select 1 from public.requests where id = p_request and member_id = auth.uid() and status = 'refused') then
    raise exception 'only a refused request of yours can be appealed' using errcode = '42501';
  end if;
  insert into public.appeals (request_id, member_id, reason) values (p_request, auth.uid(), p_reason)
  returning id into v_id;
  return v_id;
end $$;

-- Panel members decide appeals. Upholding sends the request back to review.
create function public.decide_appeal(p_appeal uuid, p_uphold boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
  a public.appeals;
begin
  if not public.has_role('panel') then
    raise exception 'appeal panel only' using errcode = '42501';
  end if;
  select * into a from public.appeals where id = p_appeal and status = 'open' for update;
  if a.id is null then
    raise exception 'appeal not found or already decided' using errcode = 'P0002';
  end if;
  if a.member_id = auth.uid() then
    raise exception 'you cannot decide your own appeal' using errcode = '42501';
  end if;
  update public.appeals
  set status = case when p_uphold then 'upheld'::public.appeal_status else 'denied' end,
      decided_by = auth.uid(), decided_at = now()
  where id = p_appeal;
  if p_uphold then
    update public.requests set status = 'in_review' where id = a.request_id;
  end if;
  perform private.audit(case when p_uphold then 'appeal.upheld' else 'appeal.denied' end,
                        'appeals', p_appeal);
end $$;

-- --- the request board --------------------------------------------------------
-- Owned by postgres, so it reads past RLS deliberately and exposes only safe
-- columns: the redacted summary, kind, amount, score, state and week. Visible to
-- signed-in, verified members only; quasi-identifiers (exact date, town) never
-- appear. Public aggregate numbers live in `public_stats` (funding migration).

create view public.board_requests with (security_barrier) as
select
  r.id,
  r.kind,
  r.public_summary,
  r.amount_cents,
  r.current_score,
  r.status,
  m.region,
  date_trunc('week', r.submitted_at)::date as week_of
from public.requests r
join public.members m on m.id = r.member_id
where r.status in ('open', 'funded', 'paid')
  and r.funding in ('pool', 'both')
  and r.public_summary is not null
  and public.is_active_member();

-- --- row-level security and grants ---------------------------------------------

alter table public.payees enable row level security;
alter table public.requests enable row level security;
alter table public.request_transitions enable row level security;
alter table public.request_events enable row level security;
alter table public.evidence enable row level security;
alter table public.scores enable row level security;
alter table public.reviews enable row level security;
alter table public.appeals enable row level security;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;

-- Re-grant what the previous migration granted (the blanket revoke above clears it).
grant select on public.fund_settings, public.subscription_formulas to anon, authenticated;
grant select, insert (id, display_name, region), update (display_name) on public.members to authenticated;
grant select on public.member_roles, public.income_verifications, public.subscriptions,
  public.subscription_payments to authenticated;
grant select, insert, update, delete on public.allocation_preferences to authenticated;
grant select, insert (member_id, kind, description, value_cents), update (description, removed_on)
  on public.covered_assets to authenticated;

create policy "verified payees are visible" on public.payees for select to authenticated
  using (status = 'verified' or proposed_by = auth.uid());
create policy "members propose payees" on public.payees for insert to authenticated
  with check (proposed_by = auth.uid() and status = 'pending');
grant select (id, kind, legal_name, region, status), insert (kind, legal_name, region, proposed_by)
  on public.payees to authenticated;

create policy "transitions are public" on public.request_transitions for select using (true);
grant select on public.request_transitions to authenticated;

create policy "members read their requests" on public.requests for select to authenticated
  using (member_id = auth.uid());
create policy "reviewers read requests needing a person" on public.requests for select to authenticated
  using (public.has_role('reviewer') and member_id <> auth.uid()
         and status in ('in_review', 'needs_evidence', 'refused'));
create policy "members create drafts" on public.requests for insert to authenticated
  with check (member_id = auth.uid() and status = 'draft');
create policy "members edit drafts" on public.requests for update to authenticated
  using (member_id = auth.uid() and status = 'draft')
  with check (member_id = auth.uid() and status = 'draft');
grant select on public.requests to authenticated;
grant insert (member_id, kind, funding, title, description, amount_cents, incident_on, asset_id, payee_id),
      update (kind, funding, title, description, amount_cents, incident_on, asset_id, payee_id)
  on public.requests to authenticated;

create policy "members read their request history" on public.request_events for select to authenticated
  using (exists (select 1 from public.requests r where r.id = request_id and r.member_id = auth.uid()));
grant select on public.request_events to authenticated;

create policy "members read their evidence" on public.evidence for select to authenticated
  using (exists (select 1 from public.requests r where r.id = request_id and r.member_id = auth.uid()));
create policy "members remove evidence before scoring" on public.evidence for delete to authenticated
  using (exists (select 1 from public.requests r
                 where r.id = request_id and r.member_id = auth.uid()
                   and r.status in ('draft', 'needs_evidence')));
create policy "members add evidence before scoring" on public.evidence for insert to authenticated
  with check (exists (select 1 from public.requests r
                      where r.id = request_id and r.member_id = auth.uid()
                        and r.status in ('draft', 'needs_evidence'))
              and redaction_status = 'pending' and redacted_path is null
              and original_path like auth.uid()::text || '/%');
grant select, insert (request_id, kind, original_path, sha256, captured_in_app), delete
  on public.evidence to authenticated;

create policy "members read scores on their requests" on public.scores for select to authenticated
  using (exists (select 1 from public.requests r where r.id = request_id and r.member_id = auth.uid())
         or public.has_role('reviewer'));
grant select on public.scores to authenticated;

create policy "members read reviews of their requests" on public.reviews for select to authenticated
  using (exists (select 1 from public.requests r where r.id = request_id and r.member_id = auth.uid())
         or public.has_role('panel'));
grant select on public.reviews to authenticated;

create policy "members read their appeals" on public.appeals for select to authenticated
  using (member_id = auth.uid() or public.has_role('panel'));
grant select on public.appeals to authenticated;

grant select on public.board_requests to authenticated;

grant execute on function
  public.has_role(public.member_role), public.is_active_member(),
  public.subscription_amount(bigint, integer), public.coverage_started_on(uuid),
  public.fund_for_kind(public.request_kind),
  public.submit_request(uuid), public.withdraw_request(uuid), public.confirm_redaction(uuid),
  public.record_review(uuid, public.review_decision, text),
  public.file_appeal(uuid, text), public.decide_appeal(uuid, boolean)
to authenticated;
grant execute on function public.subscription_amount(bigint, integer) to anon;
-- record_score is service-role only: no grant to authenticated.

-- --- storage ------------------------------------------------------------------

insert into storage.buckets (id, name, public) values
  ('evidence-original', 'evidence-original', false),
  ('evidence-redacted', 'evidence-redacted', false)
on conflict (id) do nothing;

-- Members upload originals into their own folder and can read them back.
-- Nobody else reads originals through the API: reviewers get short-lived signed
-- URLs from an edge function that writes to the audit log.
create policy "members upload their originals" on storage.objects for insert to authenticated
  with check (bucket_id = 'evidence-original' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "members read their originals" on storage.objects for select to authenticated
  using (bucket_id = 'evidence-original' and (storage.foldername(name))[1] = auth.uid()::text);

-- Redacted copies: the owner, plus verified members once the request is on the board.
create policy "redacted evidence on the board" on storage.objects for select to authenticated
  using (bucket_id = 'evidence-redacted' and exists (
    select 1 from public.evidence e
    join public.requests r on r.id = e.request_id
    where e.redacted_path = storage.objects.name
      and (r.member_id = auth.uid()
           or (e.redaction_status = 'confirmed' and r.id in (select id from public.board_requests)))
  ));
