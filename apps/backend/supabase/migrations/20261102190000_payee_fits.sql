-- A request's payee has to fit what the request asks for (followup: payee kind
-- wasn't tied to request kind, so a repair shop could be named on a loan payoff
-- and money would be aimed at the wrong place). The web form already only offers
-- the kinds that fit (`payeeKindsFor`); the database now agrees, and one small
-- function is the single mapping both sides read.
--
--   * car damage and car deductible   -> a repair shop
--   * home repair                     -> a contractor
--   * down payment, mortgage gap,
--     loan payoff                     -> a lender, seller or title company

create function public.payee_fits(p_request_kind public.request_kind, p_payee_kind public.payee_kind) returns boolean
language sql stable security definer set search_path = '' as $$
  select (p_request_kind in ('car_damage', 'car_deductible') and p_payee_kind = 'repair_shop')
    or (p_request_kind = 'home_repair' and p_payee_kind = 'contractor')
    or (p_request_kind in ('down_payment', 'mortgage_gap', 'loan_payoff')
        and p_payee_kind in ('lender', 'seller', 'title_company'));
$$;

create or replace function public.submit_request(p_request uuid) returns public.request_status
language plpgsql security definer set search_path = '' as $$
declare
  r        public.requests;
  s        public.fund_settings;
  v_start  date;
  v_asset  public.covered_assets;
begin
  select * into r from public.requests where id = p_request for update;
  if r.id is null or r.member_id <> auth.uid() then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if not public.is_active_member() then
    raise exception 'verify your identity before submitting a request' using errcode = '42501';
  end if;
  if r.status not in ('draft', 'needs_evidence') then
    raise exception 'only drafts and requests needing evidence can be submitted' using errcode = '23514';
  end if;
  if r.payee_id is null then
    raise exception 'name who should be paid (a shop, lender or seller)' using errcode = '23514';
  end if;
  -- The payee has to fit the request: cars go to a shop, a home repair to a
  -- contractor, home money to whoever pays it back. Same mapping as the form.
  if not public.payee_fits(r.kind, (select kind from public.payees where id = r.payee_id)) then
    raise exception 'the payee does not fit this request' using errcode = '23514';
  end if;
  if not exists (select 1 from public.evidence where request_id = r.id) then
    raise exception 'add at least one piece of evidence' using errcode = '23514';
  end if;
  if exists (select 1 from public.evidence where request_id = r.id and redaction_status <> 'confirmed') then
    raise exception 'check and confirm the redacted copy of every piece of evidence' using errcode = '23514';
  end if;

  -- Pool eligibility: cover must have started, and the asset must have been
  -- registered, at least `waiting_days` before the incident. Stops joining
  -- the day after a crash.
  if r.funding in ('pool', 'both') then
    select * into s from public.fund_settings where fund = public.fund_for_kind(r.kind);
    if not r.kind = any (s.kinds) then
      raise exception 'the community pool does not cover % requests yet', r.kind using errcode = '23514';
    end if;
    if r.amount_cents > s.max_request_cents then
      raise exception 'the pool pays at most % cents per request', s.max_request_cents using errcode = '23514';
    end if;
    v_start := public.coverage_started_on(r.member_id);
    if v_start is null or r.incident_on < v_start + s.waiting_days then
      raise exception 'pool cover starts % days after your first payment; ask your people instead', s.waiting_days
        using errcode = '23514';
    end if;
    if public.fund_for_kind(r.kind) = 'protection' then
      select * into v_asset from public.covered_assets
      where id = r.asset_id and member_id = r.member_id and removed_on is null;
      if v_asset.id is null or r.incident_on < v_asset.registered_on + s.waiting_days then
        raise exception 'the vehicle must be registered with Kinfold % days before the incident', s.waiting_days
          using errcode = '23514';
      end if;
    end if;
  end if;

  update public.requests
  set status = 'scoring', submitted_at = coalesce(submitted_at, now())
  where id = r.id;
  return 'scoring';
end $$;

grant execute on function public.payee_fits(public.request_kind, public.payee_kind) to authenticated;
