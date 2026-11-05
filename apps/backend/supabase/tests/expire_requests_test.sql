-- Request expiry (20261102220000_expire_requests.sql).
--
-- Properties this file pins:
--   * expiry is the service's, and it only moves open or needs-evidence
--     requests: drafts are a member's to withdraw, funded/paid ones wait;
--   * an expired request releases pledges and cancels unsigned loans through
--     the existing close trigger, like withdraw does;
--   * a request with money already out to the payee can't be expired: the
--     payout guard routes it to a person (the job skips it, then reports);
--   * a member can't expire anything; the audit row records the expiry.
begin;
-- Audit counts read only this transaction's rows (`at = now()`): the seed's own
-- trail predates it, and a count over the whole log would read the seed too.
select plan(10);

-- --- fixtures ------------------------------------------------------------------
-- Temporary helpers, gone at rollback. They run as postgres (the owner).

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

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

-- A request already in a state, with (optionally) a pledge, inserted with
-- triggers off: this file pins what expiry allows, not how requests arrive.
create function pg_temp.request_in(p_request uuid, p_member uuid,
                                   p_status public.request_status, p_pledged boolean)
returns void language plpgsql as $$
begin
  insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                               status, public_summary, public_summary_confirmed_at, current_score, submitted_at)
  values (p_request, p_member, 'car_damage', 'pool', 'Test request', 123456, current_date - 5,
          'draft', 'Rear bumper after a parking-lot hit', now(), 87::smallint, now());
  if p_status <> 'draft' then
    update public.requests set status = 'scoring' where id = p_request;
    if p_status = 'needs_evidence' then
      update public.requests set status = 'needs_evidence' where id = p_request;
    end if;
    if p_status in ('open', 'funded') then
      update public.requests set status = 'open' where id = p_request;
    end if;
    if p_status = 'funded' then
      update public.requests set status = 'funded' where id = p_request;
    end if;
  end if;
  if p_pledged then
    insert into public.contributions (request_id, contributor_id, source, amount_cents, status)
    values (p_request, p_member, 'gift', 40000, 'pledged');
  end if;
end $$;

select pg_temp.member('00000000-0000-0000-0007-0000000000a1');
select pg_temp.member('00000000-0000-0000-0007-0000000000a2');
select pg_temp.request_in('00000000-0000-0000-0007-0000000000b1', '00000000-0000-0000-0007-0000000000a1',
                          'open', true);
select pg_temp.request_in('00000000-0000-0000-0007-0000000000b2', '00000000-0000-0000-0007-0000000000a1',
                          'needs_evidence', false);
select pg_temp.request_in('00000000-0000-0000-0007-0000000000b3', '00000000-0000-0000-0007-0000000000a1',
                          'draft', false);
select pg_temp.request_in('00000000-0000-0000-0007-0000000000b4', '00000000-0000-0000-0007-0000000000a1',
                          'funded', false);

-- --- expiry is the service's, open and needs-evidence only -----------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.expire_request('00000000-0000-0000-0007-0000000000b1')$$,
  'a stale open request is expired');
select is((select status from public.requests where id = '00000000-0000-0000-0007-0000000000b1'),
  'expired', 'the request says expired');
select is((select count(*) from public.contributions
           where request_id = '00000000-0000-0000-0007-0000000000b1' and status = 'released'),
  1::bigint, 'expiry releases the pledges, through the close trigger');
reset role;
select is((select count(*) from private.audit_log where action = 'request.expired' and at = now()),
  1::bigint, 'the expiry is audit-logged');
set local role service_role;
select pg_temp.as_service();

select lives_ok($$select public.expire_request('00000000-0000-0000-0007-0000000000b2')$$,
  'a needs-evidence request is expired too');

select throws_ok($$select public.expire_request('00000000-0000-0000-0007-0000000000b3')$$,
  'P0002', 'request not found, or not open or still needing evidence',
  'a draft is not the cron''s to expire: a member withdraws their own');
select throws_ok($$select public.expire_request('00000000-0000-0000-0007-0000000000b4')$$,
  'P0002', 'request not found, or not open or still needing evidence',
  'a funded request waits for money, it is not stale');
select throws_ok($$select public.expire_request('00000000-0000-0000-0007-0000000000b9')$$,
  'P0002', 'request not found, or not open or still needing evidence',
  'a request not found is refused');

-- --- money with the payee is not the cron's to expire ----------------------------

insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at)
values ('00000000-0000-0000-0007-0000000000c1', 'repair_shop', 'Shop', 'CA', 'verified', 'acct_c1', now() - interval '1 year');
insert into public.evidence (id, request_id, kind, original_path, redacted_path, sha256, redaction_status)
values ('00000000-0000-0000-0007-0000000000e1', '00000000-0000-0000-0007-0000000000b4',
        'invoice', 'x/original.pdf', 'x/redacted.pdf', repeat('a', 64), 'confirmed');
insert into public.contributions (id, request_id, contributor_id, source, amount_cents,
                                  status, created_at)
values ('00000000-0000-0000-0007-0000000000c2', '00000000-0000-0000-0007-0000000000b4',
        '00000000-0000-0000-0007-0000000000a2', 'gift', 123456, 'captured', now());
update public.requests set payee_id = '00000000-0000-0000-0007-0000000000c1' where id = '00000000-0000-0000-0007-0000000000b4';
insert into public.payouts (id, request_id, payee_id, amount_cents, invoice_evidence_id,
                            status, partner_ref, sent_at)
values ('00000000-0000-0000-0007-0000000000d1', '00000000-0000-0000-0007-0000000000b4',
        '00000000-0000-0000-0007-0000000000c1', 123456, '00000000-0000-0000-0007-0000000000e1',
        'sent', 'acct_p1', now());
select throws_ok($$select public.expire_request('00000000-0000-0000-0007-0000000000b4')$$,
  '23514', 'a payout to the payee is pending or sent; a person handles this request until it is returned',
  'money out with the payee keeps the request a person''s until it returns');

-- --- a member can't expire anything ----------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0007-0000000000a1');
select throws_ok($$select public.expire_request('00000000-0000-0000-0007-0000000000b1')$$,
  '42501', 'permission denied for function expire_request',
  'a member cannot expire a request');
