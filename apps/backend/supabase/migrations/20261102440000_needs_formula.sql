-- Applicants for the Home Fund are ranked by a published needs formula (design.md:
-- the same evidence score as every other request PLUS need, readiness and
-- reliability — rent paid on time, family loan repayments; no prohibited basis
-- under 12 CFR 1002.5). The weights live in a versioned table so the formula
-- can move with the Fund's fee economics and be audited annually, and every
-- applicant record logs the version and an inputs hash, so a published score
-- can be re-derived at the fairness audit — a score nobody can re-derive
-- cannot be defended at the panel.

create table public.needs_formulas (
  version         integer primary key,
  need_bps        integer not null check (need_bps >= 0),
  readiness_bps   integer not null check (readiness_bps >= 0),
  reliability_bps integer not null check (reliability_bps >= 0),
  check (need_bps + readiness_bps + reliability_bps = 10000),
  effective_from  date not null
);

create policy "needs formulas are published" on public.needs_formulas for select using (true);

-- v1 weights: need half the weight (the Fund is a charity for need), readiness
-- and reliability a quarter each. Local stand-ins pending the annual fairness
-- audit, like every other design target.
insert into public.needs_formulas values (1, 5000, 2500, 2500, '2026-01-01');

-- One applicant record per request per formula version. Components are banded
-- points (0..100), never raw hardship: hardship details stay private, and the
-- board will only ever read the score. The inputs hash is logged so the score
-- is re-derivable; the rows are append-only, so a formula change never
-- rewrites an applicant's past ranking.
create table public.needs_records (
  id                uuid primary key default gen_random_uuid(),
  request_id        uuid not null references public.requests (id) on delete cascade,
  formula_version   integer not null references public.needs_formulas (version),
  need              smallint not null check (need between 0 and 100),
  readiness         smallint not null check (readiness between 0 and 100),
  reliability       smallint not null check (reliability between 0 and 100),
  score             smallint not null check (score between 0 and 100),
  inputs_sha256     text not null,
  created_at        timestamptz not null default now(),
  unique (request_id, formula_version)
);

create trigger needs_records_append_only before update or delete on public.needs_records
  for each row execute function private.forbid_change();

-- The newest effective version decides the weights, the same way dues pick
-- their formula version by effective date.
create function public.needs_formula_version() returns integer
language sql stable security definer set search_path = '' as $$
  select coalesce((select max(version) from public.needs_formulas
                   where effective_from <= current_date), 0);
$$;

-- What the ranking currently reads for a request; null until ranked.
create function public.needs_score(p_request uuid) returns smallint
language sql view security definer set search_path = '' as $$
  select score from public.needs_records
  where request_id = p_request
  order by formula_version desc, created_at desc
  limit 1;
$$;

-- Service only: rank a scored Home Fund applicant. A replay at the same
-- version answers with the score already recorded rather than writing a second
-- row. Components are handed in by the reviewer or the cron that computed them
-- from a member's reliability record — the Fund's ranking never reads earnings.
create function public.record_needs(
  p_request uuid, p_need smallint, p_readiness smallint, p_reliability smallint,
  p_inputs_sha256 text
) returns smallint language plpgsql security definer set search_path = '' as $$
declare
  r        public.requests;
  f        public.needs_formulas;
  v_score  smallint;
begin
  if not private.is_service() then
    raise exception 'applicants are ranked by the Fund''s own service path' using errcode = '42501';
  end if;
  select * into r from public.requests where id = p_request for update;
  if r.status not in ('open', 'in_review') then
    raise exception 'a score is needed before an applicant is ranked' using errcode = '23514';
  end if;
  if public.fund_for_kind(r.kind) <> 'home_fund' then
    raise exception 'only Home Fund applicants get a needs ranking' using errcode = '23514';
  end if;
  if p_inputs_sha256 is null or p_inputs_sha256 = '' then
    raise exception 'a ranking logs the inputs it was computed from' using errcode = '23514';
  end if;
  select * into f from public.needs_formulas
  where effective_from <= current_date
  order by version desc
  limit 1;
  if f.version is null then
    raise exception 'no needs formula is effective' using errcode = '23514';
  end if;
  if exists (select 1 from public.needs_records
             where request_id = p_request and formula_version = f.version) then
    return public.needs_score(p_request);
  end if;
  v_score := ((p_need * f.need_bps + p_readiness * f.readiness_bps
               + p_reliability * f.reliability_bps) + 5000) / 10000;
  insert into public.needs_records
    (request_id, formula_version, need, readiness, reliability, score, inputs_sha256)
  values (p_request, f.version, p_need, p_readiness, p_reliability, v_score, p_inputs_sha256);
  perform private.audit('needs.recorded', 'needs_records', null,
    jsonb_build_object('request_id', p_request, 'formula_version', f.version,
                       'inputs_sha256', p_inputs_sha256));
  return v_score;
end $$;

alter table public.needs_records enable row level security;

revoke all on public.needs_records from public, anon, authenticated;
revoke all from function public.needs_formula_version();
revoke all from function public.needs_formula_version() to public, anon;
grant execute on function public.needs_formula_version() to authenticated, service_role;
revoke all from function public.needs_score(uuid);
revoke all from function public.needs_score(uuid) to public, anon;
grant execute on function public.needs_score(uuid) to authenticated, service_role;

-- Requesters and the reviewers they may review read the ranking.
create policy "owners and reviewers read the ranking" on public.needs_records for select to authenticated
  using (exists (select 1 from public.requests r where r.id = request_id
                 and (r.member_id = auth.uid() or private.may_review(request_id, auth.uid()))));

grant select on public.needs_records to authenticated;
grant select, insert on public.needs_records to service_role;
grant execute on function public.record_needs(uuid, smallint, smallint, smallint, text) to service_role;
