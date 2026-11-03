-- The Fund's one certified housing counselor (the rest of 3c/3g: design.md's
-- "HUD housing counseling grants" row and its "get the bank's own relief" step).
-- Kinfold never becomes a counselor: it **partners with one** HUD-approved
-- nonprofit agency, certified under 24 CFR part 214, for every applicant and
-- for the ask-for-relief step. Which agency is published data - versioned and
-- effective-dated like every other public rule, so a change of agency is a data
-- change an auditor can watch, and the certification (the approval date and the
-- CFR it is certified under) sits on the row so a page can name the agency and
-- its credential without re-deciding either. The seeded row is a local stand-in
-- pending the Stage 3 agency contract, like every other design target.

create table public.housing_counsel (
  version         integer primary key,
  agency_name     text not null check (agency_name <> ''),
  contact_url     text not null check (contact_url ~ 'https?://.*'),
  hud_approved_on date not null check (hud_approved_on <= current_date),
  certified_under text not null check (certified_under = '24 CFR part 214'),
  effective_from  date not null,
  -- One agency at a time: two rows sharing an effective date would leave two
  -- agencies current at once, which is the "one agency" rule read as data.
  unique (effective_from)
);

-- An agency change is a new row, never an edit of the standing one: the agency
-- that priced an applicant's help stays readable beside that request.
create trigger housing_counsel_append_only before update or delete on public.housing_counsel
  for each row execute function private.forbid_change();

-- v1: a local stand-in for the pilot city's certified agency, approved before it
-- became effective. Kinfold names this agency, so the certification has to be
-- real paper before launch; until then the row says which credential it claims.
insert into public.housing_counsel values
  (1, 'Pilot City Housing Counseling', 'https://pilotcity.example/housing-counseling',
   '2026-01-01', '24 CFR part 214', '2026-01-01');

-- The newest effective version decides which agency the Fund partners with, the
-- same way dues and needs pick their formula version by effective date.
create function public.housing_counsel_version() returns integer
language sql stable security definer set search_path = '' as $$
  select coalesce((select max(version) from public.housing_counsel
                   where effective_from <= current_date), 0);
$$;

-- --- access --------------------------------------------------------------------

alter table public.housing_counsel enable row level security;

-- Which agency the Fund partners with, and the credential behind it, is public:
-- a fairness auditor and a member asking for relief both need to see who was
-- named, and neither the name nor the CFR it is certified under is PII.
create policy "housing counsel is published" on public.housing_counsel for select
  using (true);
grant select on public.housing_counsel to anon, authenticated;

-- New table: hardening.sql's blanket service grants don't cover it; state them.
grant select, insert on public.housing_counsel to service_role;

-- The version door is public too (anon execute): the published page asks the
-- schema which agency is standing rather than deciding it itself, so the same
-- answer a member gets is the answer a fairness auditor gets. The door reads
-- only version numbers - no row, no PII crosses it.
revoke all from function public.housing_counsel_version();
revoke all from function public.housing_counsel_version() to public, anon, authenticated;
grant execute on function public.housing_counsel_version() to anon, authenticated, service_role;