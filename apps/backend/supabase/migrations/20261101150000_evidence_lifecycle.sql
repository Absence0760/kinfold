-- Evidence lifecycle and "other money for the same damage": closes gaps found
-- building the web request flow (roadmap step 1c).
--
--   * the redaction pipeline gets its database affordance: the service writes
--     the redacted copy (auto_done) and can re-run over a rejected one; the
--     member can reject a bad redaction;
--   * the service writes a request's public summary; any change clears the
--     member's confirmation (the existing trigger), and the member can ask for
--     a different one with a note the service can act on;
--   * money covering the same damage through other sources (insurance
--     recoveries, FEMA/SBA/state/charity, the member's own cover) is recorded
--     in request_recoveries: append-only, subtracted from pledge caps and pool
--     needs, and never counted as money Kinfold captured (funding, payout caps
--     and refunds still look only at pledges and payouts);
--   * deleting an evidence row queues its files for the service to delete: a
--     client delete policy can't work once the row is gone (the web app
--     removes the row first), and the queue can't race with it.

-- --- 1. other money for the same damage ----------------------------------------

create type public.recovery_source as enum (
  'own_cover', 'insurance', 'fema', 'sba', 'state', 'charity', 'other'
);

create table public.request_recoveries (
  id           uuid primary key default gen_random_uuid(),
  request_id   uuid not null references public.requests (id) on delete cascade,
  source       public.recovery_source not null,
  amount_cents bigint not null check (amount_cents > 0),
  recovered_on date not null,
  note         text check (note is null or length(note) <= 500),
  partner_ref  text unique,
  verified_at  timestamptz,
  recorded_by  uuid references public.members (id),
  recorded_at  timestamptz not null default now(),
  check ((verified_at is not null) = (partner_ref is not null))
);

create index request_recoveries_request on public.request_recoveries (request_id);

create trigger request_recoveries_append_only before update or delete
  on public.request_recoveries for each row execute function private.forbid_change();

-- What the pledge cap and the pool run subtract. Internal only: recovered money
-- is money that moved outside Kinfold, so nothing else reads it as funding.
create function private.recovered_cents(p_request uuid) returns bigint
language sql stable set search_path = '' as $$
  select coalesce(sum(amount_cents), 0) from public.request_recoveries
  where request_id = p_request;
$$;

-- The member's declaration at request time and the recovery report later, both
-- owner-written; the service may record partner money directly.
create function public.record_recovery(
  p_request uuid, p_source public.recovery_source, p_amount_cents bigint,
  p_on date, p_note text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if p_amount_cents <= 0 then
    raise exception 'money covered must be positive' using errcode = '23514';
  end if;
  perform 1 from public.requests where id = p_request for update;
  if not found then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if not (private.is_service()
          or (select member_id from public.requests where id = p_request) = auth.uid()) then
    raise exception 'money for the same damage is recorded by the requester or the service'
      using errcode = '42501';
  end if;
  insert into public.request_recoveries
    (request_id, source, amount_cents, recovered_on, note, recorded_by)
  values (p_request, p_source, p_amount_cents, p_on, p_note,
          case when private.is_service() then null else auth.uid() end)
  returning id into v_id;
  perform private.audit('recovery.recorded', 'request_recoveries', v_id,
    jsonb_build_object('request_id', p_request, 'source', p_source,
                       'amount_cents', p_amount_cents));
  return v_id;
end $$;

-- Service only, after the partner confirms the money actually moved.
create function public.verify_recovery(p_recovery uuid, p_partner_ref text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_service() then
    raise exception 'verification is done by the service' using errcode = '42501';
  end if;
  if p_partner_ref is null or p_partner_ref = '' then
    raise exception 'verification needs the partner''s reference' using errcode = '23514';
  end if;
  -- Webhook retries: the same verification twice is a no-op.
  if exists (select 1 from public.request_recoveries where id = p_recovery
             and partner_ref = p_partner_ref) then
    return;
  end if;
  update public.request_recoveries
  set partner_ref = p_partner_ref, verified_at = now()
  where id = p_recovery and partner_ref is null;
  if not found then
    raise exception 'recovery not found or already verified' using errcode = 'P0002';
  end if;
  perform private.audit('recovery.verified', 'request_recoveries', p_recovery);
end $$;

-- Pledge cap now nets out other money for the same damage (rest as in
-- board_privacy.sql).
create or replace function public.pledge(p_request uuid, p_amount_cents bigint,
  p_source public.contribution_source)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  r          public.requests;
  v_left     bigint;
  v_loan     uuid;
  v_id       uuid;
  v_invited  boolean;
begin
  if p_source = 'pool' then
    raise exception 'pool money is allocated by the pool run, not pledged' using errcode = '42501';
  end if;
  select * into r from public.requests where id = p_request for update;
  if r.id is null then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if r.member_id = auth.uid() then
    raise exception 'you cannot pledge to your own request' using errcode = '42501';
  end if;
  if r.status <> 'open' then
    raise exception 'this request is not taking pledges' using errcode = '23514';
  end if;

  v_invited := public.is_supporter(p_request);
  -- Strangers give only to requests they can see on the board.
  if p_source = 'gift' and not v_invited
     and not (public.on_board(r) and public.is_active_member()) then
    raise exception 'ask the member for an invite to give to this request' using errcode = '42501';
  end if;
  -- Loans only between people who know each other. A loan from a stranger on
  -- the board would be regulated lending, so it isn't offered.
  if p_source = 'loan' and not (v_invited and public.is_active_member()) then
    raise exception 'only invited, verified family and friends can lend' using errcode = '42501';
  end if;
  -- Verification can run while the request is scored; money waits for it.
  if not exists (select 1 from public.payees where id = r.payee_id and status = 'verified') then
    raise exception 'pledges open once the request''s payee is verified' using errcode = '23514';
  end if;

  v_left := r.amount_cents - private.raised_cents(p_request) - private.recovered_cents(p_request);
  if p_amount_cents <= 0 or p_amount_cents > v_left then
    raise exception 'pledge must be between 1 and % cents', v_left using errcode = '23514';
  end if;

  if p_source = 'loan' then
    insert into public.family_loans (request_id, borrower_id, lender_id, principal_cents)
    values (p_request, r.member_id, auth.uid(), p_amount_cents)
    returning id into v_loan;
  end if;

  insert into public.contributions (request_id, contributor_id, source, amount_cents, loan_id)
  values (p_request, auth.uid(), p_source, p_amount_cents, v_loan)
  returning id into v_id;
  return v_id;
end $$;

-- The pool run subtracts other money for the same damage from need (rest as in
-- hardening.sql, bands-v1).
create or replace function public.run_pool_allocation(p_fund public.fund, p_available_cents bigint)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  s           public.fund_settings;
  v_run       uuid;
  v_reserve   bigint;
  v_left      bigint;
  v_band      smallint;
  v_total     bigint;
  v_band_left bigint;
  v_alloc     uuid;
  v_grant     bigint;
  c           record;
begin
  select * into s from public.fund_settings where fund = p_fund;
  if s.fund is null then
    raise exception 'no pooled fund %', p_fund using errcode = '22023';
  end if;
  if p_available_cents < 0 then
    raise exception 'available balance cannot be negative' using errcode = '22023';
  end if;

  v_reserve := p_available_cents * s.reserve_bps / 10000;
  v_left := p_available_cents - v_reserve;

  insert into public.pool_runs (fund, available_cents, reserve_cents, settings, algorithm_version)
  values (p_fund, p_available_cents, v_reserve, to_jsonb(s), 'bands-v1')
  returning id into v_run;

  perform 1 from public.requests r
  where r.status = 'open' and r.funding in ('pool', 'both') and public.fund_for_kind(r.kind) = p_fund
  for update;

  drop table if exists pg_temp.candidates;
  create temporary table candidates on commit drop as
  select r.id, r.current_score as score,
         ((r.current_score / s.band_size) * s.band_size)::smallint as band,
         r.amount_cents - private.raised_cents(r.id) - private.recovered_cents(r.id) as need
  from public.requests r
  join public.payees p on p.id = r.payee_id and p.status = 'verified'  -- waits for a verified payee
  where r.status = 'open'
    and r.funding in ('pool', 'both')
    and public.fund_for_kind(r.kind) = p_fund
    and r.current_score >= s.min_score;

  delete from pg_temp.candidates where need <= 0;

  for v_band in select distinct band from pg_temp.candidates order by band desc loop
    exit when v_left <= 0;
    select sum(need) into v_total from pg_temp.candidates where band = v_band;
    v_band_left := v_left;
    for c in select * from pg_temp.candidates where band = v_band order by id loop
      v_grant := case when v_band_left >= v_total then c.need else c.need * v_band_left / v_total end;
      insert into public.pool_allocations (run_id, request_id, score, band, need_cents, grant_cents)
      values (v_run, c.id, c.score, c.band, c.need, v_grant)
      returning id into v_alloc;
      if v_grant > 0 then
        insert into public.contributions (request_id, source, amount_cents, pool_allocation_id)
        values (c.id, 'pool', v_grant, v_alloc);
      end if;
      v_left := v_left - v_grant;
    end loop;
    exit when v_band_left < v_total;
  end loop;

  update public.pool_runs
  set allocated_cents = p_available_cents - v_reserve - v_left
  where id = v_run;
  return v_run;
end $$;

-- --- 2. redaction and summary affordances --------------------------------------

-- Service writes the redacted copy: pending or rejected -> auto_done, so a
-- member's rejection can be re-run. Only while the request is still being
-- prepared (draft or needs_evidence).
create function public.set_redaction_done(p_evidence uuid, p_redacted_path text,
  p_perceptual_hash text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_service() then
    raise exception 'redaction is run by the service' using errcode = '42501';
  end if;
  if p_redacted_path is null or p_redacted_path = '' then
    raise exception 'redaction needs the redacted copy''s path' using errcode = '23514';
  end if;
  update public.evidence e set redaction_status = 'auto_done',
      redacted_path = p_redacted_path,
      perceptual_hash = coalesce(p_perceptual_hash, e.perceptual_hash)
  from public.requests r
  where e.id = p_evidence and r.id = e.request_id
    and r.status in ('draft', 'needs_evidence')
    and e.redaction_status in ('pending', 'rejected');
  if not found then
    raise exception 'evidence not found, not waiting for redaction, or its request was already submitted'
      using errcode = 'P0002';
  end if;
  perform private.audit('evidence.redacted', 'evidence', p_evidence);
end $$;

-- The member says "this redaction is wrong" on their own evidence.
create function public.reject_redaction(p_evidence uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.evidence e set redaction_status = 'rejected'
  from public.requests r
  where e.id = p_evidence and r.id = e.request_id and r.member_id = auth.uid()
    and e.redaction_status = 'auto_done';
  if not found then
    raise exception 'evidence not found or not ready to reject' using errcode = 'P0002';
  end if;
  perform private.audit('evidence.redaction_rejected', 'evidence', p_evidence);
end $$;

-- The service writes or rewrites a request's public summary (the redaction
-- pipeline); the existing trigger clears the member's confirmation.
create function public.set_public_summary(p_request uuid, p_summary text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_service() then
    raise exception 'summaries are written by the redaction service' using errcode = '42501';
  end if;
  update public.requests set public_summary = p_summary where id = p_request;
  if not found then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  perform private.audit('request.summary_written', 'requests', p_request);
end $$;

alter table public.requests
  add column summary_change_note text
    check (summary_change_note is null or length(summary_change_note) between 1 and 1000);

-- The member can't rewrite the summary themselves; they say what's wrong, and
-- the service applies the change through set_public_summary.
create function public.request_summary_change(p_request uuid, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_note is null or p_note = '' then
    raise exception 'tell us what is wrong with the summary' using errcode = '23514';
  end if;
  update public.requests set summary_change_note = p_note
  where id = p_request and member_id = auth.uid() and public_summary is not null;
  if not found then
    raise exception 'request not found, has no summary yet, or is not yours' using errcode = 'P0002';
  end if;
  perform private.audit('request.summary_change_requested', 'requests', p_request);
end $$;

-- --- 3. files queued when evidence rows go -------------------------------------

create table private.evidence_deletions (
  id           bigint generated always as identity primary key,
  bucket       text not null,
  path         text not null,
  created_at   timestamptz not null default now(),
  processed_at timestamptz
);

-- A member removes evidence: the web app deletes the row (its delete policy
-- allows that), and the objects queue for the service to remove. A client
-- storage-delete policy can't cover the case where the row is already gone.
create function private.queue_evidence_deletion() returns trigger
language plpgsql set search_path = '' as $$
begin
  insert into private.evidence_deletions (bucket, path)
  select q.bucket, q.path
  from (values ('evidence-original', old.original_path),
               ('evidence-redacted', old.redacted_path)) q (bucket, path)
  where q.path is not null;
  perform private.audit('evidence.files_queued', 'evidence', old.id);
  return null;
end $$;

create trigger evidence_queue_deletion after delete on public.evidence
  for each row execute function private.queue_evidence_deletion();

-- The service (storage cleanup edge function) reads this, deletes the objects,
-- then marks the entry processed.
create view public.pending_evidence_deletions with (security_barrier) as
select id, bucket, path, created_at
from private.evidence_deletions where processed_at is null;

create function public.mark_evidence_deleted(p_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_service() then
    raise exception 'the service marks file deletions' using errcode = '42501';
  end if;
  update private.evidence_deletions set processed_at = now() where id = p_id;
  if not found then
    raise exception 'deletion entry not found' using errcode = 'P0002';
  end if;
end $$;

-- --- grants ---------------------------------------------------------------------

-- Supabase's default privileges hand the new relations to anon and authenticated;
-- take them back, then grant only what each role needs.
revoke all on public.request_recoveries, private.evidence_deletions,
  public.pending_evidence_deletions from public, anon, authenticated;
revoke all on function
  public.record_recovery(uuid, public.recovery_source, bigint, date, text),
  public.verify_recovery(uuid, text), public.set_redaction_done(uuid, text, text),
  public.reject_redaction(uuid), public.set_public_summary(uuid, text),
  public.request_summary_change(uuid, text), public.mark_evidence_deleted(bigint),
  private.queue_evidence_deletion(), private.recovered_cents(uuid)
from public, anon, authenticated;

create policy "requesters read their recoveries" on public.request_recoveries
  for select to authenticated
  using (exists (select 1 from public.requests r where r.id = request_id and r.member_id = auth.uid()));

grant execute on function
  public.record_recovery(uuid, public.recovery_source, bigint, date, text),
  public.reject_redaction(uuid), public.request_summary_change(uuid, text)
to authenticated;

-- New tables and functions live in this migration, so hardening.sql's blanket
-- service grants don't cover them; state them here.
grant select on public.request_recoveries to authenticated;
grant select, insert on public.request_recoveries to service_role;
grant select, insert, update on private.evidence_deletions to service_role;
grant select on public.pending_evidence_deletions to service_role;
grant execute on function
  public.verify_recovery(uuid, text), public.set_redaction_done(uuid, text, text),
  public.set_public_summary(uuid, text), public.mark_evidence_deleted(bigint),
  public.record_recovery(uuid, public.recovery_source, bigint, date, text)
to service_role;