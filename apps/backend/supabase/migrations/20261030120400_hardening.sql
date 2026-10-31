-- Hardening: closes gaps found reviewing the first four migrations.
--
--   * accounts are closed, never deleted (financial records are kept ~5 years);
--   * money is captured only once every loan behind it is signed, and refunded
--     when a request with captured money is withdrawn, refused or expires;
--   * roles count only for active members; a refused request is reopened only
--     by an upheld appeal; one appeal per refusal; a panel member never decides
--     an appeal on a request they reviewed; the member never learns who
--     reviewed their request;
--   * loans: terms are set before signing, installments land on the payment
--     day, 'active' means disbursed (forgive and pause need it), pauses end,
--     and paying the last cent marks a loan repaid;
--   * request_raised_cents answers only people who can see the request;
--   * pledges and pool grants wait for a verified payee;
--   * post_journal is reachable by the service role, and needs two lines;
--   * the service role gets the privileges the edge functions need.
--
-- Same conventions as the earlier migrations: security definer functions pin
-- `search_path = ''`, and function grants are re-stated in full at the end.

-- --- helpers ------------------------------------------------------------------

-- True for the service role (edge functions) and for backend callers with no
-- signed-in user. Clients always carry a user id and the 'authenticated' role.
-- (current_user can't tell: inside a security definer function it is the owner.)
create function private.is_service() returns boolean
language sql stable set search_path = '' as $$
  select auth.uid() is null or coalesce(auth.role(), '') = 'service_role';
$$;

-- Raised so far, for internal callers (pledge, mark_funded, the pool run).
create function private.raised_cents(p_request uuid) returns bigint
language sql stable set search_path = '' as $$
  select coalesce(sum(amount_cents), 0) from public.contributions
  where request_id = p_request and status in ('pledged', 'captured');
$$;

-- --- 5. roles count only for active members -------------------------------------

create or replace function public.has_role(p_role public.member_role) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.member_roles mr
    join public.members m on m.id = mr.member_id
    where mr.member_id = auth.uid() and mr.role = p_role and m.status = 'active'
  );
$$;

-- --- 1. closing an account ------------------------------------------------------
-- Members are never deleted: requests are `on delete restrict`, history is
-- append-only, and financial records must be kept for years. Deleting the
-- auth.users row fails for any member with a request, pledge, review or loan.
-- The account-deletion edge function calls close_account() as the member, then
-- disables (never deletes) the auth user.

create function public.close_account() returns void
language plpgsql security definer set search_path = '' as $$
declare
  m public.members;
begin
  select * into m from public.members where id = auth.uid() for update;
  if m.id is null then
    raise exception 'member not found' using errcode = 'P0002';
  end if;
  if m.status = 'closed' then
    raise exception 'this account is already closed' using errcode = '23514';
  end if;
  if exists (select 1 from public.requests where member_id = m.id
             and status not in ('paid', 'refused', 'withdrawn', 'expired')) then
    raise exception 'withdraw or finish your open requests before closing your account' using errcode = '23514';
  end if;
  if exists (select 1 from public.appeals where member_id = m.id and status = 'open') then
    raise exception 'your appeal is still open; close your account once it is decided' using errcode = '23514';
  end if;
  if exists (select 1 from public.family_loans l where m.id in (l.borrower_id, l.lender_id)
             and (l.status in ('proposed', 'signed', 'active', 'paused')
                  or (l.status = 'defaulted' and public.loan_outstanding_cents(l.id) > 0))) then
    raise exception 'settle the loans you owe or are owed before closing your account' using errcode = '23514';
  end if;
  if exists (select 1 from public.contributions where contributor_id = m.id and status = 'pledged') then
    raise exception 'your pledges are still waiting to be collected' using errcode = '23514';
  end if;

  update public.members set status = 'closed', display_name = 'Closed account' where id = m.id;
  -- A request's asset stays as part of its financial record, scrubbed; the rest go.
  delete from public.covered_assets a
  where a.member_id = m.id and not exists (select 1 from public.requests r where r.asset_id = a.id);
  update public.covered_assets set description = 'Closed account', removed_on = coalesce(removed_on, current_date)
  where member_id = m.id;
  delete from public.allocation_preferences where member_id = m.id;
  delete from public.request_supporters where member_id = m.id;
  update public.subscriptions set ends_on = greatest(current_date, starts_on)
  where member_id = m.id and ends_on is null;
  perform private.audit('account.closed', 'members', m.id);
end $$;

-- A closed account's name stays scrubbed.
drop policy "members edit themselves" on public.members;
create policy "members edit themselves" on public.members for update to authenticated
  using (id = auth.uid() and status <> 'closed') with check (id = auth.uid() and status <> 'closed');

-- --- 14. record_score on a missing request ----------------------------------------

create or replace function public.record_score(
  p_request uuid, p_score smallint, p_reasons jsonb,
  p_model text, p_model_version text, p_prompt_version text, p_inputs_sha256 text
) returns public.request_status
language plpgsql security definer set search_path = '' as $$
declare
  r       public.requests;
  v_min   smallint;
  v_next  public.request_status;
begin
  select * into r from public.requests where id = p_request for update;
  if r.id is null then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if r.status <> 'scoring' then
    raise exception 'request is not waiting for a score' using errcode = '23514';
  end if;

  insert into public.scores (request_id, score, reasons, model, model_version, prompt_version, inputs_sha256)
  values (p_request, p_score, p_reasons, p_model, p_model_version, p_prompt_version, p_inputs_sha256);

  select coalesce(min_score, 70) into v_min
  from public.fund_settings where fund = public.fund_for_kind(r.kind);

  v_next := case
    when exists (select 1 from private.fraud_signals
                 where request_id = p_request and severity = 'high' and resolved_at is null) then 'in_review'
    when p_score < v_min then 'needs_evidence'
    else 'open'
  end;

  update public.requests set status = v_next, current_score = p_score where id = p_request;
  return v_next;
end $$;

-- --- 4. a refused request is reopened only by an upheld appeal ------------------------

create or replace function public.record_review(p_request uuid, p_decision public.review_decision, p_reason text)
returns public.request_status
language plpgsql security definer set search_path = '' as $$
declare
  r       public.requests;
  v_me    public.members;
  v_next  public.request_status;
begin
  if not public.has_role('reviewer') then
    raise exception 'reviewers only' using errcode = '42501';
  end if;
  select * into r from public.requests where id = p_request for update;
  select * into v_me from public.members where id = auth.uid();
  if r.member_id = v_me.id then
    raise exception 'you cannot review your own request' using errcode = '42501';
  end if;
  if (select region from public.members where id = r.member_id) = v_me.region then
    raise exception 'requests are reviewed by someone outside the member''s region' using errcode = '42501';
  end if;
  -- Not 'refused': only an upheld appeal (decide_appeal) reopens a refusal.
  if r.status not in ('in_review', 'needs_evidence', 'open', 'funded') then
    raise exception 'request is not reviewable in status %', r.status using errcode = '23514';
  end if;

  insert into public.reviews (request_id, reviewer_id, decision, reason)
  values (p_request, v_me.id, p_decision, p_reason);
  perform private.audit('review.' || p_decision, 'requests', p_request, jsonb_build_object('reason', p_reason));

  v_next := case p_decision
    when 'approve' then 'open'
    when 'needs_evidence' then 'needs_evidence'
    when 'refuse' then 'refused'
    when 'escalate' then 'in_review'
  end;

  -- Reaching some targets takes two steps (e.g. open -> in_review -> refused).
  if r.status <> 'in_review' and v_next <> r.status
     and not exists (select 1 from public.request_transitions where from_status = r.status and to_status = v_next) then
    update public.requests set status = 'in_review' where id = p_request;
  end if;
  if v_next <> (select status from public.requests where id = p_request) then
    update public.requests set status = v_next where id = p_request;
  end if;
  -- Approving a request whose pledges already cover it (e.g. a funded request
  -- sent back for review) returns it to funded; left 'open' it could never
  -- take another pledge or pool grant, nor reach payout.
  if v_next = 'open' then
    update public.requests set status = 'funded'
    where id = p_request and status = 'open' and private.raised_cents(p_request) >= amount_cents;
  end if;
  return (select status from public.requests where id = p_request);
end $$;

-- --- 7. one appeal per refusal ---------------------------------------------------
-- Each refusal is one transition into 'refused' in request_events, and an appeal
-- can only be filed while the request is refused, so "an appeal already filed
-- since the latest refusal" is "as many appeals as refusals". Counting rather
-- than comparing timestamps keeps it exact when both happen in one transaction.

create or replace function public.file_appeal(p_request uuid, p_reason text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  perform 1 from public.requests where id = p_request and member_id = auth.uid() and status = 'refused' for update;
  if not found then
    raise exception 'only a refused request of yours can be appealed' using errcode = '42501';
  end if;
  if (select count(*) from public.appeals where request_id = p_request)
     >= (select count(*) from public.request_events where request_id = p_request and to_status = 'refused') then
    raise exception 'this refusal has already been appealed' using errcode = '23505';
  end if;
  insert into public.appeals (request_id, member_id, reason) values (p_request, auth.uid(), p_reason)
  returning id into v_id;
  return v_id;
end $$;

-- --- 6. a panel member never decides an appeal on a request they reviewed ---------------

create or replace function public.decide_appeal(p_appeal uuid, p_uphold boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
  a public.appeals;
begin
  if not public.has_role('panel') then
    raise exception 'appeal panel only' using errcode = '42501';
  end if;
  select * into a from public.appeals where id = p_appeal and status = 'open' for update;
  if a.id is null then
    raise exception 'appeal not found or already decided' using errcode = 'P0002';
  end if;
  if a.member_id = auth.uid() then
    raise exception 'you cannot decide your own appeal' using errcode = '42501';
  end if;
  if exists (select 1 from public.reviews where request_id = a.request_id and reviewer_id = auth.uid()) then
    raise exception 'you reviewed this request; another panel member decides the appeal' using errcode = '42501';
  end if;
  update public.appeals
  set status = case when p_uphold then 'upheld'::public.appeal_status else 'denied' end,
      decided_by = auth.uid(), decided_at = now()
  where id = p_appeal;
  if p_uphold then
    update public.requests set status = 'in_review' where id = a.request_id;
  end if;
  perform private.audit(case when p_uphold then 'appeal.upheld' else 'appeal.denied' end,
                        'appeals', p_appeal);
end $$;

-- --- 8. the member never learns who reviewed their request ----------------------------
-- Column grants can't tell the owner from the panel (both are `authenticated`),
-- so the owner loses direct access to `reviews` and reads decisions through
-- my_request_reviews(), which omits reviewer_id. The panel keeps full rows on
-- requests that aren't their own, and a reviewer sees the reviews they wrote.

drop policy "members read reviews of their requests" on public.reviews;
create policy "panel and authors read reviews" on public.reviews for select to authenticated
  using (reviewer_id = auth.uid()
         or (public.has_role('panel')
             and not exists (select 1 from public.requests r where r.id = request_id and r.member_id = auth.uid())));

create function public.my_request_reviews(p_request uuid)
returns table (decision public.review_decision, reason text, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  if not exists (select 1 from public.requests where id = p_request and member_id = auth.uid()) then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  return query
    select rv.decision, rv.reason, rv.created_at from public.reviews rv
    where rv.request_id = p_request order by rv.created_at, rv.id;
end $$;

-- --- 15. request_raised_cents answers only people who can see the request ---------------

create or replace function public.request_raised_cents(p_request uuid) returns bigint
language sql stable security definer set search_path = '' as $$
  select private.raised_cents(r.id)
  from public.requests r
  where r.id = p_request
    and (private.is_service()
         or r.member_id = auth.uid()
         or public.is_supporter(r.id)
         -- on the board (same rule as public.board_requests)
         or (r.status in ('open', 'funded', 'paid') and r.funding in ('pool', 'both')
             and r.public_summary is not null and public.is_active_member()));
$$;

create or replace function private.mark_funded() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.requests r set status = 'funded'
  where r.id = new.request_id and r.status = 'open'
    and private.raised_cents(r.id) >= r.amount_cents;
  return null;
end $$;

-- --- 16. pledges and pool grants wait for a verified payee ------------------------------

create or replace function public.pledge(p_request uuid, p_amount_cents bigint, p_source public.contribution_source)
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
  -- Verification can run while the request is scored; money waits for it.
  if not exists (select 1 from public.payees where id = r.payee_id and status = 'verified') then
    raise exception 'pledges open once the request''s payee is verified' using errcode = '23514';
  end if;

  v_left := r.amount_cents - private.raised_cents(p_request);
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

create or replace function public.run_pool_allocation(p_fund public.fund, p_available_cents bigint) returns uuid
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
         r.amount_cents - private.raised_cents(r.id) as need
  from public.requests r
  join public.payees p on p.id = r.payee_id and p.status = 'verified'  -- waits for a verified payee
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

-- --- 2. capture only once every loan is signed ------------------------------------------
-- Service role, after the payment partner confirms the charge.

create function public.capture_contributions(p_request uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  r       public.requests;
  v_count integer;
begin
  select * into r from public.requests where id = p_request for update;
  if r.id is null then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if r.status <> 'funded' then
    raise exception 'only a funded request''s pledges are captured' using errcode = '23514';
  end if;
  if exists (select 1 from public.contributions c
             join public.family_loans l on l.id = c.loan_id
             where c.request_id = p_request and c.source = 'loan' and c.status = 'pledged'
               and l.status <> 'signed') then
    raise exception 'every loan must be signed by both sides before money is captured' using errcode = '23514';
  end if;
  update public.contributions set status = 'captured' where request_id = p_request and status = 'pledged';
  get diagnostics v_count = row_count;
  perform private.audit('contributions.captured', 'requests', p_request, jsonb_build_object('count', v_count));
  return v_count;
end $$;

-- --- 3. refunds ----------------------------------------------------------------------
-- Pledges are released, but money already captured on a request that then ends
-- unpaid (withdrawn, refused, expired) goes back. The payments webhook reads
-- refunds_due, refunds through the partner, then calls mark_refunded.

alter table public.contributions
  add column refund_partner_ref text unique,
  add column refunded_at        timestamptz;

create view public.refunds_due with (security_barrier) as
select c.id as contribution_id, c.request_id, r.status as request_status, c.source, c.contributor_id,
       c.amount_cents, c.loan_id, c.pool_allocation_id, c.partner_ref, c.created_at
from public.contributions c
join public.requests r on r.id = c.request_id
where c.status = 'captured' and r.status in ('withdrawn', 'refused', 'expired');

create function public.mark_refunded(p_contribution uuid, p_partner_ref text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_partner_ref is null or p_partner_ref = '' then
    raise exception 'a refund needs the partner''s reference' using errcode = '23514';
  end if;
  -- Webhooks retry: the same refund reported twice is a no-op.
  if exists (select 1 from public.contributions where id = p_contribution and status = 'refunded'
             and refund_partner_ref = p_partner_ref) then
    return;
  end if;
  update public.contributions c
  set status = 'refunded', refund_partner_ref = p_partner_ref, refunded_at = now()
  from public.requests r
  where c.id = p_contribution and r.id = c.request_id
    and c.status = 'captured' and r.status in ('withdrawn', 'refused', 'expired');
  if not found then
    raise exception 'contribution not found or not due a refund' using errcode = 'P0002';
  end if;
  perform private.audit('contribution.refunded', 'contributions', p_contribution,
                        jsonb_build_object('partner_ref', p_partner_ref));
end $$;

-- --- 10. loan terms, and installments on the payment day ---------------------------------

create function public.set_loan_terms(
  p_loan uuid, p_payment_day integer, p_pause_months_per_year integer, p_default_plan public.default_plan
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  l public.family_loans;
begin
  select * into l from public.family_loans where id = p_loan for update;
  if l.id is null or auth.uid() not in (l.borrower_id, l.lender_id) then
    raise exception 'loan not found' using errcode = 'P0002';
  end if;
  if l.status <> 'proposed' then
    raise exception 'a signed loan''s terms can only change by agreement (restructure)' using errcode = '23514';
  end if;
  if p_payment_day not between 1 and 28 then
    raise exception 'payment day must be 1 to 28' using errcode = '23514';
  end if;
  if p_pause_months_per_year not between 0 and 12 then
    raise exception 'pause allowance must be 0 to 12 months a year' using errcode = '23514';
  end if;
  if p_default_plan = 'repay_on_sale' and not l.secured then
    raise exception 'repay on sale needs a loan secured by a lien' using errcode = '23514';
  end if;
  update public.family_loans
  set payment_day = p_payment_day, pause_months_per_year = p_pause_months_per_year,
      default_plan = p_default_plan, borrower_signed_at = null, lender_signed_at = null
  where id = p_loan;
  -- An existing schedule moves to the new day, same months, same amounts.
  update public.loan_installments
  set due_on = (date_trunc('month', due_on) + make_interval(days => p_payment_day - 1))::date
  where loan_id = p_loan;
end $$;

-- Equal monthly installments on the loan's payment day, the first no earlier
-- than p_first_due; the last takes the remainder so the total is exactly the
-- principal. Clears any signatures.
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

-- --- 12. 'active' means disbursed ----------------------------------------------------
-- A signed loan becomes active when its request is paid (the money went out).
-- Only then can it be paused, forgiven or defaulted.

create function private.activate_loans_on_paid() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.family_loans set status = 'active' where request_id = new.id and status = 'signed';
  return null;
end $$;

create trigger requests_activate_loans after update of status on public.requests
  for each row when (new.status = 'paid' and old.status is distinct from new.status)
  execute function private.activate_loans_on_paid();

create or replace function public.forgive_loan(p_loan uuid, p_amount_cents bigint, p_tax_year integer) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.family_loans where id = p_loan and lender_id = auth.uid()
                 and status in ('active', 'paused')) then
    raise exception 'only the lender can forgive an active loan' using errcode = '42501';
  end if;
  insert into public.loan_forgiveness (loan_id, tax_year, amount_cents) values (p_loan, p_tax_year, p_amount_cents);
  if public.loan_outstanding_cents(p_loan) = 0 then
    update public.family_loans set status = 'forgiven' where id = p_loan;
  end if;
end $$;

create or replace function public.pause_loan(p_loan uuid, p_months integer, p_reason text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  l       public.family_loans;
  v_used  integer;
begin
  select * into l from public.family_loans where id = p_loan for update;
  if l.id is null or l.borrower_id <> auth.uid() then
    raise exception 'loan not found' using errcode = 'P0002';
  end if;
  if l.status not in ('active', 'paused') then
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

-- Collecting = active or paused; a signed loan hasn't been disbursed yet.
create or replace view public.loan_missed_installments with (security_invoker) as
select i.loan_id, i.seq, i.due_on, i.amount_cents - i.paid_cents as owed_cents
from public.loan_installments i
join public.family_loans l on l.id = i.loan_id
where i.paid_cents < i.amount_cents and i.due_on < current_date - 10
  and not i.paused and l.status in ('active', 'paused');

-- --- 9. pauses end ----------------------------------------------------------------------
-- The pause is in effect until the latest started_on + months. The borrower can
-- resume early at any time (the pushed-back dates stay pushed back); the
-- service (daily loan-servicing job) resumes only once the pause has run out.

create function private.pause_ends_on(p_loan uuid) returns date
language sql stable set search_path = '' as $$
  select max((started_on + make_interval(months => months))::date)
  from public.loan_pauses where loan_id = p_loan;
$$;

create function public.resume_loan(p_loan uuid) returns public.loan_status
language plpgsql security definer set search_path = '' as $$
declare
  l       public.family_loans;
  v_until date;
begin
  select * into l from public.family_loans where id = p_loan for update;
  if l.id is null or not (l.borrower_id = auth.uid() or private.is_service()) then
    raise exception 'loan not found' using errcode = 'P0002';
  end if;
  if l.status <> 'paused' then
    raise exception 'only a paused loan can be resumed' using errcode = '23514';
  end if;
  if l.borrower_id is distinct from auth.uid() then
    v_until := private.pause_ends_on(p_loan);
    if v_until > current_date then
      raise exception 'the borrower''s pause runs until %', v_until using errcode = '23514';
    end if;
  end if;
  update public.family_loans set status = 'active' where id = p_loan;
  perform private.audit('loan.resumed', 'family_loans', p_loan);
  return 'active';
end $$;

-- Service only: the daily job resumes every loan whose pause has run out.
create function public.resume_ended_pauses() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  update public.family_loans l set status = 'active'
  where l.status = 'paused' and coalesce(private.pause_ends_on(l.id), current_date) <= current_date;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- --- 11. repaid, and no default on a loan that owes nothing --------------------------------

create function private.mark_repaid() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.family_loans set status = 'repaid'
  where id = new.loan_id and status in ('active', 'paused') and public.loan_outstanding_cents(id) = 0;
  return null;
end $$;

create trigger loan_installments_mark_repaid after update of paid_cents on public.loan_installments
  for each row when (new.paid_cents is distinct from old.paid_cents)
  execute function private.mark_repaid();

create or replace function public.apply_default_plan(p_loan uuid) returns public.loan_status
language plpgsql security definer set search_path = '' as $$
declare
  l          public.family_loans;
  v_left     bigint;
  v_next     public.loan_status;
begin
  select * into l from public.family_loans where id = p_loan for update;
  if l.status not in ('active', 'paused') then
    raise exception 'loan is %', l.status using errcode = '23514';
  end if;
  v_left := public.loan_outstanding_cents(p_loan);
  if v_left <= 0 then
    raise exception 'nothing is outstanding: the loan is repaid, not in default' using errcode = '23514';
  end if;
  if l.default_plan = 'forgive' then
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

-- --- 13. journals: at least two lines, and reachable by the service role -------------------

create or replace function private.post_journal(
  p_fund public.fund, p_kind text, p_ref uuid, p_partner_ref text, p_lines jsonb
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then
    raise exception 'a journal needs at least two lines' using errcode = '23514';
  end if;
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

-- PostgREST exposes only `public`, so edge functions post through this.
create function public.post_journal(
  p_fund public.fund, p_kind text, p_ref uuid, p_partner_ref text, p_lines jsonb
) returns uuid language sql security definer set search_path = '' as $$
  select private.post_journal(p_fund, p_kind, p_ref, p_partner_ref, p_lines);
$$;

-- --- grants ---------------------------------------------------------------------------

revoke all on public.refunds_due from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

-- The service role (edge functions) bypasses RLS but still needs privileges:
-- the earlier blanket revokes from PUBLIC took away its execute, and tables
-- created by postgres never granted it read or write. Append-only triggers,
-- the status guard and the payout guard still apply to it.
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

-- Function grants for the whole schema, after the blanket revoke above.
grant execute on function
  public.has_role(public.member_role), public.is_active_member(),
  public.subscription_amount(bigint, integer), public.coverage_started_on(uuid),
  public.fund_for_kind(public.request_kind),
  public.submit_request(uuid), public.withdraw_request(uuid), public.confirm_redaction(uuid),
  public.record_review(uuid, public.review_decision, text),
  public.file_appeal(uuid, text), public.decide_appeal(uuid, boolean),
  public.my_request_reviews(uuid),
  public.create_invite(uuid, text), public.accept_invite(text), public.is_supporter(uuid),
  public.loan_outstanding_cents(uuid), public.set_loan_schedule(uuid, integer, date),
  public.set_loan_terms(uuid, integer, integer, public.default_plan),
  public.sign_loan(uuid), public.forgive_loan(uuid, bigint, integer),
  public.pause_loan(uuid, integer, text), public.resume_loan(uuid),
  public.request_raised_cents(uuid), public.pledge(uuid, bigint, public.contribution_source),
  public.my_reliability(), public.my_giving_record(), public.pool_requests_paid_3y(uuid),
  public.close_account()
to authenticated;
grant execute on function public.subscription_amount(bigint, integer), public.fund_for_kind(public.request_kind) to anon;
-- Service-role only (no client grant): record_score, run_pool_allocation,
-- capture_contributions, mark_refunded, resume_ended_pauses, apply_default_plan,
-- post_journal; and the refunds_due view.
