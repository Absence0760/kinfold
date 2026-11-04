-- Grant funding (roadmap 3d): matching funds and program-related investments
-- from foundations, employers and local government, tracked per source, with
-- federally funded money as its own pot (2 CFR 200). design.md "What grants
-- must not buy": grants fund the Fund, not a list of chosen families, so no
-- grant-to-allocation link exists here — grant money reaches a pool only
-- through the dues/premiums doors that already exist. And "No public money in
-- insured cover": federal money inside the cover would turn payouts into
-- federal aid, so a federal grant never enters the protection fund; a
-- non-federal one may pay into the fund's `dues` pot, which only ever pays
-- premiums.

create type public.grant_source as enum ('foundation', 'employer', 'local_government');

-- Labelled pots of their own accounts, so grant money never joins `available`.
insert into private.ledger_accounts (fund, code)
  values ('home_fund', 'grants'), ('home_fund', 'federal_grants');

create table public.grants (
  fund         public.fund not null check (fund in ('protection', 'home_fund')),
  source       public.grant_source not null,
  programme     text not null check (programme ~ '^\S.*' and length(programme) <= 200),
  federal      boolean not null default false,
  amount_cents bigint not null check (amount_cents > 0),
  partner_ref  text unique,
  posted_at    timestamptz not null default now(),
  id           uuid primary key default gen_random_uuid(),
  check (not federal or fund = 'home_fund')
);

create trigger grants_append_only before update or delete on public.grants
  for each row execute function private.forbid_change();

-- The partner (or a grantee's own board) reports money in, keyed by its
-- reference so a replayed report is a no-op answering with the row it made.
-- Federal money gets its own pot; non-federal money for the Home Fund joins
-- that fund's grants pot; non-federal money for the protection fund lands in
-- the fund's dues pot, which only ever pays premiums.
create function public.record_grant(
  p_fund public.fund, p_source public.grant_source, p_programme text,
  p_federal boolean, p_amount_cents bigint, p_partner_ref text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id    uuid;
  v_code  text;
begin
  if not private.is_service() then
    raise exception 'grant money is reported in by the partner' using errcode = '42501';
  end if;
  if p_partner_ref is null or p_partner_ref = '' then
    raise exception 'a grant report needs the partner''s reference' using errcode = '23514';
  end if;
  if p_fund is null or p_amount_cents <= 0 then
    raise exception 'a grant needs a fund and a positive amount' using errcode = '23514';
  end if;
  if p_programme is null or p_programme = '' then
    raise exception 'a grant report names the award it came from' using errcode = '23514';
  end if;
  if p_federal and p_fund = 'protection' then
    raise exception 'federal money never enters insured cover' using errcode = '23514';
  end if;
  -- A replayed report answers with the row it already made, adding no money.
  if exists (select 1 from public.grants where partner_ref = p_partner_ref) then
    return (select id from public.grants where partner_ref = p_partner_ref);
  end if;

  v_code := (case
    when p_federal then 'federal_grants'
    when p_fund = 'home_fund' then 'grants'
    else 'dues'
  end);

  insert into public.grants (fund, source, programme, federal, amount_cents, partner_ref)
    values (p_fund, p_source, p_programme, p_federal, p_amount_cents, p_partner_ref)
    returning id into v_id;
  perform private.post_journal(p_fund, 'grant', v_id, p_partner_ref,
    jsonb_build_array(jsonb_build_object('code', 'partner_cash', 'amount_cents', -p_amount_cents),
                      jsonb_build_object('code', v_code, 'amount_cents', p_amount_cents)));
  perform private.audit('grants.recorded', 'grants', v_id,
    jsonb_build_object('fund', p_fund, 'source', p_source, 'programme', p_programme,
                       'federal', p_federal, 'amount_cents', p_amount_cents));
  return v_id;
end $$;

-- --- access --------------------------------------------------------------------

-- New relations: Supabase hands the defaults to the client roles; take them
-- back, then grant only what each role needs. Members read the grants that
-- funded the cooperative (who funded what is public by design); only the
-- partner-side door and the ledger behind it stay with the service.
revoke all on public.grants from public, anon, authenticated;
grant select on public.grants to authenticated;

-- New table: hardening.sql's blanket service grants don't cover it; state them.
grant select, insert on public.grants to service_role;

revoke all on function public.record_grant(public.fund, public.grant_source, text, boolean, bigint, text) from public, anon, authenticated;
grant execute on function public.record_grant(public.fund, public.grant_source, text, boolean, bigint, text) to service_role;