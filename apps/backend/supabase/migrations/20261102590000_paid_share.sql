-- design.md ("What it can feed, openly and by published rule"): how OFTEN a
-- member's pool requests have been paid (in the last three years) raises their
-- OWN share of the next request, the same way a deductible works. The published
-- rule is versioned data, so it can move with the Fund's fee economics and be
-- audited; the pool's need line subtracts that share, so the pool never pays
-- the part the member carries themselves - a frequent claimant gets a smaller
-- grant, but is never refused and never waits longer. The seeded weights are
-- local stand-ins pending actuarial review, like every other design target.

create table public.share_rules (
  version        integer primary key,
  step_bps       integer not null check (step_bps >= 0),
  cap_bps        integer not null check (cap_bps between 0 and 10000),
  effective_from date not null
);

create policy "share rules are published" on public.share_rules for select using (true);

-- v1: a tenth of the need moves to the member's own share per request they had
-- paid in the last three years, capped at three tenths. Local stand-in.
insert into public.share_rules values (1, 1000, 3000, '2026-01-01');

-- The newest effective version decides the weights, the same way dues and
-- needs pick their formula version by effective date.
create function public.share_rule_version() returns integer
language sql stable security definer set search_path = '' as $$
  select coalesce((select max(version) from public.share_rules
                   where effective_from <= current_date), 0);
$$;

-- Percentage points of the still-needed amount the member carries themselves.
-- The read runs `pool_requests_paid_3y`, so an authenticated member may ask
-- only about themselves while the service (no auth.uid()) may ask about anyone.
create function public.member_share_bps(p_member uuid) returns integer
language sql stable security definer set search_path = '' as $$
  select coalesce(
    least(
      (select cap_bps from public.share_rules
       where version = public.share_rule_version()),
      public.pool_requests_paid_3y(p_member)
        * (select step_bps from public.share_rules
           where version = public.share_rule_version())),
    0);
$$;

revoke all from function public.share_rule_version();
revoke all from function public.share_rule_version() to public, anon, authenticated;
grant execute on function public.share_rule_version() to authenticated, service_role;

revoke all from function public.member_share_bps(uuid);
revoke all from function public.member_share_bps(uuid) to public, anon, authenticated;
grant execute on function public.member_share_bps(uuid) to authenticated, service_role;

-- The allocation now subtracts the member's own share from the need line
-- (amount minus cover, pledges and recovered, minus the published share), and
-- records the share rule's version on the run so the fairness audit can
-- re-derive grants. Band math, reserve and ordering are unchanged.
create or replace function public.run_pool_allocation(p_fund public.fund, p_available_cents bigint)
returns uuid language plpgsql security definer set search_path = '' as $$
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
  values (p_fund, p_available_cents, v_reserve,
          to_jsonb(s) * jsonb_build_object('share_version', public.share_rule_version()),
          'bands-v1')
  returning id into v_run;

  perform 1 from public.requests r
  where r.status = 'open' and r.funding in ('pool', 'both') and public.fund_for_kind(r.kind) = p_fund
  for update;

  drop table if exists pg_temp.candidates;
  create temporary table candidates on commit drop as
  select r.id, r.current_score as score,
         ((r.current_score / s.band_size) * s.band_size)::smallint as band,
         r.amount_cents
           - public.insured_cover_cents(r.id)
           - private.raised_cents(r.id) - private.recovered_cents(r.id)
           - ((r.amount_cents
               - public.insured_cover_cents(r.id)
               - private.raised_cents(r.id) - private.recovered_cents(r.id))
              * public.member_share_bps(r.member_id) / 10000)
         as need
  from public.requests r
  join public.payees p on p.id = r.payee_id and p.status = 'verified'
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

revoke all from function public.run_pool_allocation(public.fund, bigint);
revoke all from function public.run_pool_allocation(public.fund, bigint) to public, anon, authenticated;
grant execute on function public.run_pool_allocation(public.fund, bigint) to service_role;
