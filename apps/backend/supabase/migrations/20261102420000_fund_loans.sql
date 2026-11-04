-- Home Fund loans (roadmap 3a): the same shape as `family_loans`, but the lender
-- is the Fund itself — charity lending through the partner credit union. The
-- Fund signs the agreement at once (there is no lender member to wait for), the
-- borrower signs their side, and only the partner's disbursement (a service
-- statement) activates the loan. Income-based schedules carry a share of the
-- member's verified income and the schema caps each month's payment at that
-- figure, so payments fall off automatically when income does. Lien terms follow
-- design.md: the loan's lien sits behind the bank's and any public-assistance
-- liens, and all liens together must stay at or below 105% of the home's value.

create type public.fund_loan_schedule as enum ('monthly', 'income');

create table public.fund_loans (
  id                 uuid primary key default gen_random_uuid(),
  fund               public.fund not null check (fund = 'home_fund'),
  borrower_id        uuid not null references public.members (id) on delete cascade,
  principal_cents    bigint not null check (principal_cents > 0),
  status             public.loan_status not null default 'proposed',
  secured            boolean not null default false,
  lien_bps           integer not null default 0 check (lien_bps between 0 and 105000),
  bank_lien_bps      integer not null default 0 check (bank_lien_bps between 0 and 105000),
  pa_lien_bps        integer not null default 0 check (pa_lien_bps between 0 and 105000),
  schedule           public.fund_loan_schedule not null,
  income_share_bps   integer not null check (income_share_bps between 0 and 10000),
  fund_signed_at     timestamptz,
  borrower_signed_at timestamptz,
  partner_ref        text unique,
  created_at         timestamptz not null default now(),
  check (secured or (lien_bps = 0 and bank_lien_bps = 0 and pa_lien_bps = 0)),
  check (not secured or lien_bps + bank_lien_bps + pa_lien_bps <= 105000),
  check (schedule <> 'income' or income_share_bps > 0),
  check (schedule <> 'monthly' or income_share_bps = 0)
);

-- Monthly schedules look exactly like family-loan installments; the totals check
-- below is the no-interest rule: payments never exceed what was lent.
create table public.fund_loan_installments (
  loan_id       uuid not null references public.fund_loans (id) on delete cascade,
  seq           integer not null check (seq > 0),
  due_on        date not null,
  amount_cents  bigint not null check (amount_cents > 0),
  paid_cents    bigint not null default 0 check (paid_cents >= 0),
  primary key (loan_id, seq),
  check (paid_cents <= amount_cents)
);

-- Income schedules have no fixed rows: each payment is recorded as it happens,
-- append-only, capped at the income share by the schema functions below.
create table public.fund_loan_payments (
  id           bigint generated always as identity primary key,
  loan_id      uuid not null references public.fund_loans (id) on delete cascade,
  amount_cents bigint not null check (amount_cents > 0),
  paid_on      timestamptz not null default now()
);

create trigger fund_loan_payments_append_only before update or delete on public.fund_loan_payments
  for each row execute function private.forbid_change();

alter table public.fund_loans enable row level security;
alter table public.fund_loan_installments enable row level security;
alter table public.fund_loan_payments enable row level security;

create policy "borrowers read their fund loans" on public.fund_loans
  for select to authenticated
  using (borrower_id = auth.uid());

create policy "borrowers read their installment schedules" on public.fund_loan_installments
  for select to authenticated
  using (exists (select 1 from public.fund_loans f where f.id = loan_id
                 and f.borrower_id = auth.uid()));

create policy "borrowers read their payments" on public.fund_loan_payments
  for select to authenticated
  using (exists (select 1 from public.fund_loans f where f.id = loan_id
                 and f.borrower_id = auth.uid()));

grant select on public.fund_loans to authenticated;
grant select on public.fund_loan_installments to authenticated;
grant select on public.fund_loan_payments to authenticated;

-- The member's latest still-live verified income (definer reads past RLS).
create function private.member_live_income_cents(p_member uuid) returns bigint
language sql stable security definer set search_path = '' as $$
  select coalesce((select monthly_income_cents
                   from public.income_verifications
                   where member_id = p_member and expires_at > now()
                   order by verified_at desc limit 1), 0);
$$;

-- One month's share of an income schedule: never more than the share of income
-- at the moment of asking, so a falling income shrinks payments by itself.
create function public.fund_loan_income_due_cents(p_loan uuid) returns bigint
language sql stable security definer set search_path = '' as $$
  select case when l.schedule = 'income'
              then l.income_share_bps * private.member_live_income_cents(l.borrower_id) / 10000
              else 0::bigint end
  from public.fund_loans l where l.id = p_loan limit 1;
$$;

create function public.fund_loan_outstanding_cents(p_loan uuid) returns bigint
language sql stable security definer set search_path = '' as $$
  select l.principal_cents
       - coalesce((select sum(amount_cents) from public.fund_loan_payments where loan_id = l.id), 0)
       - coalesce((select sum(paid_cents) from public.fund_loan_installments where loan_id = l.id), 0)
  from public.fund_loans l where l.id = p_loan limit 1;
$$;

-- Payments and forgiveness never exceed the principal; monthly schedules never
-- schedule more than the principal. (The Fund lends at no interest, so the
-- money moving back can only ever be money that moved out.)
create function private.check_fund_loan_totals() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_loan uuid := coalesce(new.loan_id, old.loan_id);
  v_principal bigint;
begin
  select principal_cents into v_principal from public.fund_loans where id = v_loan;
  if v_loan is null then
    return null;
  end if;
  if coalesce((select sum(amount_cents) from public.fund_loan_installments where loan_id = v_loan), 0)
     > v_principal then
    raise exception 'fund loan schedule exceeds the principal: Kinfold lends at no interest'
      using errcode = '23514';
  end if;
  if public.fund_loan_outstanding_cents(v_loan) < 0 then
    raise exception 'fund loan payments exceed the principal' using errcode = '23514';
  end if;
  return null;
end $$;

create constraint trigger fund_loan_installments_total after insert or update or delete on public.fund_loan_installments
  deferrable initially deferred for each row execute function private.check_fund_loan_totals();
create constraint trigger fund_loan_payments_total after insert on public.fund_loan_payments
  deferrable initially deferred for each row execute function private.check_fund_loan_totals();

-- The partner opens the loan (they know the home, the liens, the need). The
-- reference makes a replayed event a no-op answering with the loan already made.
create function public.create_fund_loan(
  p_borrower uuid, p_principal_cents bigint, p_secured boolean,
  p_lien_bps integer, p_bank_lien_bps integer, p_pa_lien_bps integer,
  p_schedule public.fund_loan_schedule, p_income_share_bps integer,
  p_partner_ref text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not private.is_service() then
    raise exception 'fund loans are opened by the partner' using errcode = '42501';
  end if;
  if p_partner_ref is null or p_partner_ref = '' then
    raise exception 'a fund loan needs the partner''s loan reference' using errcode = '23514';
  end if;
  if exists (select 1 from public.fund_loans where partner_ref = p_partner_ref) then
    return (select id from public.fund_loans where partner_ref = p_partner_ref);
  end if;
  insert into public.fund_loans
    (fund, borrower_id, principal_cents, secured, lien_bps, bank_lien_bps,
     pa_lien_bps, schedule, income_share_bps, fund_signed_at, partner_ref)
    values ('home_fund', p_borrower, p_principal_cents, p_secured,
            p_lien_bps, p_bank_lien_bps, p_pa_lien_bps, p_schedule,
            p_income_share_bps, now(), p_partner_ref)
    returning id into v_id;
  perform private.audit('fund_loans.created', 'fund_loans', v_id,
    jsonb_build_object('borrower', p_borrower, 'principal_cents', p_principal_cents,
                       'schedule', p_schedule, 'partner_ref', p_partner_ref));
  return v_id;
end $$;

-- The borrower agrees to a monthly schedule (mirror of set_loan_schedule: equal
-- months, the tail taking the remainder so the total is exactly the principal).
create function public.set_fund_loan_schedule(p_loan uuid, p_months integer,
  p_first_due date) returns void
language plpgsql security definer set search_path = '' as $$
declare
  l       public.fund_loans;
  v_each  bigint;
begin
  select * into l from public.fund_loans where id = p_loan for update;
  if l.id is null or l.borrower_id <> auth.uid() then
    raise exception 'fund loan not found' using errcode = 'P0002';
  end if;
  if l.schedule <> 'monthly' then
    raise exception 'income schedules are computed from income, not set' using errcode = '23514';
  end if;
  if l.status <> 'proposed' then
    raise exception 'a signed fund loan''s schedule can only change by agreement' using errcode = '23514';
  end if;
  if p_months not between 1 and 480 then
    raise exception 'schedule must be 1 to 480 months' using errcode = '23514';
  end if;
  if p_first_due < current_date then
    raise exception 'a proposed schedule can''t start in the past' using errcode = '23514';
  end if;
  v_each := l.principal_cents / p_months;
  if v_each = 0 then
    raise exception 'too many installments for this amount' using errcode = '23514';
  end if;
  delete from public.fund_loan_installments where loan_id = p_loan;
  insert into public.fund_loan_installments (loan_id, seq, due_on, amount_cents)
  select p_loan, n, (p_first_due + make_interval(months => n - 1))::date,
         case when n = p_months then l.principal_cents - v_each * (p_months - 1) else v_each end
  from generate_series(1, p_months) n;
  update public.fund_loans set borrower_signed_at = null where id = p_loan;
end $$;

-- Borrower signs; the Fund side was signed at once when the loan was opened.
create function public.sign_fund_loan(p_loan uuid) returns public.loan_status
language plpgsql security definer set search_path = '' as $$
declare
  l public.fund_loans;
begin
  select * into l from public.fund_loans where id = p_loan for update;
  if l.id is null or l.borrower_id <> auth.uid() then
    raise exception 'fund loan not found' using errcode = 'P0002';
  end if;
  if l.status <> 'proposed' then
    raise exception 'fund loan is already %', l.status using errcode = '23514';
  end if;
  if l.schedule = 'monthly' and coalesce((select sum(amount_cents)
        from public.fund_loan_installments where loan_id = p_loan), 0) <> l.principal_cents then
    raise exception 'set a repayment schedule that adds up to the amount lent' using errcode = '23514';
  end if;
  update public.fund_loans set borrower_signed_at = now() where id = p_loan;
  update public.fund_loans set status = 'signed' where id = p_loan;
  return 'signed';
end $$;

-- Only the partner's disbursement activates a fund loan: money moving is the
-- partner's event, so a loan without a request still becomes active (the open
-- followup for loans that never accompany a request).
create function public.activate_fund_loan(p_loan uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  l public.fund_loans;
begin
  if not private.is_service() then
    raise exception 'fund loans are activated by the partner''s disbursement' using errcode = '42501';
  end if;
  select * into l from public.fund_loans where id = p_loan;
  if l.status <> 'signed' then
    raise exception 'fund loan not found, or not awaiting disbursement' using errcode = 'P0002';
  end if;
  update public.fund_loans set status = 'active' where id = p_loan;
  perform private.audit('fund_loans.activate', 'fund_loans', p_loan,
                        jsonb_build_object('loan_id', p_loan));
end $$;

-- The partner moves one month's money. Monthly loans pay an installment of the
-- agreed schedule; income loans pay at most the month's income share — the
-- schema checks the cap, so a payment can never outrun the income it was
-- priced from. Reaching zero outstanding completes the loan.
create function public.record_fund_loan_payment(
  p_loan uuid, p_seq integer, p_amount_cents bigint
) returns bigint language plpgsql security definer set search_path = '' as $$
declare
  l        public.fund_loans;
  i        public.fund_loan_installments;
  v_left   bigint;
  v_due    bigint;
begin
  if not private.is_service() then
    raise exception 'fund loan money is moved by the partner' using errcode = '42501';
  end if;
  select * into l from public.fund_loans where id = p_loan;
  if l.status not in ('active', 'paused') then
    raise exception 'fund loan not found, or not collecting' using errcode = 'P0002';
  end if;
  if l.schedule = 'monthly' then
    select * into i from public.fund_loan_installments where loan_id = p_loan and seq = p_seq for update;
    if i.id is null then
      raise exception 'installment not found' using errcode = 'P0002';
    end if;
    v_left := i.amount_cents - i.paid_cents;
    if p_amount_cents <= 0 or p_amount_cents > v_left then
      raise exception 'fund loan payment must be between 1 and % cents', v_left using errcode = '23514';
    end if;
    update public.fund_loan_installments set paid_cents = paid_cents + p_amount_cents
    where loan_id = p_loan and seq = p_seq;
  else
    v_due := public.fund_loan_income_due_cents(p_loan);
    if p_amount_cents <= 0 or p_amount_cents > v_due then
      raise exception 'income payment must be between 1 and % cents', v_due using errcode = '23514';
    end if;
    insert into public.fund_loan_payments (loan_id, amount_cents)
    values (p_loan, p_amount_cents);
  end if;
  perform private.audit('fund_loan.payment', 'fund_loans', p_loan,
                        jsonb_build_object('seq', p_seq, 'amount_cents', p_amount_cents));
  if public.fund_loan_outstanding_cents(p_loan) = 0 then
    update public.fund_loans set status = 'repaid' where id = p_loan;
  end if;
  return public.fund_loan_outstanding_cents(p_loan);
end $$;

revoke all on function public.create_fund_loan(uuid, bigint, boolean, integer, integer, integer, public.fund_loan_schedule, integer, text) from public, anon, authenticated;
grant execute on function public.create_fund_loan(uuid, bigint, boolean, integer, integer, integer, public.fund_loan_schedule, integer, text)
  to service_role;

revoke all on function public.set_fund_loan_schedule(uuid, integer, date) from public, anon;
grant execute on function public.set_fund_loan_schedule(uuid, integer, date) to authenticated;

revoke all on function public.sign_fund_loan(uuid) from public, anon;
grant execute on function public.sign_fund_loan(uuid) to authenticated;

revoke all on function public.activate_fund_loan(uuid) from public, anon, authenticated;
grant execute on function public.activate_fund_loan(uuid) to service_role;

revoke all on function public.record_fund_loan_payment(uuid, integer, bigint) from public, anon, authenticated;
grant execute on function public.record_fund_loan_payment(uuid, integer, bigint) to service_role;

revoke all on function public.fund_loan_income_due_cents(uuid) from public, anon, authenticated;
grant execute on function public.fund_loan_income_due_cents(uuid) to authenticated, anon;

revoke all on function public.fund_loan_outstanding_cents(uuid) from public, anon, authenticated;
grant execute on function public.fund_loan_outstanding_cents(uuid) to authenticated, anon;
