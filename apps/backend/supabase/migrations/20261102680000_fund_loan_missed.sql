-- Fund loans get the same two rules family loans already carry: a missed
-- installment that opens a conversation (roadmap 1h's "missed installments"),
-- and a default plan that closes a loan under what both sides agreed to
-- (design.md's ladder for Fund loans: "pause, restructure, income-based
-- payments, and on true default, repayment when the home is sold or refinanced
-- with cash out. The Fund never forecloses.").
--
-- Two decisions worth the ledger:
--
-- 1. `fund_loan_missed_installments` is its OWN view, not a widening of
--    `loan_missed_installments`. Fund pauses push unpaid dates back instead of
--    flagging installment rows, so the family view's `not i.paused` predicate
--    would quietly drop every Fund row if the two were unioned — and a row that
--    belongs to one ladder or the other matters to the console reading it.
-- 2. A Fund loan has exactly one default plan: repay when the home is sold or
--    refinanced. `loan_forgiveness.loan_id` already references `family_loans`,
--    so a Fund loan cannot be forgiven even to ask for it, and the Fund never
--    forecloses: this door only stops collection, it never moves money.

alter table public.fund_loans add column defaulted_at timestamptz;

-- A Fund loan is "missed" on the same 10-day rule family loans use, and only
-- while it is collecting: a proposed or signed loan has nothing overdue yet,
-- and a loan closed under its plan is not being collected either. Income
-- schedules have no installment rows at all, so they can never look missed.
create view public.fund_loan_missed_installments with (security_invoker) as
select i.loan_id, i.seq, i.due_on, i.amount_cents - i.paid_cents as owed_cents
from public.fund_loan_installments i
join public.fund_loans l on l.id = i.loan_id
where i.paid_cents < i.amount_cents and i.due_on < current_date - 10
  and l.status in ('active', 'paused');

revoke all on public.fund_loan_missed_installments from anon, authenticated;
grant select on public.fund_loan_missed_installments to authenticated;

-- Service only: the partner's servicing event (or the mediation agreement)
-- decides a Fund loan is truly in default. Nothing here moves money — the Fund
-- never forecloses, so closing a loan stops collection and the lien keeps its
-- promise to be paid when the home is sold or refinanced.
create function public.apply_fund_loan_default(p_loan uuid) returns public.loan_status
language plpgsql security definer set search_path = '' as $$
declare
  l         public.fund_loans;
  v_left    bigint;
begin
  if not private.is_service() then
    raise exception 'a Fund loan closes under its plan by agreement, not by a client'
      using errcode = '42501';
  end if;
  select * into l from public.fund_loans where id = p_loan for update;
  if l.status not in ('active', 'paused') then
    raise exception 'fund loan not found, or not collecting' using errcode = 'P0002';
  end if;
  v_left := public.fund_loan_outstanding_cents(p_loan);
  if v_left <= 0 then
    raise exception 'nothing is outstanding: the loan is repaid, not in default'
      using errcode = '23514';
  end if;
  update public.fund_loans set status = 'defaulted', defaulted_at = now() where id = p_loan;
  perform private.audit('loan.default.fund', 'fund_loans', p_loan,
                        jsonb_build_object('outstanding_cents', v_left));
  return 'defaulted'::public.loan_status;
end $$;

revoke all on function public.apply_fund_loan_default(uuid) from public, anon, authenticated;
grant execute on function public.apply_fund_loan_default(uuid) to service_role;