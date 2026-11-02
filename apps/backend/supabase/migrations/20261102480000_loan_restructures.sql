-- Family loan restructures (ladder step 3, design.md:137: "smaller payments
-- over a longer term, or a new start date. A new schedule both sides sign").
-- The borrower stages the new schedule; the lender signs it; when both sides
-- have signed, the unpaid installments re-spread over the new dates. Money
-- already returned keeps its date and amount, and the re-spread covers
-- exactly what is still owed — a restructure repays the same money over
-- different dates, never less.

create table public.loan_restructures (
  id                uuid primary key default gen_random_uuid(),
  loan_id           uuid not null references public.family_loans (id) on delete cascade,
  months            integer not null check (months between 1 and 480),
  first_due         date not null,
  stager_signed_at  timestamptz not null default now(),
  other_signed_at   timestamptz,
  created_by        uuid not null references public.members (id)
);


-- Either side stages a restructure on their own collecting loan. A new
-- schedule is only complete once the other side signs it, so a staged ask
-- moves no money.
create function public.restructure_loan(p_loan uuid, p_months integer, p_first_due date)
returns void language plpgsql security definer set search_path = '' as $$
declare
  l       public.family_loans;
  v_left  bigint;
begin
  select * into l from public.family_loans where id = p_loan for update;
  if l.id is null or auth.uid() not in (l.borrower_id, l.lender_id) then
    raise exception 'loan not found' using errcode = 'P0002';
  end if;
  if l.status not in ('active', 'paused') then
    raise exception 'only a collecting loan can be restructured' using errcode = '23514';
  end if;
  if exists (select 1 from public.loan_restructures
             where loan_id = p_loan and other_signed_at is null) then
    raise exception 'a restructure the other side has not signed yet is already pending' using errcode = '23514';
  end if;
  select coalesce(sum(amount_cents - paid_cents), 0) into v_left from public.loan_installments
  where loan_id = p_loan;
  if v_left = 0 then
    raise exception 'a loan that owes nothing has nothing to restructure' using errcode = '23514';
  end if;
  if p_first_due < current_date then
    raise exception 'a restructured schedule can''t start in the past' using errcode = '23514';
  end if;
  if v_left / p_months = 0 then
    raise exception 'too many installments for what is left to pay' using errcode = '23514';
  end if;
  insert into public.loan_restructures (loan_id, months, first_due, created_by)
  values (p_loan, p_months, p_first_due, auth.uid());
  perform private.audit('loan_restructures.staged', 'loan_restructures', p_loan,
    jsonb_build_object('months', p_months, 'first_due', p_first_due, 'stager', auth.uid()));
end $$;

-- The other side signs the staged ask: the schedule both sides agreed to. On
-- the signing the unpaid installments re-spread — the new rows carry only
-- unpaid money, so what's already returned never moves twice.
create function public.sign_loan_restructure(p_loan uuid) returns public.loan_status
language plpgsql security definer set search_path = '' as $$
declare
  l     public.family_loans;
  r     public.loan_restructures;
  v_left  bigint;
  v_each  bigint;
  v_seq   integer := 0;
  v_max   integer;
  v_month date;
begin
  select * into l from public.family_loans where id = p_loan for update;
  if l.id is null or auth.uid() not in (l.borrower_id, l.lender_id) then
    raise exception 'loan not found' using errcode = 'P0002';
  end if;
  if l.status not in ('active', 'paused') then
    raise exception 'loan not found, or not collecting' using errcode = 'P0002';
  end if;
  select * into r from public.loan_restructures
    where loan_id = p_loan and other_signed_at is null
    and created_by is distinct from auth.uid();
  if r.id is null then
    raise exception 'no restructure is waiting for this side to sign' using errcode = 'P0002';
  end if;
  select coalesce(sum(amount_cents - paid_cents), 0) into v_left from public.loan_installments
  where loan_id = p_loan;
  if v_left > 0 then
    select coalesce(max(seq), 0) into v_max from public.loan_installments where loan_id = p_loan;
    delete from public.loan_installments where loan_id = p_loan and paid_cents < amount_cents;
    v_each := v_left / r.months;
    -- Same day-of-month rule as set_loan_schedule: installments land on the
    -- loan's payment day, the first no earlier than the agreed start.
    v_month := date_trunc('month', r.first_due)::date;
    if extract(day from r.first_due) > l.payment_day then
      v_month := (v_month + interval '1 month')::date;
    end if;
    for v_seq in 1 .. r.months loop
      insert into public.loan_installments (loan_id, seq, due_on, amount_cents)
      values (p_loan, v_max + v_seq,
              (v_month + make_interval(months => v_seq - 1, days => l.payment_day - 1))::date,
              case when v_seq = r.months then v_left - v_each * (r.months - 1)
                   else v_each end);
    end loop;
  end if;
  update public.loan_restructures set other_signed_at = now() where id = r.id;
  perform private.audit('loan_restructures.signed', 'loan_restructures', p_loan,
    jsonb_build_object('months', r.months, 'first_due', r.first_due,
                       'left_cents', v_left, 'stager', r.created_by));
  return l.status;
end $$;

alter table public.loan_restructures enable row level security;
revoke all on public.loan_restructures from anon, authenticated;
create policy "both sides read loan restructures" on public.loan_restructures for select to authenticated
  using (exists (select 1 from public.family_loans l
                 where l.id = loan_id and auth.uid() in (l.borrower_id, l.lender_id)));
grant select on public.loan_restructures to authenticated;

revoke all from function public.restructure_loan(uuid, integer, date);
revoke all from function public.restructure_loan(uuid, integer, date) to public, anon;
grant execute on function public.restructure_loan(uuid, integer, date) to authenticated;

revoke all from function public.sign_loan_restructure(uuid);
revoke all from function public.sign_loan_restructure(uuid) to public, anon;
grant execute on function public.sign_loan_restructure(uuid) to authenticated;
