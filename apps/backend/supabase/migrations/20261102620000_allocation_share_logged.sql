-- design.md's fairness audit: "a score nobody can re-derive cannot be defended
-- at the panel". The share rule moves part of a request's need onto the member,
-- and that share depends on how often their pool requests were PAID - a number
-- whose window moves every day. So the rule's effect is logged where the money
-- lands: each allocation row carries the `share_bps` actually applied, next to
-- the version the run read, and an auditor can check grant against need without
-- replaying a moving window.

alter table public.pool_allocations add column share_bps integer not null
  default 0 check (share_bps between 0 and 10000);

-- Same bands, reserve and ordering as `bands-v1`; the need line is unchanged;
-- the only addition is logging the share that line applied.
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
         public.member_share_bps(r.member_id) as share_bps,
         (r.amount_cents
           - public.insured_cover_cents(r.id)
           - private.raised_cents(r.id) - private.recovered_cents(r.id))
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
      insert into public.pool_allocations (run_id, request_id, score, band, need_cents, grant_cents, share_bps)
      values (v_run, c.id, c.score, c.band, c.need, v_grant, c.share_bps)
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
