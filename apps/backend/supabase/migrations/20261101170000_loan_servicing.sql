-- Loan servicing: the rules the daily loan-servicing job needs, and two
-- database checks the loan forms were leaning on (roadmap step 1g).
--
--   * an installment remembers when it was paid, so `my_reliability` counts
--     payments made on time rather than payments made at all;
--   * forgiving part of a loan takes that money off the tail of the schedule,
--     so the installments left still add up to exactly what is outstanding;
--   * a proposed schedule can't start in the past;
--   * `loan_default_due` is the agreed trigger for a default plan: a loan the
--     servicing job hands to `apply_default_plan` only when repayment really
--     has given up.

-- --- 1. installments keep the date they were paid ----------------------------------

-- The date is only ever set with the payment that finishes the installment
-- (or cleared, if the amount is ever re-opened), so the check below is the
-- invariant the trigger maintains.
alter table public.loan_installments
  add column paid_on date
    check (paid_on is null or paid_cents = amount_cents);

create function private.record_paid_on() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.loan_installments
  set paid_on = case when new.paid_cents = new.amount_cents then current_date end
  where loan_id = new.loan_id and seq = new.seq;
  return null;
end $$;

create trigger loan_installments_paid_on after update of paid_cents on public.loan_installments
  for each row execute function private.record_paid_on();

-- The count is what the name promises: paid on or before the installment's due
-- date. Installments paid before this migration shipped carry no paid date, so
-- they don't count as on time — the record understates rather than invents.
create or replace function public.my_reliability() returns table (
  subscription_payments bigint, installments_paid_on_time bigint, installments_due bigint,
  requests_paid bigint, member_since date
) language sql stable security definer set search_path = '' as $$
  select
    (select count(*) from public.subscription_payments where member_id = auth.uid() and status = 'captured'),
    (select count(*) from public.loan_installments i join public.family_loans l on l.id = i.loan_id
     where l.borrower_id = auth.uid() and i.paid_on is not null and i.paid_on <= i.due_on),
    (select count(*) from public.loan_installments i join public.family_loans l on l.id = i.loan_id
     where l.borrower_id = auth.uid() and i.due_on <= current_date),
    (select count(*) from public.requests where member_id = auth.uid() and status = 'paid'),
    (select joined_at::date from public.members where id = auth.uid());
$$;

-- --- 2. forgiveness shrinks the schedule -------------------------------------------

-- The lender forgives part of a loan: that money is never collected, so the
-- last unpaid installments stop at what is still outstanding. Cutting the tail
-- keeps two things true: the remaining installments still sum to exactly the
-- outstanding amount (so the totals check can't be broken by later payments),
-- and no installment's amount is cut below what the borrower has already paid.
create or replace function public.forgive_loan(p_loan uuid, p_amount_cents bigint, p_tax_year integer) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_left bigint := p_amount_cents;
  v_seqs integer[];
  v_seq  integer;
  v_row  public.loan_installments;
  v_cut  bigint;
begin
  if not exists (select 1 from public.family_loans where id = p_loan and lender_id = auth.uid()
                 and status in ('active', 'paused')) then
    raise exception 'only the lender can forgive an active loan' using errcode = '42501';
  end if;
  -- The cap is stated where it is refused, not left to the deferred totals
  -- trigger: a deferred constraint raises at COMMIT, which a client calling
  -- this function would never see — the same money the trigger backstops.
  if p_amount_cents > public.loan_outstanding_cents(p_loan) then
    raise exception 'payments and forgiveness exceed the principal' using errcode = '23514';
  end if;
  insert into public.loan_forgiveness (loan_id, tax_year, amount_cents) values (p_loan, p_tax_year, p_amount_cents);

  v_seqs := (select array_agg(seq order by seq desc) from public.loan_installments
              where loan_id = p_loan and paid_cents < amount_cents);

  -- The loop runs over a plain variable: every other loop in the repo does
  -- the same, because the stack's parser takes `array <variable>`; an
  -- expression in that slot is what CI's walk of this file choked on.
  if v_seqs is null then
    v_seqs := '{}';
  end if;

  -- The guard skips instead of exiting: the stack's parser stops at the
  -- break token (our only one; the repo's other loops all run the guarded
  -- way), and once v_left runs out the remaining iterations do nothing —
  -- same money leaves the schedule either way.
  foreach v_seq in array v_seqs loop
    if v_left > 0 then
      select * into v_row from public.loan_installments where loan_id = p_loan and seq = v_seq;
      v_cut := v_left;
      if v_row.amount_cents - v_row.paid_cents < v_left then
        v_cut := v_row.amount_cents - v_row.paid_cents;
      end if;
      if v_cut = v_row.amount_cents and v_row.paid_cents = 0 then
        -- Nothing would be left of this installment: drop it rather than keep a
        -- zero row (and a zero amount is refused by the schedule in the first place).
        delete from public.loan_installments where loan_id = p_loan and seq = v_seq;
      else
        update public.loan_installments set amount_cents = amount_cents - v_cut
        where loan_id = p_loan and seq = v_seq;
      end if;
      v_left := v_left - v_cut;
    end if;
  end loop;

  if public.loan_outstanding_cents(p_loan) = 0 then
    update public.family_loans set status = 'forgiven' where id = p_loan;
  end if;
end $$;

-- --- 3. a proposed schedule starts today or later ----------------------------------

create or replace function public.set_loan_schedule(p_loan uuid, p_months integer, p_first_due date) returns void
language plpgsql security definer set search_path = '' as $$
declare
  l        public.family_loans;
  v_each   bigint;
  v_month  date;
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
  -- The web form blocked this; the database has to agree with it, otherwise a
  -- loan could be proposed with payments already overdue on the day it is made.
  if p_first_due is null or p_first_due < current_date then
    raise exception 'the first installment cannot be due in the past' using errcode = '23514';
  end if;
  v_each := l.principal_cents / p_months;
  if v_each = 0 then
    raise exception 'too many installments for this amount' using errcode = '23514';
  end if;
  v_month := date_trunc('month', p_first_due)::date;
  if extract(day from p_first_due) > l.payment_day then
    v_month := (v_month + interval '1 month')::date;
  end if;
  delete from public.loan_installments where loan_id = p_loan;
  insert into public.loan_installments (loan_id, seq, due_on, amount_cents)
  select p_loan, n,
         (v_month + make_interval(months => n - 1, days => l.payment_day - 1))::date,
         case when n = p_months then l.principal_cents - v_each * (p_months - 1) else v_each end
  from generate_series(1, p_months) n;
  update public.family_loans set borrower_signed_at = null, lender_signed_at = null where id = p_loan;
end $$;

-- --- 4. the agreed trigger for a default plan -------------------------------------

-- What happens when repayment stops for good was agreed when the loan was
-- signed; what starts it is agreed here. A loan is handed to
-- `apply_default_plan` only when:
--   * it is still collecting (a loan the borrower paused by agreement is not),
--   * the borrower has used up the pause allowance they agreed to in 12 months,
--     so no pause offer is left, and
--   * three or more installments are unpaid and more than 10 days past due, so
--     the missed payments are a pattern and not one late month.
-- The loan-servicing job reads this view and calls `apply_default_plan` per
-- loan; nothing here changes a loan on its own, so the borrower keeps the
-- reminder and pause-offer conversations until the trigger is truly reached.

create function private.missed_count(p_loan uuid) returns integer
language sql stable security definer set search_path = '' as $$
  select count(*)::integer from public.loan_installments i
  where i.loan_id = p_loan and i.paid_cents < i.amount_cents and not i.paused
    and i.due_on < current_date - 10;
$$;

create function private.pause_months_used(p_loan uuid) returns integer
language sql stable security definer set search_path = '' as $$
  select coalesce(sum(months), 0)::integer from public.loan_pauses
  where loan_id = p_loan and started_on > current_date - interval '12 months';
$$;

create view public.loan_default_due with (security_barrier) as
select l.id, l.default_plan,
       private.missed_count(l.id) as missed_installments,
       private.pause_months_used(l.id) as pause_months_used
from public.family_loans l
where l.status = 'active'
  and private.missed_count(l.id) >= 3
  and private.pause_months_used(l.id) >= l.pause_months_per_year;

revoke all on public.loan_default_due from public, anon, authenticated;
grant select on public.loan_default_due to service_role;