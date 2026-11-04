-- Fund loan pauses and resumes (roadmap 3a's remaining leg: "restructuring
-- and pause flows"). The ladder matches `family_loans`: a borrower pauses
-- repayments on their own fund loan; within the loan's allowance no approval
-- is needed, beyond it the ask becomes a restructure the lending partner
-- owns. Pause pushes unpaid installments back, so the total owed never grows.
-- A paused loan still accepts payments — pausing buys back dates, not money.

alter table public.fund_loans
  add column pause_months_per_year smallint not null default 3
  check (pause_months_per_year between 0 and 12);

create table public.fund_loan_pauses (
  id          uuid primary key default gen_random_uuid(),
  loan_id     uuid not null references public.fund_loans (id) on delete cascade,
  months      smallint not null check (months between 1 and 12),
  reason      text check (length(reason) <= 500),
  started_on  date not null default current_date,
  created_by  uuid not null references public.members (id)
);

-- Pause rows are history: never edited, never removed.
create trigger fund_loan_pauses_append_only before update or delete on public.fund_loan_pauses
  for each row execute function private.forbid_change();

-- A pause is in effect until the latest started_on + months.
create function private.fund_pause_ends_on(p_loan uuid) returns date
language sql stable set search_path = '' as $$
  select max((started_on + make_interval(months => months))::date)
  from public.fund_loan_pauses where loan_id = p_loan;
$$;

-- The borrower pauses their own fund loan.
create function public.pause_fund_loan(p_loan uuid, p_months integer, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  l       public.fund_loans;
  v_used  integer;
begin
  select * into l from public.fund_loans where id = p_loan for update;
  if l.id is null or l.borrower_id <> auth.uid() then
    raise exception 'loan not found' using errcode = 'P0002';
  end if;
  if l.status not in ('active', 'paused') then
    raise exception 'only a collecting loan can be paused' using errcode = '23514';
  end if;
  select coalesce(sum(months), 0) into v_used from public.fund_loan_pauses
  where loan_id = p_loan and started_on > current_date - interval '12 months';
  if v_used + p_months > l.pause_months_per_year then
    raise exception 'this loan allows % pause months a year (% used); ask the lending Fund to restructure',
      l.pause_months_per_year, v_used using errcode = '23514';
  end if;

  insert into public.fund_loan_pauses (loan_id, months, reason, created_by)
  values (p_loan, p_months, p_reason, auth.uid());
  update public.fund_loan_installments
  set due_on = (due_on + make_interval(months => p_months))::date
  where loan_id = p_loan and paid_cents < amount_cents;
  update public.fund_loans set status = 'paused' where id = p_loan;
  perform private.audit('fund_loans.pause', 'fund_loans', p_loan,
    jsonb_build_object('months', p_months, 'reason', p_reason));
end $$;

-- The borrower can always resume early (pushed-back dates stay pushed back);
-- a service (the loan-servicing job) may only resume once the pause has run
-- out, so the job's view of "ended" is the schema's, never its own.
create function public.resume_fund_loan(p_loan uuid) returns public.loan_status
language plpgsql security definer set search_path = '' as $$
declare
  l       public.fund_loans;
  v_until date;
begin
  select * into l from public.fund_loans where id = p_loan for update;
  if l.id is null or not (l.borrower_id = auth.uid() or private.is_service()) then
    raise exception 'loan not found' using errcode = 'P0002';
  end if;
  if l.status <> 'paused' then
    raise exception 'only a paused loan can be resumed' using errcode = '23514';
  end if;
  if l.borrower_id is distinct from auth.uid() then
    v_until := private.fund_pause_ends_on(p_loan);
    if v_until > current_date then
      raise exception 'the borrower''s pause runs until %', v_until using errcode = '23514';
    end if;
  end if;
  update public.fund_loans set status = 'active' where id = p_loan;
  perform private.audit('fund_loans.resume', 'fund_loans', p_loan);
  return 'active';
end $$;

-- Service only: the loan-servicing job resumes every fund loan whose pause ran
-- out; which loans qualify is the schema's call, not the job's.
create function public.resume_ended_fund_pauses() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  update public.fund_loans l set status = 'active'
  where l.status = 'paused' and coalesce(private.fund_pause_ends_on(l.id), current_date) <= current_date;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- --- access --------------------------------------------------------------------

alter table public.fund_loan_pauses enable row level security;
revoke all on public.fund_loan_pauses from anon, authenticated;
create policy "borrowers read their fund loan pauses" on public.fund_loan_pauses for select to authenticated
  using (exists (select 1 from public.fund_loans l
                 where l.id = loan_id and l.borrower_id = auth.uid()));
grant select on public.fund_loan_pauses to authenticated;

revoke all on function public.pause_fund_loan(uuid, integer, text) from public, anon;
grant execute on function public.pause_fund_loan(uuid, integer, text) to authenticated;

revoke all on function public.resume_fund_loan(uuid) from public, anon;
grant execute on function public.resume_fund_loan(uuid) to authenticated, service_role;

revoke all on function public.resume_ended_fund_pauses() from public, anon, authenticated;
grant execute on function public.resume_ended_fund_pauses() to service_role;
