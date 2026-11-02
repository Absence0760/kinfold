-- The payments partner moves loan money; the daily loan-servicing job says
-- which installment is due and marks it paid (autopay: the borrower pays at
-- the payday through the partner). Nothing owned that write today, so an
-- unpaid-but-collecting loan could quietly become "paid" with no record.
--
-- record_loan_payment is the service's guarded way: only loans still
-- collecting move money, only up to what the installment still owes, and the
-- existing triggers (paid_on, mark_repaid) handle the dates and the loan's
-- final status. This closes the webhook's "records repayments" leg.

create function public.record_loan_payment(p_loan uuid, p_seq integer, p_amount_cents bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  l     public.family_loans;
  i     public.loan_installments;
  v_owed bigint;
begin
  if not private.is_service() then
    raise exception 'loan payments are moved by the service' using errcode = '42501';
  end if;
  select * into l from public.family_loans where id = p_loan;
  if l.status not in ('active', 'paused') then
    raise exception 'loan not found, or not collecting' using errcode = 'P0002';
  end if;
  select * into i from public.loan_installments where loan_id = p_loan and seq = p_seq for update;
  if i.id is null then
    raise exception 'installment not found' using errcode = 'P0002';
  end if;
  if i.paused then
    raise exception 'a paused installment is not being collected' using errcode = '23514';
  end if;
  v_owed := i.amount_cents - i.paid_cents;
  if p_amount_cents <= 0 or p_amount_cents > v_owed then
    raise exception 'loan payment must be between 1 and % cents', v_owed using errcode = '23514';
  end if;
  update public.loan_installments set paid_cents = paid_cents + p_amount_cents
  where loan_id = p_loan and seq = p_seq;
  perform private.audit('loan.payment', 'family_loans', p_loan,
                        jsonb_build_object('seq', p_seq, 'amount_cents', p_amount_cents));
  return v_owed - p_amount_cents;
end $$;

-- New relations carry Supabase's default grants: take them back, then the
-- service alone moves loan money — the borrower's side is the partner.
revoke all from function public.record_loan_payment(uuid, integer, bigint);
revoke all from function public.record_loan_payment(uuid, integer, bigint) to public, anon, authenticated;
grant execute on function public.record_loan_payment(uuid, integer, bigint) to service_role;
