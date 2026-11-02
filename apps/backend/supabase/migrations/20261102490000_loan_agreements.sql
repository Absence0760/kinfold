-- Family loan agreement paperwork (1g's "written agreement ... paperwork").
-- Once both sides have signed, the loan-servicing event finalizes the
-- agreement in writing - what was agreed, in plain words, recorded on the
-- loan. This written document is what makes an unpaid family loan qualify as
-- a bad-debt tax deduction for the lender (design.md:149): proper paperwork
-- an accountant can cite years later, which an informal handshake loan
-- usually can't carry. The text is history: written once, never edited.

alter table public.family_loans
  add column agreement_text text check (agreement_text is null or length(agreement_text) >= 120),
  add column agreement_finalized_at timestamptz;

-- The loan-servicing job finalizes one loan's agreement: the amount, the
-- schedule as set, the pause allowance and the default plan - everything
-- both sides stood behind when they signed. Replaying on a finalized loan
-- is a no-op.
create function public.finalize_loan_agreement(p_loan uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  l          public.family_loans;
  v_first    date;
  v_months   integer;
  v_signed   timestamptz;
  v_text     text;
begin
  if not private.is_service() then
    raise exception 'agreements are finalized by the loan-servicing event' using errcode = '42501';
  end if;
  select * into l from public.family_loans where id = p_loan for update;
  if l.id is null or l.status in ('proposed', 'cancelled')
     or l.borrower_signed_at is null or l.lender_signed_at is null then
    raise exception 'loan not found, or not yet signed by both sides' using errcode = 'P0002';
  end if;
  if l.agreement_text is not null then
    return;
  end if;

  select coalesce(min(due_on), current_date) into v_first from public.loan_installments where loan_id = p_loan;
  select coalesce(count(*), 0)::integer into v_months from public.loan_installments where loan_id = p_loan;
  v_signed := greatest(l.borrower_signed_at, l.lender_signed_at);

  v_text := format(
    'Written agreement: both sides signed on %s. The lender lends $%s at zero interest, '
    || 'repaid in %s monthly installments on day %s of each month, first due %s. '
    || 'The borrower may pause repayment for up to %s months in any 12; a pause moves dates, '
    || 'never the amount owed. %s',
    to_char(v_signed::date, 'YYYY-MM-DD'),
    '$' || to_char(l.principal_cents / 100.0, 'fm9,999,990.00'),
    v_months::text,
    l.payment_day::text,
    to_char(v_first, 'YYYY-MM-DD'),
    l.pause_months_per_year::text,
    case
      when l.secured then format(
        'The loan is secured by a lien on the home; the IRS minimum rate %s basis points '
        || 'is written for tax paperwork. If repayment stops, the agreed default plan (%s) applies.',
        coalesce(l.imputed_rate_bps, 0)::text,
        l.default_plan::text)
      else format('If repayment stops, the agreed default plan (%s) applies.', l.default_plan::text)
    end);

  update public.family_loans
    set agreement_text = v_text, agreement_finalized_at = now()
    where id = p_loan;
  perform private.audit('loan_agreements.finalized', 'family_loans', p_loan,
    jsonb_build_object('signed_on', to_char(v_signed::date, 'YYYY-MM-DD')));
end $$;

-- Service only: finalize every signed loan that has no agreement yet, so the
-- job's sweep is the schema's call. Returns how many were written.
create function public.finalize_signed_loan_agreements() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_id  uuid;
  v_ids uuid[];
  v_count integer := 0;
begin
  if not private.is_service() then
    raise exception 'agreements are finalized by the loan-servicing event' using errcode = '42501';
  end if;
  select array(
    select l.id from public.family_loans l
    where l.agreement_text is null
      and l.borrower_signed_at is not null and l.lender_signed_at is not null
      and l.status not in ('proposed', 'cancelled')
  ) into v_ids;
  foreach v_id in array v_ids loop
    perform public.finalize_loan_agreement(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

revoke all from function public.finalize_loan_agreement(uuid);
revoke all from function public.finalize_loan_agreement(uuid) to public, anon, authenticated;
grant execute on function public.finalize_loan_agreement(uuid) to service_role;

revoke all from function public.finalize_signed_loan_agreements();
revoke all from function public.finalize_signed_loan_agreements() to public, anon, authenticated;
grant execute on function public.finalize_signed_loan_agreements() to service_role;
