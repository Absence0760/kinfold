-- Members, roles, fund settings, subscriptions and covered assets.
--
-- Conventions for every Kinfold migration:
--   * money is bigint cents, never numeric dollars, never floats;
--   * there is no interest column anywhere, by design (docs/design.md, principle 1);
--   * clients get explicit grants only: Supabase's default "grant all to anon,
--     authenticated" is revoked at the end of each migration;
--   * anything clients must never read through the API lives in `private`;
--   * security definer functions pin `search_path = ''` and qualify every name.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- --- enums --------------------------------------------------------------------

create type public.fund as enum ('protection', 'home_fund', 'people');
create type public.member_status as enum ('pending_verification', 'active', 'suspended', 'closed');
create type public.member_role as enum ('reviewer', 'panel', 'admin');
create type public.asset_kind as enum ('vehicle', 'home');
create type public.request_kind as enum (
  'car_damage', 'car_deductible', 'home_repair', 'down_payment', 'mortgage_gap', 'loan_payoff'
);

-- --- fund settings ------------------------------------------------------------
-- One row per pooled fund. The allocation and eligibility rules read from here,
-- so a rule change is a data change with a history row, not a code change.

create table public.fund_settings (
  fund             public.fund primary key check (fund <> 'people'),
  min_score        smallint not null check (min_score between 0 and 100),
  band_size        smallint not null check (band_size between 1 and 100),
  reserve_bps      integer  not null check (reserve_bps between 0 and 10000),
  waiting_days     integer  not null check (waiting_days >= 0),
  max_request_cents bigint  not null check (max_request_cents > 0),
  kinds            public.request_kind[] not null,
  updated_at       timestamptz not null default now()
);

insert into public.fund_settings values
  ('protection', 70, 10, 2000, 60, 1000000, '{car_damage,car_deductible}', now()),
  ('home_fund',  70, 10, 1000, 90, 5000000, '{home_repair,down_payment,mortgage_gap,loan_payoff}', now());

create table private.fund_settings_history (
  id         bigint generated always as identity primary key,
  fund       public.fund not null,
  old_row    jsonb not null,
  changed_at timestamptz not null default now(),
  changed_by uuid
);

create function private.log_fund_settings_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into private.fund_settings_history (fund, old_row, changed_by)
  values (old.fund, to_jsonb(old), auth.uid());
  new.updated_at := now();
  return new;
end $$;

create trigger fund_settings_history before update on public.fund_settings
  for each row execute function private.log_fund_settings_change();

-- --- members ------------------------------------------------------------------

create table public.members (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text not null check (length(display_name) between 1 and 80),
  region        text not null check (region ~ '^[A-Z]{2}$'),  -- US state code
  status        public.member_status not null default 'pending_verification',
  joined_at     timestamptz not null default now()
);

-- Identity verification is done by a KYC vendor. Kinfold keeps the vendor's
-- reference and the outcome, never the documents.
create table private.member_identity (
  member_id     uuid primary key references public.members (id) on delete cascade,
  provider      text not null,
  provider_ref  text not null,
  verified_at   timestamptz not null default now()
);

create table public.member_roles (
  member_id  uuid not null references public.members (id) on delete cascade,
  role       public.member_role not null,
  granted_at timestamptz not null default now(),
  primary key (member_id, role)
);

create function public.has_role(p_role public.member_role) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.member_roles where member_id = auth.uid() and role = p_role
  );
$$;

create function public.is_active_member() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.members where id = auth.uid() and status = 'active');
$$;

-- --- audit log ----------------------------------------------------------------
-- Append-only record of sensitive actions: reviews, refusals, reads of original
-- (unredacted) evidence, payouts. Written only from security definer functions.

create table private.audit_log (
  id          bigint generated always as identity primary key,
  actor       uuid,
  action      text not null,
  target      text not null,
  target_id   uuid,
  detail      jsonb not null default '{}',
  at          timestamptz not null default now()
);

create function private.forbid_change() returns trigger
language plpgsql as $$
begin
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end $$;

create trigger audit_log_append_only before update or delete on private.audit_log
  for each row execute function private.forbid_change();

create function private.audit(p_action text, p_target text, p_target_id uuid, p_detail jsonb default '{}')
returns void language sql security definer set search_path = '' as $$
  insert into private.audit_log (actor, action, target, target_id, detail)
  values (auth.uid(), p_action, p_target, p_target_id, p_detail);
$$;

-- --- income and subscriptions -------------------------------------------------

create type public.income_method as enum ('bank_link', 'tax_return', 'self_attested');

create table public.income_verifications (
  id                    uuid primary key default gen_random_uuid(),
  member_id             uuid not null references public.members (id) on delete cascade,
  method                public.income_method not null,
  monthly_income_cents  bigint not null check (monthly_income_cents >= 0),
  provider_ref          text,
  verified_at           timestamptz not null default now(),
  expires_at            timestamptz not null default now() + interval '1 year'
);

-- The published subscription formula. A new version is a new row; old rows stay
-- so every subscription can say which formula priced it.
create table public.subscription_formulas (
  version              integer primary key,
  floor_income_cents   bigint  not null check (floor_income_cents >= 0),
  rate_bps             integer not null check (rate_bps between 0 and 10000),
  cap_cents            bigint  not null check (cap_cents >= 0),
  core_share_bps       integer not null check (core_share_bps between 0 and 10000),
  effective_from       date not null
);

-- v1 design targets, pending actuarial review: nothing below $1,500/month of
-- take-home pay, 1% above it, capped at $60/month; 80% always goes to the
-- protection pool and the member directs the other 20%.
insert into public.subscription_formulas values (1, 150000, 100, 6000, 8000, '2026-01-01');

create function public.subscription_amount(p_monthly_income_cents bigint, p_version integer default null)
returns bigint language sql stable set search_path = '' as $$
  select case
    when p_monthly_income_cents < f.floor_income_cents then 0
    else least(f.cap_cents, (p_monthly_income_cents * f.rate_bps) / 10000)
  end
  from public.subscription_formulas f
  where f.version = coalesce(
    p_version,
    (select max(version) from public.subscription_formulas where effective_from <= current_date)
  );
$$;

create table public.subscriptions (
  id                      uuid primary key default gen_random_uuid(),
  member_id               uuid not null references public.members (id) on delete cascade,
  formula_version         integer not null references public.subscription_formulas (version),
  income_verification_id  uuid not null references public.income_verifications (id),
  monthly_cents           bigint not null check (monthly_cents >= 0),
  starts_on               date not null default current_date,
  ends_on                 date,
  check (ends_on is null or ends_on >= starts_on)
);

create unique index subscriptions_one_active on public.subscriptions (member_id) where ends_on is null;

create type public.payment_status as enum ('pending', 'captured', 'failed', 'refunded');

create table public.subscription_payments (
  id               uuid primary key default gen_random_uuid(),
  subscription_id  uuid not null references public.subscriptions (id),
  member_id        uuid not null references public.members (id),
  period           date not null check (extract(day from period) = 1),
  amount_cents     bigint not null check (amount_cents >= 0),
  status           public.payment_status not null default 'pending',
  partner_ref      text unique,
  captured_at      timestamptz,
  unique (subscription_id, period),
  check ((status = 'captured') = (captured_at is not null) or status = 'refunded')
);

-- Cover starts with the first captured payment; a $0 subscription counts once
-- its first period is recorded as captured.
-- Security invoker: a client sees only their own payments through RLS, so it
-- can't learn when another member's cover began. Definer callers (submit_request)
-- read past RLS as the owner.
create function public.coverage_started_on(p_member uuid) returns date
language sql stable security invoker set search_path = '' as $$
  select min(captured_at)::date from public.subscription_payments
  where member_id = p_member and status = 'captured';
$$;

create type public.allocation_target as enum ('car_damage', 'home_help', 'highest_score');

-- How a member splits the directable share of their subscription.
create table public.allocation_preferences (
  member_id   uuid not null references public.members (id) on delete cascade,
  target      public.allocation_target not null,
  weight_pct  smallint not null check (weight_pct between 1 and 100),
  primary key (member_id, target)
);

create function private.check_allocation_total() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_member uuid := coalesce(new.member_id, old.member_id);
  v_total  integer;
begin
  select coalesce(sum(weight_pct), 0) into v_total
  from public.allocation_preferences where member_id = v_member;
  if v_total not in (0, 100) then
    raise exception 'allocation weights must add up to 100 (got %)', v_total using errcode = '23514';
  end if;
  return null;
end $$;

create constraint trigger allocation_total after insert or update or delete on public.allocation_preferences
  deferrable initially deferred for each row execute function private.check_allocation_total();

-- --- covered assets -----------------------------------------------------------

create table public.covered_assets (
  id             uuid primary key default gen_random_uuid(),
  member_id      uuid not null references public.members (id) on delete cascade,
  kind           public.asset_kind not null,
  description    text not null check (length(description) between 1 and 200),
  value_cents    bigint not null check (value_cents > 0),
  registered_on  date not null default current_date,
  verified_at    timestamptz,
  removed_on     date
);

-- --- row-level security and grants ---------------------------------------------

alter table public.fund_settings enable row level security;
alter table public.members enable row level security;
alter table public.member_roles enable row level security;
alter table public.income_verifications enable row level security;
alter table public.subscription_formulas enable row level security;
alter table public.subscriptions enable row level security;
alter table public.subscription_payments enable row level security;
alter table public.allocation_preferences enable row level security;
alter table public.covered_assets enable row level security;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;

-- Published rules are public.
create policy "fund settings are public" on public.fund_settings for select using (true);
create policy "formulas are public" on public.subscription_formulas for select using (true);
grant select on public.fund_settings, public.subscription_formulas to anon, authenticated;

create policy "members read themselves" on public.members for select to authenticated
  using (id = auth.uid());
create policy "members create themselves" on public.members for insert to authenticated
  with check (id = auth.uid() and status = 'pending_verification');
create policy "members edit themselves" on public.members for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
-- Region is set at sign-up and changed only by the service (after address
-- verification): reviewers are matched by region, so a self-editable region
-- would let a reviewer step around the anti-collusion rule.
grant select, insert (id, display_name, region), update (display_name)
  on public.members to authenticated;

create policy "members read their roles" on public.member_roles for select to authenticated
  using (member_id = auth.uid());
grant select on public.member_roles to authenticated;

create policy "members read their income checks" on public.income_verifications for select to authenticated
  using (member_id = auth.uid());
grant select on public.income_verifications to authenticated;

create policy "members read their subscriptions" on public.subscriptions for select to authenticated
  using (member_id = auth.uid());
grant select on public.subscriptions to authenticated;

create policy "members read their payments" on public.subscription_payments for select to authenticated
  using (member_id = auth.uid());
grant select on public.subscription_payments to authenticated;

create policy "members manage their allocation" on public.allocation_preferences for all to authenticated
  using (member_id = auth.uid()) with check (member_id = auth.uid());
grant select, insert, update, delete on public.allocation_preferences to authenticated;

create policy "members manage their assets" on public.covered_assets for all to authenticated
  using (member_id = auth.uid()) with check (member_id = auth.uid() and verified_at is null);
grant select, insert (member_id, kind, description, value_cents), update (description, removed_on)
  on public.covered_assets to authenticated;

grant execute on function public.has_role(public.member_role), public.is_active_member(),
  public.subscription_amount(bigint, integer), public.coverage_started_on(uuid) to authenticated;
grant execute on function public.subscription_amount(bigint, integer) to anon;
