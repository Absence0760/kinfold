-- Fund loan restructures (the rest of 3a's ladder): beyond the pause allowance
-- the borrower asks the lending Fund to restructure — smaller payments over a
-- longer term, or a new start date. The borrower stages the ask; the partner's
-- servicing event applies it. Only unpaid installments move: money already
-- returned stays returned, and the outstanding figure never changes — a
-- restructure repays the same money over different dates, never less.

create table public.fund_loan_restructures (
  id                   uuid primary key default gen_random_uuid(),
  loan_id              uuid not null references public.fund_loans (id) on delete cascade,
  months               integer not null check (months between 1 and 480),
  first_due            date not null,
  borrower_signed_at   timestamptz not null default now(),
  applied_at           timestamptz,
  created_by           uuid not null references public.members (id),
  check (months > 0),
  check (applied_at is null or borrower_signed_at <= applied_at)
);

-- The borrower stages a restructure on their own collecting monthly loan. The
-- Fund has already signed the agreement (it is the lender), so a staged ask
-- only waits for the partner's servicing event.
create function public.restructure_fund_loan(p_loan uuid, p_months integer, p_first_due date)
returns void language plpgsql security definer set search_path = '' as $$
declare
  l          public.fund_loans;
  v_left     bigint;
begin
  select * into l from public.fund_loans where id = p_loan for update;
  if l.id is null or l.borrower_id <> auth.uid() then
    raise exception 'loan not found' using errcode = 'P0002';
  end if;
  if l.status not in ('active', 'paused') then
    raise exception 'only a collecting loan can be restructured' using errcode = '23514';
  end if;
  if l.schedule <> 'monthly' then
    raise exception 'income payments are computed from income; nothing to reschedule' using errcode = '23514';
  end if;
  if exists (select 1 from public.fund_loan_restructures
             where loan_id = p_loan and applied_at is null) then
    raise exception 'a restructure the partner has not answered yet is already pending' using errcode = '23514';
  end if;
  v_left := public.fund_loan_outstanding_cents(p_loan);
  if v_left = 0 then
    raise exception 'a loan that owes nothing has nothing to restructure' using errcode = '23514';
  end if;
  if p_first_due < current_date then
    raise exception 'a restructured schedule can''t start in the past' using errcode = '23514';
  end if;
  if v_left / p_months = 0 then
    raise exception 'too many installments for what is left to pay' using errcode = '23514';
  end if;
  insert into public.fund_loan_restructures (loan_id, months, first_due, created_by)
  values (p_loan, p_months, p_first_due, auth.uid());
  perform private.audit('fund_loans.restructure_requested', 'fund_loans', p_loan,
    jsonb_build_object('months', p_months, 'first_due', p_first_due));
end $$;

-- Service only: the loan-servicing job answers the borrower's ask by re-spreading
-- only the unpaid installments over the new dates. Installments already paid
-- keep their dates and amounts, so the money returned so far is untouched.
create function public.apply_fund_loan_restructure(p_loan uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  l        public.fund_loans;
  r        public.fund_loan_restructures;
  v_left   bigint;
  v_each   bigint;
  v_seq    integer := 0;
  v_max    integer;
  v_first  date;
begin
  if not private.is_service() then
    raise exception 'restructures are applied by the lending partner''s servicing event' using errcode = '42501';
  end if;
  select * into l from public.fund_loans where id = p_loan;
  if l.status not in ('active', 'paused') then
    raise exception 'fund loan not found, or not collecting' using errcode = 'P0002';
  end if;
  select * into r from public.fund_loan_restructures where loan_id = p_loan and applied_at is null;
  if r.id is null then
    raise exception 'no restructure is pending on this loan' using errcode = 'P0002';
  end if;
  v_left := public.fund_loan_outstanding_cents(p_loan);
  if v_left = 0 then
    update public.fund_loan_restructures set applied_at = now() where id = r.id;
    return false;
  end if;

  select coalesce(max(seq), 0) into v_max from public.fund_loan_installments
  where loan_id = p_loan;
  delete from public.fund_loan_installments where loan_id = p_loan and paid_cents < amount_cents;
  v_each := v_left / r.months;
  v_first := r.first_due;
  for v_seq in 1 .. r.months loop
    insert into public.fund_loan_installments (loan_id, seq, due_on, amount_cents)
    values (p_loan, v_max + v_seq,
            (v_first + make_interval(months => v_seq - 1))::date,
            case when v_seq = r.months then v_left - v_each * (r.months - 1)
                 else v_each end);
  end loop;

  update public.fund_loan_restructures set applied_at = now() where id = r.id;
  perform private.audit('fund_loans.restructure_applied', 'fund_loans', p_loan,
    jsonb_build_object('months', r.months, 'first_due', r.first_due, 'left_cents', v_left));
  return true;
end $$;

alter table public.fund_loan_restructures enable row level security;
revoke all on public.fund_loan_restructures from anon, authenticated;
create policy "borrowers read their fund loan restructures" on public.fund_loan_restructures for select to authenticated
  using (exists (select 1 from public.fund_loans l
                 where l.id = loan_id and l.borrower_id = auth.uid()));
grant select on public.fund_loan_restructures to authenticated;

revoke all on function public.restructure_fund_loan(uuid, integer, date) from public, anon;
grant execute on function public.restructure_fund_loan(uuid, integer, date) to authenticated;

revoke all on function public.apply_fund_loan_restructure(uuid) from public, anon, authenticated;
grant execute on function public.apply_fund_loan_restructure(uuid) to service_role;
