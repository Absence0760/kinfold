-- Payout reporting (20261102210000_payout_reporting.sql).
--
-- Properties this file pins:
--   * the service reports an outcome, a client can't;
--   * the moves are honest: pending becomes sent or failed, a sent payout can
--     come back, failed and returned are terminal, and pending is not an
--     outcome the partner reports;
--   * the same outcome twice is a no-op (webhooks retry);
--   * `sent` stamps `sent_at` (the existing trigger does the stamping);
--   * a payout whose request already refunded money can't be reported back:
--     `refunds_due` splits captured money over live payouts and a late return
--     wouldn't re-run that split, so it goes to a person instead.
begin;
select plan(11);

-- --- fixtures ------------------------------------------------------------------
-- Temporary helpers, gone at rollback. They run as postgres (the owner), standing
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

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

-- A request in a given state with a payout and (optionally) a refunded
-- contribution, inserted with triggers off: this file is about what reporting
-- allows, not about how a request got there (service_paths_test pins that).
create function pg_temp.request_with_payout(p_request uuid, p_member uuid, p_evidence uuid,
                                            p_payout uuid, p_payout_status public.payout_status,
                                            p_contribution uuid, p_refunded boolean)
returns void language plpgsql as $$
begin
  set local session_replication_role = replica;
  insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                               status, public_summary, public_summary_confirmed_at, current_score, submitted_at)
  values (p_request, p_member, 'car_damage', 'pool', 'Test request', 123456, current_date - 5,
          p_status, 'Rear bumper after a parking-lot hit', now(), 87::smallint, now());
  insert into public.evidence (id, request_id, kind, original_path, redacted_path, sha256, redaction_status)
  values (p_evidence, p_request, 'invoice', 'x/original.pdf', 'x/redacted.pdf', repeat('a', 64), 'confirmed');
  insert into public.payouts (id, request_id, payee_id, amount_cents, invoice_evidence_id,
                              status, partner_ref)
  values (p_payout, p_request, '00000000-0000-0000-0006-0000000000c1', 100000, p_evidence,
          p_payout_status, 'acct_' || right(p_request::text, 4));
  if p_refunded then
    insert into public.contributions (id, request_id, contributor_id, source, amount_cents,
                                      status, refunded_cents, refund_partner_ref, refunded_at)
    values (p_contribution, p_request, p_member, 'gift', 23456,
            'refunded', 23456, 'acct_ref' || right(p_request::text, 4), now());
  end if;
  set local session_replication_role = origin;
end $$;

select pg_temp.member('00000000-0000-0000-0006-0000000000a1');
insert into public.payees (id, kind, legal_name, region, status)
values ('00000000-0000-0000-0006-0000000000c1', 'repair_shop', 'Shop', 'CA', 'verified');

-- b1: open request, pending payout, nothing refunded yet.
select pg_temp.request_with_payout('00000000-0000-0000-0006-0000000000b1',
                                   '00000000-0000-0000-0006-0000000000a1',
                                   '00000000-0000-0000-0006-0000000000e1',
                                   '00000000-0000-0000-0006-0000000000d1', 'pending',
                                   '00000000-0000-0000-0006-0000000000c1', false);
-- b2: withdrawn request whose payout is sent and whose money was refunded.
select pg_temp.request_with_payout('00000000-0000-0000-0006-0000000000b2',
                                   '00000000-0000-0000-0006-0000000000a1',
                                   '00000000-0000-0000-0006-0000000000e2',
                                   '00000000-0000-0000-0006-0000000000d2', 'sent',
                                   '00000000-0000-0000-0006-0000000000c2', true);

-- --- the honest moves -----------------------------------------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.report_payout('00000000-0000-0000-0006-0000000000d1', 'sent')$$,
  'the service reports a pending payout as sent');
select is((select status from public.payouts where id = '00000000-0000-0000-0006-0000000000d1'),
  'sent', 'the payout says sent');
select isnot((select sent_at from public.payouts where id = '00000000-0000-0000-0006-0000000000d1'),
  NULL::timestamptz, 'the existing trigger stamps the sent date');

select lives_ok($$select public.report_payout('00000000-0000-0000-0006-0000000000d1', 'sent')$$,
  'the same outcome twice is a no-op');
select is((select status from public.payouts where id = '00000000-0000-0000-0006-0000000000d1'),
  'sent', 'a repeat report changes nothing');

select throws_ok($$select public.report_payout('00000000-0000-0000-0006-0000000000d1', 'pending')$$,
  '23514', 'a payout starts pending; the partner only reports an outcome',
  'pending is not an outcome to report');
select throws_ok($$select public.report_payout('00000000-0000-0000-0006-0000000000d1', 'failed')$$,
  '23514', 'a payout moves sent -> failed in no honest step',
  'a sent payout can only come back');

-- --- the rule a returned payout needs a person's decision ----------------------

select throws_ok($$select public.report_payout('00000000-0000-0000-0006-0000000000d2', 'returned')$$,
  '23514', 'a payout cannot be reported returned once money was refunded on its request; the console decides what happens next',
  'a late return after refunds goes to a person, not to the ledger');

-- --- an outcome report is the service's ------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0006-0000000000a1');
select throws_ok($$select public.report_payout('00000000-0000-0000-0006-0000000000d1', 'sent')$$,
  '42501', 'payout outcomes are reported by the service',
  'a member cannot report an outcome');

-- --- a payout that doesn't exist ------------------------------------------------

set local role service_role;
select pg_temp.as_service();
select throws_ok($$select public.report_payout('00000000-0000-0000-0006-0000000000d9', 'sent')$$,
  'P0002', 'payout not found', 'a payout not found is refused');

-- --- the audit row records the report -------------------------------------------

select is((select count(*) from private.audit_log where action = 'payout.reported'),
  1::bigint, 'a report is audit-logged once (the no-op repeat adds nothing)');
