-- The fairness measure the public books publish (design.md "How we know it's
-- helping": "Help reaching families without wealth — Share of fund money to
-- households with no family lender — at least half of fund money", and
-- roadmap 2d's transparency dashboard). The headline risk in design.md ("How
-- we know it's helping") is mostly helping families who were already
-- comfortable, so the published month gains the money that went to members
-- who had no family lender of their own — an aggregate only, in the same
-- monthly snapshot the open books already publish (never live), under the same
-- small-numbers rules.
--
-- "Had a family lender" is defined as having had a family loan that actually
-- carried money: a loan that reached 'signed' or went past it. A loan still
-- 'proposed' or 'cancelled' never lent anything, so it does not count, and a
-- member whose only family loan was refused is exactly a household with help
-- reaching it because there was nobody to lend.

alter table public.open_books
  add pool_requests integer,
  add constraint pool_requests_suppressed check (pool_requests is null
                                                 or pool_requests = 0 or pool_requests >= 11),
  add no_lender_cents bigint,
  add constraint no_lender_rounded check (no_lender_cents is null
                                          or (no_lender_cents >= 0
                                              and no_lender_cents % 100000 = 0));

-- The service republishes the whole function: the month's grants are now split
-- into all-grants (already there) and grants to households with no family
-- lender (new). Same rules as every other published figure: a count shows at
-- 0 or at 11+, a dollar total shows only when at least eleven requests back it,
-- no one request is half of it, and dollars round to $1,000.
create or replace function public.publish_open_books(p_month date) returns void
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
  v_rn    bigint;
  v_rsum  bigint;
  v_rmax  bigint;
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

    -- The money of those grants that went to a household with no family lender
    -- of its own: no family loan that ever carried money for that member.
    select count(*), coalesce(sum(t), 0), coalesce(max(t), 0) into v_rn, v_rsum, v_rmax
    from (select sum(a.grant_cents) as t
          from public.pool_allocations a join public.pool_runs pr on pr.id = a.run_id
          join public.requests r on r.id = a.request_id
          where pr.fund = f and pr.run_at >= v_from and pr.run_at < v_to and a.grant_cents > 0
            and not exists (select 1 from public.family_loans fl
                            where fl.borrower_id = r.member_id
                              and fl.status in ('signed', 'active', 'paused',
                                                'repaid', 'forgiven', 'defaulted'))
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
                                   pool_runs_short, allocated_cents, reserve_cents,
                                   pool_requests, no_lender_cents)
    values (
      f, p_month,
      case when v_paid = 0 or v_paid >= 11 then v_paid end,
      case when v_paid = 0 then 0
           when v_paid >= 11 and v_max * 2 < v_sum then private.round_thousand(v_sum) end,
      v_runs, case when v_gn >= 11 then v_short end,
      case when v_gn = 0 then 0
           when v_gn >= 11 and v_gmax * 2 < v_gsum then private.round_thousand(v_gsum) end,
      case when v_res is not null then private.round_thousand(v_res) end,
      -- The grant-request count, hidden the same way: 0 when none, 11 or more
      -- when published, blank when the month is too small to say.
      case when v_gn = 0 then 0 when v_gn >= 11 then v_gn end,
      -- A small month hides both cells, so the share can't be worked out by
      -- subtraction; the all-grants figure already hides those months.
      case when v_gn = 0 then 0
           when v_gn >= 11 and v_rmax * 2 < v_rsum then private.round_thousand(v_rsum) end
    );
  end loop;
end $$;

revoke all on function public.publish_open_books(date) from public, anon, authenticated;
grant execute on function public.publish_open_books(date) to service_role;