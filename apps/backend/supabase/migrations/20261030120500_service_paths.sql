-- Service paths: money that reached a payee, and the private writes edge
-- functions need.
--
--   * a payout that is pending or sent is "live". While a request has a live
--     payout it can't be refused, withdrawn or expired: money is with the
--     payee, so a person handles it (record_review routes a refusal to
--     in_review instead) until the partner reports the payout returned;
--   * a request is 'paid' only once a payout has been sent and captured money
--     covers what was sent;
--   * refunds_due refunds only what wasn't paid out: live payouts consume a
--     request's captured contributions oldest first, and the rest is refundable;
--   * guard_payout checks the request's state when a payout is created, not
--     when the partner later reports it sent, failed or returned (those are
--     facts and must always be recordable);
--   * service-only wrappers for private.fraud_signals and private.member_identity.

-- --- live payouts -----------------------------------------------------------------

create function private.has_live_payout(p_request uuid) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from public.payouts where request_id = p_request and status in ('pending', 'sent'));
$$;

-- Status guard: as before, plus the payout rules.
create or replace function private.guard_request_status() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_sent      bigint;
  v_captured  bigint;
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then
      raise exception 'requests start as drafts' using errcode = '23514';
    end if;
    return new;
  end if;

  if new.status = old.status then
    return new;
  end if;

  if not exists (
    select 1 from public.request_transitions where from_status = old.status and to_status = new.status
  ) then
    raise exception 'a request cannot move from % to %', old.status, new.status using errcode = '23514';
  end if;

  -- The AI never refuses. Refusal needs a person's review, recorded in this
  -- same transaction, with a written reason (the reviews table requires one).
  if new.status = 'refused' and not exists (
    select 1 from public.reviews
    where request_id = new.id and decision = 'refuse' and created_at = now()
  ) then
    raise exception 'only a reviewer''s recorded decision can refuse a request' using errcode = '42501';
  end if;

  -- Money with the payee: a person handles it until the payout comes back.
  if new.status in ('refused', 'withdrawn', 'expired') and private.has_live_payout(new.id) then
    raise exception 'a payout to the payee is pending or sent; a person handles this request until it is returned'
      using errcode = '23514';
  end if;

  if new.status = 'paid' then
    select coalesce(sum(amount_cents), 0) into v_sent from public.payouts
    where request_id = new.id and status = 'sent';
    select coalesce(sum(amount_cents), 0) into v_captured from public.contributions
    where request_id = new.id and status = 'captured';
    if v_sent = 0 then
      raise exception 'a request is paid once a payout to its payee has been sent' using errcode = '23514';
    end if;
    if v_captured < v_sent then
      raise exception 'captured contributions (%) do not cover the payouts sent (%)', v_captured, v_sent
        using errcode = '23514';
    end if;
  end if;

  return new;
end $$;

-- Payout guard: request state, payee and invoice are checked when the payout is
-- created (or its payee or invoice changes); the captured-money cap whenever it
-- is live. A partner-reported status change is always recorded.
create or replace function private.guard_payout() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  r public.requests;
begin
  select * into r from public.requests where id = new.request_id;
  if tg_op = 'INSERT' and r.status not in ('funded', 'paid') then
    raise exception 'only funded requests are paid out' using errcode = '23514';
  end if;
  if tg_op = 'INSERT' or new.payee_id is distinct from old.payee_id
     or new.invoice_evidence_id is distinct from old.invoice_evidence_id
     or new.request_id is distinct from old.request_id then
    if new.payee_id is distinct from r.payee_id then
      raise exception 'money goes only to the request''s named payee' using errcode = '42501';
    end if;
    if not exists (select 1 from public.payees where id = new.payee_id and status = 'verified') then
      raise exception 'payee is not verified' using errcode = '42501';
    end if;
    if not exists (select 1 from public.evidence where id = new.invoice_evidence_id
                   and request_id = new.request_id and kind = 'invoice') then
      raise exception 'a payout needs the payee''s final invoice on this request' using errcode = '23514';
    end if;
  end if;
  if new.status in ('pending', 'sent')
     and (select coalesce(sum(amount_cents), 0) from public.payouts
          where request_id = new.request_id and status in ('pending', 'sent') and id <> new.id)
         + new.amount_cents
         > (select coalesce(sum(amount_cents), 0) from public.contributions
            where request_id = new.request_id and status = 'captured') then
    raise exception 'payouts cannot exceed captured contributions' using errcode = '23514';
  end if;
  perform private.audit('payout.' || new.status, 'payouts', new.id,
                        jsonb_build_object('amount_cents', new.amount_cents, 'payee_id', new.payee_id));
  return new;
end $$;

-- record_review: a refusal on a request with a live payout is recorded, but the
-- request goes to (or stays in) in_review for a person to recover the money.
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
  if v_next = 'refused' and private.has_live_payout(p_request) then
    v_next := 'in_review';
    perform private.audit('review.refuse_held_for_payout', 'requests', p_request);
  end if;

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

-- --- refunds net of payouts ------------------------------------------------------------

alter table public.contributions
  add column refunded_cents bigint,
  add constraint contributions_refunded_cents check (refunded_cents is null or refunded_cents between 1 and amount_cents),
  add constraint contributions_refunded_has_amount check ((status = 'refunded') = (refunded_cents is not null));

-- Live payouts consume captured contributions oldest first; each captured
-- contribution's refund is what's left of it. (A refunded one still counts in
-- the running total: its share was settled when it was refunded.)
create or replace view public.refunds_due with (security_barrier) as
with paid as (
  select request_id, sum(amount_cents)::bigint as paid_cents
  from public.payouts where status in ('pending', 'sent') group by request_id
), ranked as (
  select c.*, r.status as request_status, coalesce(p.paid_cents, 0) as paid_cents,
         (sum(c.amount_cents) over (partition by c.request_id order by c.created_at, c.id))::bigint as running_cents
  from public.contributions c
  join public.requests r on r.id = c.request_id
  left join paid p on p.request_id = c.request_id
  where c.status in ('captured', 'refunded') and r.status in ('withdrawn', 'refused', 'expired')
)
select id as contribution_id, request_id, request_status, source, contributor_id,
       amount_cents, loan_id, pool_allocation_id, partner_ref, created_at,
       least(amount_cents, running_cents - paid_cents) as refund_cents
from ranked
where status = 'captured' and running_cents - paid_cents > 0;

create or replace function public.mark_refunded(p_contribution uuid, p_partner_ref text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_cents bigint;
begin
  if p_partner_ref is null or p_partner_ref = '' then
    raise exception 'a refund needs the partner''s reference' using errcode = '23514';
  end if;
  -- Webhooks retry: the same refund reported twice is a no-op.
  if exists (select 1 from public.contributions where id = p_contribution and status = 'refunded'
             and refund_partner_ref = p_partner_ref) then
    return;
  end if;
  perform 1 from public.contributions where id = p_contribution for update;
  select refund_cents into v_cents from public.refunds_due where contribution_id = p_contribution;
  if v_cents is null then
    raise exception 'contribution not found or not due a refund' using errcode = 'P0002';
  end if;
  update public.contributions
  set status = 'refunded', refunded_cents = v_cents, refund_partner_ref = p_partner_ref, refunded_at = now()
  where id = p_contribution;
  perform private.audit('contribution.refunded', 'contributions', p_contribution,
                        jsonb_build_object('partner_ref', p_partner_ref, 'refunded_cents', v_cents));
end $$;

-- --- private writes for edge functions --------------------------------------------------

-- fraud-checks: a signal on a request. High severity sends it to a person at scoring.
create function public.record_fraud_signal(
  p_request uuid, p_kind text, p_severity text, p_detail jsonb default '{}'
) returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
begin
  if not exists (select 1 from public.requests where id = p_request) then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  insert into private.fraud_signals (request_id, kind, severity, detail)
  values (p_request, p_kind, p_severity, coalesce(p_detail, '{}'))
  returning id into v_id;
  perform private.audit('fraud_signal.recorded', 'requests', p_request,
                        jsonb_build_object('signal_id', v_id, 'kind', p_kind, 'severity', p_severity));
  return v_id;
end $$;

create function public.resolve_fraud_signal(p_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_request uuid;
begin
  update private.fraud_signals set resolved_at = now()
  where id = p_id and resolved_at is null
  returning request_id into v_request;
  if v_request is null then
    raise exception 'signal not found or already resolved' using errcode = 'P0002';
  end if;
  perform private.audit('fraud_signal.resolved', 'requests', v_request, jsonb_build_object('signal_id', p_id));
end $$;

-- verify-identity webhook: the vendor's reference and outcome (never the
-- documents); a pending member becomes active. Re-verifying an active member
-- updates the reference. Suspended and closed members stay as they are.
create function public.record_identity_check(p_member uuid, p_provider text, p_provider_ref text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  m public.members;
begin
  select * into m from public.members where id = p_member for update;
  if m.id is null then
    raise exception 'member not found' using errcode = 'P0002';
  end if;
  if m.status in ('suspended', 'closed') then
    raise exception 'member is %; an identity check does not change that', m.status using errcode = '23514';
  end if;
  insert into private.member_identity (member_id, provider, provider_ref, verified_at)
  values (p_member, p_provider, p_provider_ref, now())
  on conflict (member_id) do update
    set provider = excluded.provider, provider_ref = excluded.provider_ref, verified_at = excluded.verified_at;
  update public.members set status = 'active' where id = p_member and status = 'pending_verification';
  perform private.audit('identity.verified', 'members', p_member, jsonb_build_object('provider', p_provider));
end $$;

-- --- grants ---------------------------------------------------------------------------

revoke all on public.refunds_due from public, anon, authenticated;
grant select on public.refunds_due to service_role;
revoke all on function private.has_live_payout(uuid) from public, anon, authenticated;
revoke all on function
  public.record_fraud_signal(uuid, text, text, jsonb), public.resolve_fraud_signal(bigint),
  public.record_identity_check(uuid, text, text)
from public, anon, authenticated;
grant execute on function
  public.record_fraud_signal(uuid, text, text, jsonb), public.resolve_fraud_signal(bigint),
  public.record_identity_check(uuid, text, text)
to service_role;
