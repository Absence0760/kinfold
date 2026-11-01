-- record_score routing against the fund's minimum score.
--
-- Properties this file pins:
--   * a score below the fund's min_score routes to needs_evidence, at or above
--     it to open;
--   * a fund with no fund_settings row routes on the documented default of 70
--     (20261031120000_record_score_default_min.sql), never straight to open.
begin;
select plan(4);

-- --- fixtures (as in ledger_test.sql) --------------------------------------------
-- in for the service role and the partner webhooks; clients can't do any of this.

create function pg_temp.member(p_id uuid, p_region text default 'CA',
                               p_status public.member_status default 'active')
returns uuid language sql as $$
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data, is_super_admin,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', p_id, 'authenticated', 'authenticated',
    p_id::text || '@test.invalid', 'x', now(), now(), now(),
    '{"provider":"email"}', '{}', false, '', '', '', '');
  insert into public.members (id, display_name, region, status)
  values (p_id, 'Member ' || right(p_id::text, 4), p_region, p_status);
  select p_id;
$$;

-- An income check, a subscription and its first captured payment `p_ago` back:
-- cover starts on that date.
create function pg_temp.cover(p_member uuid, p_ago interval default '200 days')
returns void language sql as $$
  with iv as (
    insert into public.income_verifications (member_id, method, monthly_income_cents)
    values (p_member, 'bank_link', 400000) returning id
  ), sub as (
    insert into public.subscriptions (member_id, formula_version, income_verification_id, monthly_cents, starts_on)
    select p_member, 1, iv.id, 4000, (now() - p_ago)::date from iv returning id
  )
  insert into public.subscription_payments (subscription_id, member_id, period, amount_cents, status, captured_at)
  select sub.id, p_member, date_trunc('month', now() - p_ago)::date, 4000, 'captured', now() - p_ago from sub;
$$;

create function pg_temp.payee(p_id uuid, p_kind public.payee_kind default 'repair_shop',
                              p_status public.verification_status default 'verified')
returns uuid language sql as $$
  insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at)
  values (p_id, p_kind, 'Payee ' || right(p_id::text, 4), 'CA', p_status,
          case when p_status = 'verified' then 'acct_' || p_id::text end,
          case when p_status = 'verified' then now() end)
  returning id;
$$;

create function pg_temp.vehicle(p_id uuid, p_member uuid, p_registered date default current_date - 200)
returns uuid language sql as $$
  insert into public.covered_assets (id, member_id, kind, description, value_cents, registered_on, verified_at)
  values (p_id, p_member, 'vehicle', 'Test car', 1200000, p_registered, now())
  returning id;
$$;

create function pg_temp.request(p_id uuid, p_member uuid, p_funding public.funding_mode default 'pool',
                                p_amount bigint default 100000, p_kind public.request_kind default 'car_damage',
                                p_payee uuid default null, p_asset uuid default null)
returns uuid language sql as $$
  insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on, payee_id, asset_id)
  values (p_id, p_member, p_kind, p_funding, 'Test request', p_amount, current_date - 5, p_payee, p_asset)
  returning id;
$$;

create function pg_temp.evidence(p_request uuid, p_kind public.evidence_kind default 'photo',
                                 p_status public.redaction_status default 'confirmed')
returns uuid language sql as $$
  insert into public.evidence (request_id, kind, original_path, redacted_path, sha256, redaction_status)
  values (p_request, p_kind, gen_random_uuid()::text || '/original.jpg',
          case when p_status in ('auto_done', 'confirmed') then gen_random_uuid()::text || '/redacted.jpg' end,
          repeat('a', 64), p_status)
  returning id;
$$;

-- Walk a request through allowed transitions (the status guard still applies).
create function pg_temp.move(p_request uuid, variadic p_path public.request_status[])
returns void language plpgsql as $$
declare
  s public.request_status;
begin
  foreach s in array p_path loop
    update public.requests set status = s where id = p_request;
  end loop;
end $$;

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;


select pg_temp.member('00000000-0000-0000-000a-0000000000a1', 'CA');

-- Fund minimum set: 80 for the protection fund (car_damage requests).
update public.fund_settings set min_score = 80 where fund = 'protection';

select pg_temp.request('00000000-0000-0000-000a-0000000000b1', '00000000-0000-0000-000a-0000000000a1');
select pg_temp.move('00000000-0000-0000-000a-0000000000b1', 'scoring');
select is(public.record_score('00000000-0000-0000-000a-0000000000b1', 79::smallint, '["x"]', 'm', '1', 'p1', 'h'),
  'needs_evidence'::public.request_status, 'below the fund minimum routes to needs_evidence');

select pg_temp.request('00000000-0000-0000-000a-0000000000b2', '00000000-0000-0000-000a-0000000000a1');
select pg_temp.move('00000000-0000-0000-000a-0000000000b2', 'scoring');
select is(public.record_score('00000000-0000-0000-000a-0000000000b2', 80::smallint, '["x"]', 'm', '1', 'p1', 'h'),
  'open'::public.request_status, 'at the fund minimum routes to open');

-- No settings row for the fund: the default of 70 applies.
delete from public.fund_settings where fund = 'protection';

select pg_temp.request('00000000-0000-0000-000a-0000000000b3', '00000000-0000-0000-000a-0000000000a1');
select pg_temp.move('00000000-0000-0000-000a-0000000000b3', 'scoring');
select is(public.record_score('00000000-0000-0000-000a-0000000000b3', 50::smallint, '["x"]', 'm', '1', 'p1', 'h'),
  'needs_evidence'::public.request_status, 'with no fund settings, a 50 still goes to a reviewer');

select pg_temp.request('00000000-0000-0000-000a-0000000000b4', '00000000-0000-0000-000a-0000000000a1');
select pg_temp.move('00000000-0000-0000-000a-0000000000b4', 'scoring');
select is(public.record_score('00000000-0000-0000-000a-0000000000b4', 70::smallint, '["x"]', 'm', '1', 'p1', 'h'),
  'open'::public.request_status, 'with no fund settings, a 70 opens');

select * from finish();
rollback;
