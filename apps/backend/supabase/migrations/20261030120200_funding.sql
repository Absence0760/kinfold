-- Funding: invitations, contributions, zero-interest family loans, payouts, the
-- double-entry ledger and the community pool allocation.
--
-- Money never sits with Kinfold. These tables mirror what the payment and
-- custody partners report (by partner_ref), so the books can be checked against
-- the partners and published. Invariants enforced here, not just in app code:
--   * pledges are all-or-nothing: captured only once a request is fully funded,
--     released if it's withdrawn, refused or expires;
--   * only invited people (family, friends) can lend; anyone verified can give;
--   * a loan's schedule sums exactly to the principal (there is no interest);
--   * a payout goes only to the request's verified payee, against an invoice;
--   * every ledger journal balances and stays inside one fund.

create type public.contribution_source as enum ('gift', 'loan', 'pool');
create type public.contribution_status as enum ('pledged', 'captured', 'released', 'refunded');
create type public.loan_status as enum (
  'proposed', 'signed', 'active', 'paused', 'repaid', 'forgiven', 'defaulted', 'cancelled'
);
create type public.payout_status as enum ('pending', 'sent', 'failed', 'returned');

-- --- invitations --------------------------------------------------------------

create table public.request_invites (
  id            uuid primary key default gen_random_uuid(),
  request_id    uuid not null references public.requests (id) on delete cascade,
  token_sha256  text not null unique,
  relationship  text not null check (length(relationship) between 1 and 40),
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default now() + interval '30 days',
  accepted_by   uuid references public.members (id),
  accepted_at   timestamptz
);

create table public.request_supporters (
  request_id    uuid not null references public.requests (id) on delete cascade,
  member_id     uuid not null references public.members (id) on delete cascade,
  relationship  text not null,
  joined_at     timestamptz not null default now(),
  primary key (request_id, member_id)
);

-- Owner creates an invite link. The plain token is returned once; only its hash
-- is stored.
create function public.create_invite(p_request uuid, p_relationship text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  if not exists (select 1 from public.requests where id = p_request and member_id = auth.uid()
                 and status not in ('withdrawn', 'expired', 'refused', 'paid')) then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  insert into public.request_invites (request_id, token_sha256, relationship)
  values (p_request, encode(extensions.digest(v_token, 'sha256'), 'hex'), p_relationship);
  return v_token;
end $$;

create function public.accept_invite(p_token text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  i public.request_invites;
begin
  select * into i from public.request_invites
  where token_sha256 = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and accepted_at is null and expires_at > now()
  for update;
  if i.id is null then
    raise exception 'invite not found, used or expired' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.requests where id = i.request_id and member_id = auth.uid()) then
    raise exception 'you cannot accept an invite to your own request' using errcode = '42501';
  end if;
  update public.request_invites set accepted_by = auth.uid(), accepted_at = now() where id = i.id;
  insert into public.request_supporters (request_id, member_id, relationship)
  values (i.request_id, auth.uid(), i.relationship)
  on conflict do nothing;
  return i.request_id;
end $$;

create function public.is_supporter(p_request uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.request_supporters where request_id = p_request and member_id = auth.uid());
$$;

-- --- family loans -------------------------------------------------------------
-- Zero interest by construction: there is no rate column. `imputed_rate_bps` is
-- the IRS minimum (AFR) used only to produce the gift paperwork; nobody pays it.

create table public.family_loans (
  id                     uuid primary key default gen_random_uuid(),
  request_id             uuid references public.requests (id) on delete set null,
  borrower_id            uuid not null references public.members (id),
  lender_id              uuid not null references public.members (id),
  principal_cents        bigint not null check (principal_cents > 0),
  status                 public.loan_status not null default 'proposed',
  secured                boolean not null default false,
  lien_recorded_at       timestamptz,
  imputed_rate_bps       integer check (imputed_rate_bps >= 0),
  agreement_path         text,
  borrower_signed_at     timestamptz,
  lender_signed_at       timestamptz,
  created_at             timestamptz not null default now(),
  check (borrower_id <> lender_id),
  check (lien_recorded_at is null or secured)
);

create table public.loan_installments (
  loan_id       uuid not null references public.family_loans (id) on delete cascade,
  seq           integer not null check (seq > 0),
  due_on        date not null,
  amount_cents  bigint not null check (amount_cents > 0),
  paid_cents    bigint not null default 0 check (paid_cents >= 0),
  paused        boolean not null default false,
  primary key (loan_id, seq),
  check (paid_cents <= amount_cents)
);

create table public.loan_forgiveness (
  id            uuid primary key default gen_random_uuid(),
  loan_id       uuid not null references public.family_loans (id) on delete cascade,
  tax_year      integer not null check (tax_year between 2000 and 2200),
  amount_cents  bigint not null check (amount_cents > 0),
  created_at    timestamptz not null default now()
);

-- Security invoker: clients get a balance only for loans they are party to
-- (RLS on family_loans); definer callers (forgive_loan, the totals trigger)
-- read past RLS as the owner.
create function public.loan_outstanding_cents(p_loan uuid) returns bigint
language sql stable security invoker set search_path = '' as $$
  select l.principal_cents
       - coalesce((select sum(paid_cents) from public.loan_installments where loan_id = l.id), 0)
       - coalesce((select sum(amount_cents) from public.loan_forgiveness where loan_id = l.id), 0)
  from public.family_loans l where l.id = p_loan;
$$;

create function private.check_loan_totals() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_loan uuid := coalesce(new.loan_id, old.loan_id);
  v_principal bigint;
  v_scheduled bigint;
begin
  select principal_cents into v_principal from public.family_loans where id = v_loan;
  select coalesce(sum(amount_cents), 0) into v_scheduled from public.loan_installments where loan_id = v_loan;
  if v_scheduled > v_principal then
    raise exception 'installments (%) exceed the principal (%): Kinfold loans carry no interest',
      v_scheduled, v_principal using errcode = '23514';
  end if;
  if public.loan_outstanding_cents(v_loan) < 0 then
    raise exception 'payments and forgiveness exceed the principal' using errcode = '23514';
  end if;
  return null;
end $$;

create constraint trigger loan_installments_total after insert or update or delete on public.loan_installments
  deferrable initially deferred for each row execute function private.check_loan_totals();
create constraint trigger loan_forgiveness_total after insert or update on public.loan_forgiveness
  deferrable initially deferred for each row execute function private.check_loan_totals();

-- Borrower or lender sets an equal monthly schedule; the last installment takes
-- the remainder so the total is exactly the principal. Clears any signatures.
create function public.set_loan_schedule(p_loan uuid, p_months integer, p_first_due date) returns void
language plpgsql security definer set search_path = '' as $$
declare
  l public.family_loans;
  v_each bigint;
begin
  select * into l from public.family_loans where id = p_loan for update;
  if l.id is null or auth.uid() not in (l.borrower_id, l.lender_id) then
    raise exception 'loan not found' using errcode = 'P0002';
  end if;
  if l.status <> 'proposed' then
    raise exception 'a signed loan''s schedule can only change by agreement (restructure)' using errcode = '23514';
  end if;
  if p_months not between 1 and 480 then
    raise exception 'schedule must be 1 to 480 months' using errcode = '23514';
  end if;
  v_each := l.principal_cents / p_months;
  if v_each = 0 then
    raise exception 'too many installments for this amount' using errcode = '23514';
  end if;
  delete from public.loan_installments where loan_id = p_loan;
  insert into public.loan_installments (loan_id, seq, due_on, amount_cents)
  select p_loan, n, (p_first_due + make_interval(months => n - 1))::date,
         case when n = p_months then l.principal_cents - v_each * (p_months - 1) else v_each end
  from generate_series(1, p_months) n;
  update public.family_loans set borrower_signed_at = null, lender_signed_at = null where id = p_loan;
end $$;

create function public.sign_loan(p_loan uuid) returns public.loan_status
language plpgsql security definer set search_path = '' as $$
declare
  l public.family_loans;
begin
  select * into l from public.family_loans where id = p_loan for update;
  if l.id is null or auth.uid() not in (l.borrower_id, l.lender_id) then
    raise exception 'loan not found' using errcode = 'P0002';
  end if;
  if l.status <> 'proposed' then
    raise exception 'loan is already %', l.status using errcode = '23514';
  end if;
  if coalesce((select sum(amount_cents) from public.loan_installments where loan_id = p_loan), 0)
     <> l.principal_cents then
    raise exception 'set a repayment schedule that adds up to the amount lent' using errcode = '23514';
  end if;
  update public.family_loans set
    borrower_signed_at = case when auth.uid() = borrower_id then now() else borrower_signed_at end,
    lender_signed_at   = case when auth.uid() = lender_id then now() else lender_signed_at end
  where id = p_loan returning * into l;
  if l.borrower_signed_at is not null and l.lender_signed_at is not null then
    update public.family_loans set status = 'signed' where id = p_loan;
    return 'signed';
  end if;
  return 'proposed';
end $$;

-- Lender forgives part of the balance (e.g. within the annual gift exclusion).
create function public.forgive_loan(p_loan uuid, p_amount_cents bigint, p_tax_year integer) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.family_loans where id = p_loan and lender_id = auth.uid()
                 and status in ('signed', 'active', 'paused')) then
    raise exception 'only the lender can forgive an active loan' using errcode = '42501';
  end if;
  insert into public.loan_forgiveness (loan_id, tax_year, amount_cents) values (p_loan, p_tax_year, p_amount_cents);
  if public.loan_outstanding_cents(p_loan) = 0 then
    update public.family_loans set status = 'forgiven' where id = p_loan;
  end if;
end $$;

-- --- contributions ------------------------------------------------------------

create table public.pool_runs (
  id                 uuid primary key default gen_random_uuid(),
  fund               public.fund not null check (fund <> 'people'),
  available_cents    bigint not null check (available_cents >= 0),
  reserve_cents      bigint not null check (reserve_cents >= 0),
  allocated_cents    bigint not null default 0 check (allocated_cents >= 0),
  settings           jsonb not null,
  algorithm_version  text not null,
  run_at             timestamptz not null default now(),
  check (reserve_cents + allocated_cents <= available_cents)
);

create table public.pool_allocations (
  id           uuid primary key default gen_random_uuid(),
  run_id       uuid not null references public.pool_runs (id),
  request_id   uuid not null references public.requests (id),
  score        smallint not null,
  band         smallint not null,
  need_cents   bigint not null check (need_cents > 0),
  grant_cents  bigint not null check (grant_cents >= 0 and grant_cents <= need_cents),
  unique (run_id, request_id)
);

create table public.contributions (
  id                  uuid primary key default gen_random_uuid(),
  request_id          uuid not null references public.requests (id),
  contributor_id      uuid references public.members (id),
  source              public.contribution_source not null,
  amount_cents        bigint not null check (amount_cents > 0),
  status              public.contribution_status not null default 'pledged',
  loan_id             uuid references public.family_loans (id),
  pool_allocation_id  uuid references public.pool_allocations (id),
  partner_ref         text unique,
  created_at          timestamptz not null default now(),
  check ((source = 'pool') = (contributor_id is null)),
  check ((source = 'pool') = (pool_allocation_id is not null)),
  check ((source = 'loan') = (loan_id is not null))
);

create index contributions_request on public.contributions (request_id);

create function public.request_raised_cents(p_request uuid) returns bigint
language sql stable security definer set search_path = '' as $$
  select coalesce(sum(amount_cents), 0) from public.contributions
  where request_id = p_request and status in ('pledged', 'captured');
$$;

create function private.mark_funded() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.requests r set status = 'funded'
  where r.id = new.request_id and r.status = 'open'
    and public.request_raised_cents(r.id) >= r.amount_cents;
  return null;
end $$;

create trigger contributions_mark_funded after insert on public.contributions
  for each row execute function private.mark_funded();

-- All-or-nothing: a request that ends without being paid releases its pledges
-- and cancels unsigned loans.
create function private.release_on_close() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status in ('withdrawn', 'expired', 'refused') then
    update public.contributions set status = 'released' where request_id = new.id and status = 'pledged';
    update public.family_loans set status = 'cancelled'
    where request_id = new.id and status in ('proposed', 'signed');
  end if;
  return null;
end $$;

create trigger requests_release_on_close after update of status on public.requests
  for each row when (old.status is distinct from new.status)
  execute function private.release_on_close();

-- Family, friends or any verified member pledge to an open request.
create function public.pledge(p_request uuid, p_amount_cents bigint, p_source public.contribution_source)
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
  -- Strangers give only to requests they can see on the board (same rule as
  -- public.board_requests: a pool request with a redacted public summary).
  if p_source = 'gift' and not v_invited
     and not (r.funding in ('pool', 'both') and r.public_summary is not null
              and public.is_active_member()) then
    raise exception 'ask the member for an invite to give to this request' using errcode = '42501';
  end if;
  -- Loans only between people who know each other. A loan from a stranger on
  -- the board would be regulated lending, so it isn't offered.
  if p_source = 'loan' and not (v_invited and public.is_active_member()) then
    raise exception 'only invited, verified family and friends can lend' using errcode = '42501';
  end if;

  v_left := r.amount_cents - public.request_raised_cents(p_request);
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

-- --- the pool run ---------------------------------------------------------------
-- Same rule as apps/web/src/lib/requests/allocation.ts, in integer cents: hold
-- the reserve back, then fill legitimacy bands from the top; inside a band every
-- request gets the same share of what it still needs. Service role only (a
-- scheduled edge function), after the custody partner confirms the balance.

create function public.run_pool_allocation(p_fund public.fund, p_available_cents bigint) returns uuid
language plpgsql security definer set search_path = '' as $$
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
         r.amount_cents - public.request_raised_cents(r.id) as need
  from public.requests r
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

-- --- payouts ------------------------------------------------------------------

create table public.payouts (
  id                   uuid primary key default gen_random_uuid(),
  request_id           uuid not null references public.requests (id),
  payee_id             uuid not null references public.payees (id),
  amount_cents         bigint not null check (amount_cents > 0),
  invoice_evidence_id  uuid not null references public.evidence (id),
  status               public.payout_status not null default 'pending',
  partner_ref          text unique,
  created_at           timestamptz not null default now()
);

create function private.guard_payout() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  r public.requests;
begin
  select * into r from public.requests where id = new.request_id;
  if r.status not in ('funded', 'paid') then
    raise exception 'only funded requests are paid out' using errcode = '23514';
  end if;
  if new.payee_id is distinct from r.payee_id then
    raise exception 'money goes only to the request''s named payee' using errcode = '42501';
  end if;
  if not exists (select 1 from public.payees where id = new.payee_id and status = 'verified') then
    raise exception 'payee is not verified' using errcode = '42501';
  end if;
  if not exists (select 1 from public.evidence where id = new.invoice_evidence_id
                 and request_id = new.request_id and kind = 'invoice') then
    raise exception 'a payout needs the payee''s final invoice on this request' using errcode = '23514';
  end if;
  if (select coalesce(sum(amount_cents), 0) from public.payouts
      where request_id = new.request_id and status in ('pending', 'sent') and id <> new.id)
     + new.amount_cents
     > (select coalesce(sum(amount_cents), 0) from public.contributions
        where request_id = new.request_id and status = 'captured') then
    raise exception 'payouts cannot exceed captured contributions' using errcode = '23514';
  end if;
  perform private.audit('payout.' || new.status, 'payouts', new.id,
                        jsonb_build_object('amount_cents', new.amount_cents, 'payee_id', new.payee_id));
  return new;
end $$;

create trigger payouts_guard before insert or update on public.payouts
  for each row execute function private.guard_payout();

-- --- ledger -------------------------------------------------------------------

create table private.ledger_accounts (
  id         uuid primary key default gen_random_uuid(),
  fund       public.fund not null,
  code       text not null,
  member_id  uuid references public.members (id),
  payee_id   uuid references public.payees (id),
  -- nulls not distinct: post_journal resolves a fund-level account by
  -- (fund, code) with null member/payee, so a duplicate would double-post.
  unique nulls not distinct (fund, code, member_id, payee_id)
);

create table private.ledger_journals (
  id          uuid primary key default gen_random_uuid(),
  fund        public.fund not null,
  kind        text not null,
  ref_id      uuid,
  partner_ref text unique,
  memo        text,
  created_at  timestamptz not null default now()
);

create table private.ledger_lines (
  id            bigint generated always as identity primary key,
  journal_id    uuid not null references private.ledger_journals (id),
  account_id    uuid not null references private.ledger_accounts (id),
  amount_cents  bigint not null check (amount_cents <> 0)
);

create trigger ledger_journals_append_only before update or delete on private.ledger_journals
  for each row execute function private.forbid_change();
create trigger ledger_lines_append_only before update or delete on private.ledger_lines
  for each row execute function private.forbid_change();

create function private.check_journal() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_sum   bigint;
  v_cross integer;
begin
  select coalesce(sum(l.amount_cents), 0),
         count(*) filter (where a.fund <> j.fund)
  into v_sum, v_cross
  from private.ledger_lines l
  join private.ledger_accounts a on a.id = l.account_id
  join private.ledger_journals j on j.id = l.journal_id
  where l.journal_id = new.journal_id;
  if v_sum <> 0 then
    raise exception 'journal % does not balance (off by % cents)', new.journal_id, v_sum using errcode = '23514';
  end if;
  if v_cross > 0 then
    raise exception 'journal % moves money between funds; the pools never mix', new.journal_id
      using errcode = '23514';
  end if;
  return null;
end $$;

create constraint trigger ledger_lines_balance after insert on private.ledger_lines
  deferrable initially deferred for each row execute function private.check_journal();

insert into private.ledger_accounts (fund, code)
select f, code
from unnest(enum_range(null::public.fund)) f,
     unnest(array['partner_cash', 'available', 'reserve', 'committed', 'paid_out']) code;

-- Service role posts a journal from a partner webhook, e.g.
--   select private.post_journal('protection', 'subscription', ref, 'pi_123',
--     '[{"code":"partner_cash","amount_cents":800},{"code":"available","amount_cents":-800}]');
create function private.post_journal(
  p_fund public.fund, p_kind text, p_ref uuid, p_partner_ref text, p_lines jsonb
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  insert into private.ledger_journals (fund, kind, ref_id, partner_ref)
  values (p_fund, p_kind, p_ref, p_partner_ref) returning id into v_id;
  insert into private.ledger_lines (journal_id, account_id, amount_cents)
  select v_id, a.id, (line ->> 'amount_cents')::bigint
  from jsonb_array_elements(p_lines) line
  join private.ledger_accounts a
    on a.fund = coalesce((line ->> 'fund')::public.fund, p_fund)
   and a.code = line ->> 'code' and a.member_id is null and a.payee_id is null;
  if (select count(*) from private.ledger_lines where journal_id = v_id) <> jsonb_array_length(p_lines) then
    raise exception 'unknown ledger account in journal' using errcode = '23503';
  end if;
  return v_id;
end $$;

-- --- open books ---------------------------------------------------------------

create view public.public_stats as
select
  f.fund,
  (select count(*) from public.requests r
   where public.fund_for_kind(r.kind) = f.fund and r.funding in ('pool', 'both') and r.status = 'paid') as requests_paid,
  (select coalesce(sum(p.amount_cents), 0) from public.payouts p
   join public.requests r on r.id = p.request_id
   where public.fund_for_kind(r.kind) = f.fund and p.status = 'sent') as paid_out_cents,
  (select count(*) from public.pool_runs pr where pr.fund = f.fund) as pool_runs,
  (select coalesce(sum(allocated_cents), 0) from public.pool_runs pr where pr.fund = f.fund) as allocated_cents
from public.fund_settings f;

-- A member's reliability record: what replaces a credit score.
create function public.my_reliability() returns table (
  subscription_payments bigint, installments_paid_on_time bigint, installments_due bigint,
  requests_paid bigint, member_since date
) language sql stable security definer set search_path = '' as $$
  select
    (select count(*) from public.subscription_payments where member_id = auth.uid() and status = 'captured'),
    (select count(*) from public.loan_installments i join public.family_loans l on l.id = i.loan_id
     where l.borrower_id = auth.uid() and i.paid_cents = i.amount_cents),
    (select count(*) from public.loan_installments i join public.family_loans l on l.id = i.loan_id
     where l.borrower_id = auth.uid() and i.due_on <= current_date),
    (select count(*) from public.requests where member_id = auth.uid() and status = 'paid'),
    (select joined_at::date from public.members where id = auth.uid());
$$;

-- --- row-level security and grants ---------------------------------------------

alter table public.request_invites enable row level security;
alter table public.request_supporters enable row level security;
alter table public.family_loans enable row level security;
alter table public.loan_installments enable row level security;
alter table public.loan_forgiveness enable row level security;
alter table public.pool_runs enable row level security;
alter table public.pool_allocations enable row level security;
alter table public.contributions enable row level security;
alter table public.payouts enable row level security;

revoke all on public.request_invites, public.request_supporters, public.family_loans,
  public.loan_installments, public.loan_forgiveness, public.pool_runs, public.pool_allocations,
  public.contributions, public.payouts, public.public_stats from anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

-- Supporters read the requests they were invited to.
create policy "supporters read requests they back" on public.requests for select to authenticated
  using (public.is_supporter(id));

create policy "owners read their invites" on public.request_invites for select to authenticated
  using (exists (select 1 from public.requests r where r.id = request_id and r.member_id = auth.uid()));
grant select (id, request_id, relationship, created_at, expires_at, accepted_by, accepted_at)
  on public.request_invites to authenticated;

create policy "owners and supporters read supporters" on public.request_supporters for select to authenticated
  using (member_id = auth.uid()
         or exists (select 1 from public.requests r where r.id = request_id and r.member_id = auth.uid()));
grant select on public.request_supporters to authenticated;

create policy "borrower and lender read the loan" on public.family_loans for select to authenticated
  using (auth.uid() in (borrower_id, lender_id));
grant select on public.family_loans to authenticated;

create policy "borrower and lender read the schedule" on public.loan_installments for select to authenticated
  using (exists (select 1 from public.family_loans l where l.id = loan_id and auth.uid() in (l.borrower_id, l.lender_id)));
grant select on public.loan_installments to authenticated;

create policy "borrower and lender read forgiveness" on public.loan_forgiveness for select to authenticated
  using (exists (select 1 from public.family_loans l where l.id = loan_id and auth.uid() in (l.borrower_id, l.lender_id)));
grant select on public.loan_forgiveness to authenticated;

create policy "pool runs are open books" on public.pool_runs for select using (true);
grant select on public.pool_runs to anon, authenticated;

create policy "verified members see allocations" on public.pool_allocations for select to authenticated
  using (public.is_active_member());
grant select on public.pool_allocations to authenticated;

create policy "contributors and owners read contributions" on public.contributions for select to authenticated
  using (contributor_id = auth.uid()
         or exists (select 1 from public.requests r where r.id = request_id and r.member_id = auth.uid()));
grant select on public.contributions to authenticated;

create policy "owners read payouts" on public.payouts for select to authenticated
  using (exists (select 1 from public.requests r where r.id = request_id and r.member_id = auth.uid()));
grant select on public.payouts to authenticated;

grant select on public.public_stats to anon, authenticated;

-- Function grants for the whole schema live here, after the blanket revoke above.
grant execute on function
  public.has_role(public.member_role), public.is_active_member(),
  public.subscription_amount(bigint, integer), public.coverage_started_on(uuid),
  public.fund_for_kind(public.request_kind),
  public.submit_request(uuid), public.withdraw_request(uuid), public.confirm_redaction(uuid),
  public.record_review(uuid, public.review_decision, text),
  public.file_appeal(uuid, text), public.decide_appeal(uuid, boolean),
  public.create_invite(uuid, text), public.accept_invite(text), public.is_supporter(uuid),
  public.loan_outstanding_cents(uuid), public.set_loan_schedule(uuid, integer, date),
  public.sign_loan(uuid), public.forgive_loan(uuid, bigint, integer),
  public.request_raised_cents(uuid), public.pledge(uuid, bigint, public.contribution_source),
  public.my_reliability()
to authenticated;
grant execute on function public.subscription_amount(bigint, integer) to anon;
-- public_stats is granted to anon and calls fund_for_kind; a view's caller
-- needs execute on the functions it uses.
grant execute on function public.fund_for_kind(public.request_kind) to anon;
-- record_score, run_pool_allocation and private.post_journal are service-role only.
