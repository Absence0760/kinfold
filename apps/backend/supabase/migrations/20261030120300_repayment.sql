-- Repayment, hardship and the giving record.
--
-- How a borrower pays back, and what happens when they can't, is agreed when
-- the loan is signed, not improvised when things go wrong:
--   * installments are monthly by default, collected by the payment partner on
--     a day the borrower picks (payday), and never carry interest or late fees;
--   * a borrower can pause up to `pause_months_per_year` months in any 12 without
--     asking; the pause pushes every unpaid installment back, so the total owed
--     never changes;
--   * `default_plan` records what both sides agreed happens if repayment stops
--     for good: forgive the rest as a gift, repay from the home's sale or
--     refinance (secured loans only), or go to a mediator.
-- The giving record shows each member what they've put in and taken out. It is
-- private to the member and is never used to rank or refuse requests.

create type public.default_plan as enum ('mediate', 'forgive', 'repay_on_sale');

alter table public.family_loans
  add column payment_day           smallint not null default 1 check (payment_day between 1 and 28),
  add column pause_months_per_year smallint not null default 3 check (pause_months_per_year between 0 and 12),
  add column default_plan          public.default_plan not null default 'mediate',
  add column defaulted_at          timestamptz,
  add constraint family_loans_repay_on_sale_needs_lien check (default_plan <> 'repay_on_sale' or secured);

create table public.loan_pauses (
  id          uuid primary key default gen_random_uuid(),
  loan_id     uuid not null references public.family_loans (id) on delete cascade,
  months      smallint not null check (months between 1 and 12),
  reason      text check (length(reason) <= 500),
  started_on  date not null default current_date,
  created_by  uuid not null references public.members (id)
);

-- Borrower pauses repayments. Within the agreed allowance no approval is
-- needed; beyond it, the borrower and lender restructure instead.
create function public.pause_loan(p_loan uuid, p_months integer, p_reason text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  l       public.family_loans;
  v_used  integer;
begin
  select * into l from public.family_loans where id = p_loan for update;
  if l.id is null or l.borrower_id <> auth.uid() then
    raise exception 'loan not found' using errcode = 'P0002';
  end if;
  if l.status not in ('signed', 'active', 'paused') then
    raise exception 'only an active loan can be paused' using errcode = '23514';
  end if;
  select coalesce(sum(months), 0) into v_used from public.loan_pauses
  where loan_id = p_loan and started_on > current_date - interval '12 months';
  if v_used + p_months > l.pause_months_per_year then
    raise exception 'this loan allows % pause months a year (% used); ask your lender to restructure',
      l.pause_months_per_year, v_used using errcode = '23514';
  end if;

  insert into public.loan_pauses (loan_id, months, reason, created_by)
  values (p_loan, p_months, p_reason, auth.uid());
  update public.loan_installments
  set due_on = (due_on + make_interval(months => p_months))::date
  where loan_id = p_loan and paid_cents < amount_cents;
  update public.family_loans set status = 'paused' where id = p_loan;
end $$;

-- Missed = due, unpaid, and more than 10 days late, on a loan that is still
-- collecting. Never charged for; it starts a conversation (reminder, pause
-- offer, hardship request). Forgiven, defaulted, cancelled or repaid loans and
-- installments marked paused are not "missed": nothing is being collected.
create view public.loan_missed_installments with (security_invoker) as
select i.loan_id, i.seq, i.due_on, i.amount_cents - i.paid_cents as owed_cents
from public.loan_installments i
join public.family_loans l on l.id = i.loan_id
where i.paid_cents < i.amount_cents and i.due_on < current_date - 10
  and not i.paused and l.status in ('signed', 'active', 'paused');

-- Service role (after mediation, or at the agreed trigger) marks a loan as
-- defaulted and applies the plan both sides signed up to.
create function public.apply_default_plan(p_loan uuid) returns public.loan_status
language plpgsql security definer set search_path = '' as $$
declare
  l          public.family_loans;
  v_left     bigint;
  v_next     public.loan_status;
begin
  select * into l from public.family_loans where id = p_loan for update;
  if l.status not in ('active', 'paused', 'signed') then
    raise exception 'loan is %', l.status using errcode = '23514';
  end if;
  v_left := public.loan_outstanding_cents(p_loan);
  if l.default_plan = 'forgive' and v_left > 0 then
    insert into public.loan_forgiveness (loan_id, tax_year, amount_cents)
    values (p_loan, extract(year from current_date)::integer, v_left);
    v_next := 'forgiven';
  else
    -- 'repay_on_sale': the lien stays and is paid when the home is sold or
    -- refinanced; nobody forces a sale. 'mediate': a mediator's agreement
    -- comes next. Either way the loan stops collecting.
    v_next := 'defaulted';
  end if;
  update public.family_loans set status = v_next, defaulted_at = now() where id = p_loan;
  perform private.audit('loan.default.' || l.default_plan, 'family_loans', p_loan,
                        jsonb_build_object('outstanding_cents', v_left));
  return v_next;
end $$;

-- What a member has put in and taken out. Shown only to the member.
create function public.my_giving_record() returns table (
  subscriptions_paid_cents bigint,
  gifts_given_cents        bigint,
  lent_cents               bigint,
  received_from_pool_cents bigint,
  received_from_people_cents bigint,
  requests_paid            bigint
) language sql stable security definer set search_path = '' as $$
  select
    (select coalesce(sum(amount_cents), 0) from public.subscription_payments
     where member_id = auth.uid() and status = 'captured'),
    (select coalesce(sum(amount_cents), 0) from public.contributions
     where contributor_id = auth.uid() and source = 'gift' and status = 'captured'),
    (select coalesce(sum(amount_cents), 0) from public.contributions
     where contributor_id = auth.uid() and source = 'loan' and status = 'captured'),
    (select coalesce(sum(c.amount_cents), 0) from public.contributions c
     join public.requests r on r.id = c.request_id
     where r.member_id = auth.uid() and c.source = 'pool' and c.status = 'captured'),
    (select coalesce(sum(c.amount_cents), 0) from public.contributions c
     join public.requests r on r.id = c.request_id
     where r.member_id = auth.uid() and c.source in ('gift', 'loan') and c.status = 'captured'),
    (select count(*) from public.requests where member_id = auth.uid() and status = 'paid');
$$;

-- Pool requests a member has had paid in the last three years. Feeds the
-- member's share on their next request (cover terms), never their place in
-- the queue: frequent claimants pay a bigger part themselves, they don't wait
-- longer or get refused.
--
-- A member may ask only about themselves (the service role, with no auth.uid(),
-- may ask about anyone). "Paid" is dated by the payout actually sent, not by
-- when the request was submitted: a request that waited months for the pool
-- was paid when the money went out.
create function public.pool_requests_paid_3y(p_member uuid) returns integer
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is not null and p_member is distinct from auth.uid() then
    raise exception 'you can only see your own record' using errcode = '42501';
  end if;
  return (
    select count(*)::integer from public.requests r
    where r.member_id = p_member and r.status = 'paid' and r.funding in ('pool', 'both')
      and exists (select 1 from public.payouts p
                  where p.request_id = r.id and p.status = 'sent'
                    and p.created_at > now() - interval '3 years'));
end $$;

alter table public.loan_pauses enable row level security;
revoke all on public.loan_pauses, public.loan_missed_installments from anon, authenticated;

create policy "borrower and lender read pauses" on public.loan_pauses for select to authenticated
  using (exists (select 1 from public.family_loans l where l.id = loan_id and auth.uid() in (l.borrower_id, l.lender_id)));
grant select on public.loan_pauses to authenticated;
grant select on public.loan_missed_installments to authenticated;

revoke all on function public.pause_loan(uuid, integer, text), public.apply_default_plan(uuid),
  public.my_giving_record(), public.pool_requests_paid_3y(uuid) from public, anon, authenticated;
grant execute on function public.pause_loan(uuid, integer, text), public.my_giving_record(),
  public.pool_requests_paid_3y(uuid) to authenticated;
-- apply_default_plan is service-role only.
