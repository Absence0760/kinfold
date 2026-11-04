-- Fair-lending data (roadmap 3h): the demographics the fair-lending law allows
-- asking for, kept where the scorer, reviewers and panel can't read them.
-- `design.md` "Demographics only where the law allows asking": the law bars
-- asking race, ethnicity or sex (12 CFR 1002.5), with two routes out —
-- home-purchase and refinance loans secured by the home ask on the government
-- monitoring form (1002.13), collected on the credit union's behalf (service
-- only); every other Fund loan asks only as a voluntary self-test carrying the
-- four required disclosures (1002.5(b)(1)), which the borrower offers
-- themselves. Self-test rows feed the fairness audit; the CDFI loan-level
-- report answers "Do Not Know" for anything that didn't come off the
-- monitoring form, so voluntary answers never become federally reported data.
-- Age may be asked but never weighted against an applicant, so nothing here
-- feeds the needs formula: the scorer reads public tables only.

create table private.fair_lending (
  id            bigint generated always as identity primary key,
  loan_id       uuid not null references public.fund_loans (id) on delete cascade,
  -- 'monitoring_form' = asked by the credit union under 1002.13;
  -- 'self_test' = offered by the borrower under 1002.5(b)(1).
  source        text not null check (source in ('monitoring_form', 'self_test')),
  race          text not null check (
    race in ('Asian', 'Black', 'Hispanic', 'American Indian', 'White', 'Not reported')),
  ethnicity     text not null check (
    ethnicity in ('Hispanic or Latino', 'Not Hispanic or Latino', 'Not reported')),
  sex           text not null check (
    sex in ('Male', 'Female', 'Not reported')),
  offered_by    uuid references public.members (id),
  collected_at  timestamptz not null default now(),
  check ((source = 'self_test') = (offered_by is not null)),
  unique (loan_id, source)
);

create trigger fair_lending_append_only before update or delete on private.fair_lending
  for each row execute function private.forbid_change();

-- The borrower offers the voluntary self-test on their own non-secured Fund
-- loan. All four disclosures (1002.5(b)(1)) must be acknowledged, and the
-- answers are the borrower's own words: the schema only stores them where
-- they came from.
create function public.offer_fair_lending_self_test(
  p_loan uuid, p_purpose_ack boolean, p_use_ack boolean,
  p_limit_ack boolean, p_retain_ack boolean,
  p_race text, p_ethnicity text, p_sex text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  l public.fund_loans;
begin
  select * into l from public.fund_loans where id = p_loan;
  if l.id is null or l.borrower_id <> auth.uid() then
    raise exception 'fund loan not found' using errcode = 'P0002';
  end if;
  if l.secured then
    raise exception 'a Fund loan secured by the home answers on the government monitoring form, not a self-test'
      using errcode = '23514';
  end if;
  if exists (select 1 from private.fair_lending
             where loan_id = p_loan and source = 'self_test') then
    raise exception 'this loan''s self-test data is already recorded' using errcode = '23514';
  end if;
  if not (p_purpose_ack and p_use_ack and p_limit_ack and p_retain_ack) then
    raise exception 'the self-test needs all four disclosures acknowledged' using errcode = '23514';
  end if;

  insert into private.fair_lending (loan_id, source, race, ethnicity, sex, offered_by)
  values (p_loan, 'self_test', p_race, p_ethnicity, p_sex, auth.uid());
  -- The answers themselves never enter the trail: the log carries only the
  -- fact that the borrower offered their own data, like every PII touch.
  perform private.audit('fair_lending.self_test', 'fund_loans', p_loan);
end $$;

-- Service only: the credit union collects on the government monitoring form
-- (1002.13), which applies only to loans secured by the home.
create function public.record_fair_lending_monitoring_form(
  p_loan uuid, p_race text, p_ethnicity text, p_sex text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  l public.fund_loans;
begin
  if not private.is_service() then
    raise exception 'the monitoring form is collected by the lending partner' using errcode = '42501';
  end if;
  select * into l from public.fund_loans where id = p_loan;
  if l.id is null then
    raise exception 'fund loan not found' using errcode = 'P0002';
  end if;
  if not l.secured then
    raise exception 'the monitoring form is only for loans secured by the home' using errcode = '23514';
  end if;
  if exists (select 1 from private.fair_lending
             where loan_id = p_loan and source = 'monitoring_form') then
    raise exception 'this loan''s monitoring form data is already recorded' using errcode = '23514';
  end if;

  insert into private.fair_lending (loan_id, source, race, ethnicity, sex)
  values (p_loan, 'monitoring_form', p_race, p_ethnicity, p_sex);
  perform private.audit('fair_lending.monitoring_form', 'fund_loans', p_loan);
end $$;

-- The auditor's view (the fairness audit and the bias audit): one loan's rows,
-- source marked. Service only — the scorer, reviewers and panel never read
-- demographics, and nothing here is public.
create function public.fair_lending_rows(p_loan uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_rows jsonb;
begin
  if not private.is_service() then
    raise exception 'fair-lending data is read by the auditor, not the platform' using errcode = '42501';
  end if;
  select coalesce((
    select jsonb_agg(
      jsonb_build_object('source', f.source, 'race', f.race,
                         'ethnicity', f.ethnicity, 'sex', f.sex,
                         'collected_at', f.collected_at)
      order by f.collected_at
    )
    from private.fair_lending f where f.loan_id = p_loan
  ), '[]'::jsonb) into v_rows;
  perform private.audit('fair_lending.read', 'fund_loans', p_loan);
  return v_rows;
end $$;

-- The CDFI loan-level report's row for one loan (2 CFR 200.337 asks for
-- demographics "where collected" and accepts "Do Not Know"): only monitoring-
-- form answers count as collected; a self-test row shows "Do Not Know", so
-- voluntary data can't be read back into a federal record.
create function public.cdfi_loan_fair_lending(p_loan uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_found jsonb;
  v_form  text default null;
begin
  if not private.is_service() then
    raise exception 'the CDFI report is written by the lending partner''s auditors' using errcode = '42501';
  end if;
  select race into v_form from private.fair_lending
  where loan_id = p_loan and source = 'monitoring_form';
  v_found := jsonb_build_object(
    'race', coalesce(v_form, 'Do Not Know'),
    'ethnicity', coalesce((
      select ethnicity from private.fair_lending
      where loan_id = p_loan and source = 'monitoring_form'), 'Do Not Know'),
    'sex', coalesce((
      select sex from private.fair_lending
      where loan_id = p_loan and source = 'monitoring_form'), 'Do Not Know'));
  perform private.audit('fair_lending.cdfi_row', 'fund_loans', p_loan);
  return v_found;
end $$;

-- --- access --------------------------------------------------------------------

-- New private table: Supabase's defaults hand it to the client roles; take them
-- back and give the service role what it needs. Clients get nothing at all —
-- even a member with the loan's id can't read their own demographics here,
-- which is the point: the rows answer the auditor, not the borrower's screen.
revoke all on private.fair_lending from public, anon, authenticated;
grant select, insert on private.fair_lending to service_role;

revoke all on function public.offer_fair_lending_self_test(uuid, boolean, boolean, boolean, boolean, text, text, text) from public, anon;
grant execute on function public.offer_fair_lending_self_test(uuid, boolean, boolean, boolean, boolean, text, text, text) to authenticated;

revoke all on function public.record_fair_lending_monitoring_form(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.record_fair_lending_monitoring_form(uuid, text, text, text) to service_role;

revoke all on function public.fair_lending_rows(uuid) from public, anon, authenticated;
grant execute on function public.fair_lending_rows(uuid) to service_role;

revoke all on function public.cdfi_loan_fair_lending(uuid) from public, anon, authenticated;
grant execute on function public.cdfi_loan_fair_lending(uuid) to service_role;