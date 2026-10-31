-- Board and open-books privacy: closes gaps found reviewing the dashboards plan
-- (docs/design.md, "Dashboards").
--
--   * the member confirms the public summary before their request reaches the
--     board, and any later change to it needs confirming again;
--   * one rule decides what is on the board (public.on_board), used by the
--     board view, request_raised_cents and pledge;
--   * the board shows bands, not exact figures, once a request stops asking for
--     money: amount band, 10-point score band, month instead of week, and the
--     Census division instead of the state where the state is small; closed
--     requests leave the board after 12 months;
--   * pool allocations are read only by the member they were for;
--   * the public no longer reads live pool runs or live totals (polling them
--     revealed one request's payout and timing). They read monthly snapshots in
--     public.open_books, published once a month has ended, with small numbers
--     hidden. Payouts are counted by when they were sent (payouts.sent_at, new
--     here), a week after the month ends so late confirmations land first, in
--     UTC. The service writes open_books only through publish_open_books.
--
-- Same conventions as the earlier migrations: security definer functions pin
-- `search_path = ''`, and grants are stated explicitly at the end.

-- --- 1. the member confirms the public summary ------------------------------------

alter table public.requests add column public_summary_confirmed_at timestamptz;

create function private.clear_summary_confirmation() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.public_summary is distinct from old.public_summary then
    new.public_summary_confirmed_at := null;
  end if;
  return new;
end $$;

create trigger requests_summary_confirmation before update of public_summary on public.requests
  for each row execute function private.clear_summary_confirmation();

create function public.confirm_public_summary(p_request uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  r public.requests;
begin
  select * into r from public.requests where id = p_request for update;
  if r.id is null or r.member_id is distinct from auth.uid() then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if r.public_summary is null then
    raise exception 'there is no public summary to confirm yet' using errcode = '23514';
  end if;
  update public.requests set public_summary_confirmed_at = now() where id = p_request;
  perform private.audit('request.summary_confirmed', 'requests', p_request);
end $$;

-- --- 2. one rule for what is on the board --------------------------------------------

-- A pool request asking for or given money, with a confirmed summary. Closed
-- requests stay 12 months; a request still open always shows.
create function public.on_board(r public.requests) returns boolean
language sql stable set search_path = '' as $$
  select r.status in ('open', 'funded', 'paid')
     and r.funding in ('pool', 'both')
     and r.public_summary is not null
     and r.public_summary_confirmed_at is not null
     and (r.status = 'open' or r.submitted_at > now() - interval '12 months');
$$;

-- US Census divisions, for states too small to name on the board.
create function private.census_division(p_region text) returns text
language sql immutable set search_path = '' as $$
  select case
    when p_region in ('CT', 'ME', 'MA', 'NH', 'RI', 'VT') then 'New England'
    when p_region in ('NJ', 'NY', 'PA') then 'Middle Atlantic'
    when p_region in ('IL', 'IN', 'MI', 'OH', 'WI') then 'East North Central'
    when p_region in ('IA', 'KS', 'MN', 'MO', 'NE', 'ND', 'SD') then 'West North Central'
    when p_region in ('DE', 'DC', 'FL', 'GA', 'MD', 'NC', 'SC', 'VA', 'WV') then 'South Atlantic'
    when p_region in ('AL', 'KY', 'MS', 'TN') then 'East South Central'
    when p_region in ('AR', 'LA', 'OK', 'TX') then 'West South Central'
    when p_region in ('AZ', 'CO', 'ID', 'MT', 'NV', 'NM', 'UT', 'WY') then 'Mountain'
    when p_region in ('AK', 'CA', 'HI', 'OR', 'WA') then 'Pacific'
    else 'Other'
  end;
$$;

-- The state while it has at least 1,000 active members, else its division.
create function public.board_area(p_region text) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when not (public.is_active_member() or private.is_service()) then null
    when (select count(*) from public.members where region = p_region and status = 'active') >= 1000
      then p_region
    else private.census_division(p_region)
  end;
$$;

create index members_region_status_idx on public.members (region, status);

-- --- 3. the board shows bands ----------------------------------------------------------

-- The storage policy on redacted evidence reads the view, so it is dropped and
-- re-created with it.
drop policy "redacted evidence on the board" on storage.objects;
drop view public.board_requests;

create view public.board_requests with (security_barrier) as
select
  r.id,
  r.kind,
  r.public_summary,
  r.status,
  -- The exact ask only while it is still being funded: givers need it.
  case when r.status = 'open' then r.amount_cents end as amount_cents,
  b.lo as amount_band_min_cents,
  b.hi as amount_band_max_cents,
  ((r.current_score / 10) * 10)::smallint as score_band,
  public.board_area(m.region) as area,
  date_trunc('month', r.submitted_at)::date as month_of
from public.requests r
join public.members m on m.id = r.member_id
cross join lateral (
  select lo, hi from (values
    (0::bigint, 50000::bigint), (50000, 100000), (100000, 250000), (250000, 500000),
    (500000, 1000000), (1000000, 2500000), (2500000, 5000000), (5000000, 10000000),
    (10000000, null)
  ) bands (lo, hi)
  where r.amount_cents >= lo and (hi is null or r.amount_cents < hi)
) b
where public.on_board(r)
  and public.is_active_member();

create policy "redacted evidence on the board" on storage.objects for select to authenticated
  using (bucket_id = 'evidence-redacted' and exists (
    select 1 from public.evidence e
    join public.requests r on r.id = e.request_id
    where e.redacted_path = storage.objects.name
      and (r.member_id = auth.uid()
           or (e.redaction_status = 'confirmed' and r.id in (select id from public.board_requests)))
  ));

create or replace function public.request_raised_cents(p_request uuid) returns bigint
language sql stable security definer set search_path = '' as $$
  select private.raised_cents(r.id)
  from public.requests r
  where r.id = p_request
    and (private.is_service()
         or r.member_id = auth.uid()
         or public.is_supporter(r.id)
         -- Strangers see progress only while a request is asking for money:
         -- once funded, raised equals the ask, which the board shows as a band.
         or (public.on_board(r) and r.status = 'open' and public.is_active_member()));
$$;

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
  -- Strangers give only to requests they can see on the board.
  if p_source = 'gift' and not v_invited
     and not (public.on_board(r) and public.is_active_member()) then
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


-- --- 4. pool allocations are the member's own -------------------------------------------

-- Every active member could read every allocation, including pool requests not
-- on the board: their need, score and band.
drop policy "verified members see allocations" on public.pool_allocations;
create policy "members read their own allocations" on public.pool_allocations for select to authenticated
  using (exists (select 1 from public.requests r where r.id = request_id and r.member_id = auth.uid()));

-- --- 5. open books as monthly snapshots ------------------------------------------------

-- Live totals and per-run amounts let anyone diff them over time and read off
-- one request's payout. The public now reads closed months only.
drop view public.public_stats;
drop policy "pool runs are open books" on public.pool_runs;
revoke select on public.pool_runs from anon, authenticated;

-- When the partner confirmed a payout sent: the open books count payouts by it.
alter table public.payouts add column sent_at timestamptz;

create function private.stamp_payout_sent() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.status = 'sent' and (tg_op = 'INSERT' or old.status is distinct from 'sent') then
    new.sent_at := now();
  end if;
  return new;
end $$;

create trigger payouts_stamp_sent before insert or update of status on public.payouts
  for each row execute function private.stamp_payout_sent();

-- One row per pooled fund per ended month. Null means hidden:
--   * requests_paid is 0 or at least 11; 1 to 10 shows as "10 or fewer";
--   * a dollar total shows only when it covers at least 11 requests and no one
--     request is half of it, rounded to the nearest $1,000;
--   * how many runs fell short shows only when the month's runs granted money
--     to at least 11 requests (one short run of one request is that request).
-- Months never overlap and there is no all-funds or all-time row, so a hidden
-- figure can't be worked out by subtraction. Adding such a row needs
-- complementary suppression first.
create table public.open_books (
  fund                 public.fund not null check (fund <> 'people'),
  month                date not null check (month = date_trunc('month', month)::date),
  requests_paid        integer check (requests_paid = 0 or requests_paid >= 11),
  paid_out_cents       bigint check (paid_out_cents >= 0 and paid_out_cents % 100000 = 0),
  pool_runs            integer not null check (pool_runs >= 0),
  pool_runs_short      integer check (pool_runs_short between 0 and pool_runs),
  allocated_cents      bigint check (allocated_cents >= 0 and allocated_cents % 100000 = 0),
  reserve_cents        bigint check (reserve_cents >= 0 and reserve_cents % 100000 = 0),
  published_at         timestamptz not null default now(),
  primary key (fund, month)
);

create function private.round_thousand(p_cents numeric) returns bigint
language sql immutable set search_path = '' as $$
  select (round(p_cents / 100000) * 100000)::bigint;
$$;

-- Service only (a monthly schedule). Publishes the month that starts on p_month,
-- once it has ended; a month is published once.
create function public.publish_open_books(p_month date) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_end   date := (p_month + interval '1 month')::date;
  -- Month edges in UTC, whatever the caller's time zone.
  v_from  timestamptz := p_month::timestamp at time zone 'UTC';
  v_to    timestamptz := v_end::timestamp at time zone 'UTC';
  f       public.fund;
  v_paid  bigint;
  v_sum   bigint;
  v_max   bigint;
  v_gn    bigint;
  v_gsum  bigint;
  v_gmax  bigint;
  v_runs  integer;
  v_short integer;
  v_res   bigint;
begin
  if not private.is_service() then
    raise exception 'only the service publishes the open books' using errcode = '42501';
  end if;
  if p_month <> date_trunc('month', p_month)::date then
    raise exception 'p_month must be the first day of a month' using errcode = '22023';
  end if;
  -- A week's settlement lag, so payouts the partner confirms late are counted.
  if v_end + 7 > (now() at time zone 'UTC')::date then
    raise exception 'a month is published a week after it ends' using errcode = '23514';
  end if;

  for f in select fund from public.fund_settings where fund <> 'people' loop
    -- Payouts sent to payees for this fund's pool requests in the month.
    select count(*), coalesce(sum(t), 0), coalesce(max(t), 0) into v_paid, v_sum, v_max
    from (select sum(p.amount_cents) as t
          from public.payouts p join public.requests r on r.id = p.request_id
          where p.status = 'sent' and r.funding in ('pool', 'both')
            and public.fund_for_kind(r.kind) = f
            and p.sent_at >= v_from and p.sent_at < v_to
          group by p.request_id) per_request;

    -- Pool grants made in the month.
    select count(*), coalesce(sum(t), 0), coalesce(max(t), 0) into v_gn, v_gsum, v_gmax
    from (select sum(a.grant_cents) as t
          from public.pool_allocations a join public.pool_runs pr on pr.id = a.run_id
          where pr.fund = f and pr.run_at >= v_from and pr.run_at < v_to and a.grant_cents > 0
          group by a.request_id) per_request;

    select count(*),
           count(*) filter (where exists (
             select 1 from public.pool_allocations a where a.run_id = pr.id
             group by a.run_id having sum(a.grant_cents) < sum(a.need_cents)))
      into v_runs, v_short
    from public.pool_runs pr
    where pr.fund = f and pr.run_at >= v_from and pr.run_at < v_to;

    select pr.reserve_cents into v_res from public.pool_runs pr
    where pr.fund = f and pr.run_at >= v_from and pr.run_at < v_to
    order by pr.run_at desc limit 1;

    insert into public.open_books (fund, month, requests_paid, paid_out_cents, pool_runs,
                                   pool_runs_short, allocated_cents, reserve_cents)
    values (
      f, p_month,
      case when v_paid = 0 or v_paid >= 11 then v_paid end,
      case when v_paid = 0 then 0
           when v_paid >= 11 and v_max * 2 < v_sum then private.round_thousand(v_sum) end,
      v_runs, case when v_gn >= 11 then v_short end,
      case when v_gn = 0 then 0
           when v_gn >= 11 and v_gmax * 2 < v_gsum then private.round_thousand(v_gsum) end,
      case when v_res is not null then private.round_thousand(v_res) end
    );
  end loop;
end $$;

-- --- grants ---------------------------------------------------------------------------

-- Supabase's default privileges give new relations to anon and authenticated;
-- take them back, then grant only what each needs.
revoke all on public.board_requests, public.open_books from anon, authenticated;
grant select on public.board_requests to authenticated;
grant select on public.board_requests to service_role;

alter table public.open_books enable row level security;
create policy "open books are public" on public.open_books for select using (true);
grant select on public.open_books to anon, authenticated;
grant select, insert on public.open_books to service_role;

revoke all on function
  public.on_board(public.requests), private.census_division(text), public.board_area(text),
  private.round_thousand(numeric), private.clear_summary_confirmation()
from public, anon, authenticated;
-- The board view runs these as the reading member (Postgres checks function
-- privileges as the caller, even inside a view), so they live in public.
grant execute on function public.on_board(public.requests), public.board_area(text) to authenticated, service_role;
revoke all on function private.stamp_payout_sent() from public, anon, authenticated;
revoke all on function public.publish_open_books(date) from public, anon, authenticated;
-- anon called fund_for_kind only through the old public_stats view.
revoke execute on function public.fund_for_kind(public.request_kind) from anon;
grant execute on function public.publish_open_books(date) to service_role;
revoke all on function public.confirm_public_summary(uuid) from public, anon;
grant execute on function public.confirm_public_summary(uuid) to authenticated;
