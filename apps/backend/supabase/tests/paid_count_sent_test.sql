-- The "how often paid" record dates a payout by when it was sent
-- (20261102610000_paid_count_sent.sql).

-- Properties this file pins:
--   * a payout opened long ago but SENT last month still counts: the request
--     waited for the fund, and it was paid when the money went out;
--   * a payout sent more than three years ago is out of the record;
--   * a payout that has not been sent yet pays nothing;
--   * the count stays self-only.
begin;
select plan(5);

-- --- fixtures ------------------------------------------------------------------

create function pg_temp.member(p_id uuid) returns void language sql as $$
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
  values (p_id, 'Member ' || right(p_id::text, 4), 'CA', 'active');
$$;

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;

-- A paid pool request for p_member with a payout opened p_created and sent
-- p_sent (null leaves the payout pending). Written with triggers off: this file
-- is about which payout DATES the count reads, not about how a payout is
-- reached (payout_creation_test and payout_reporting_test pin that).
create function pg_temp.payout_date(p_member uuid, p_rid uuid, p_eid uuid,
                                    p_created timestamptz, p_sent timestamptz default null)
returns void language plpgsql as $$
begin
  set local session_replication_role = replica;
  insert into public.requests (id, member_id, kind, funding, title, amount_cents,
                               incident_on, status, public_summary, public_summary_confirmed_at,
                               current_score, submitted_at)
  values (p_rid, p_member, 'car_damage', 'pool', 'Prior request', 50000, current_date - 30,
          'paid', 'Old fender after a slow corner clipping', now(), 85::smallint,
          p_created - interval '20 days');
  insert into public.evidence (id, request_id, kind, original_path, redacted_path,
                               sha256, redaction_status)
  values (p_eid, p_rid, 'invoice', 'x/o.pdf', 'x/r.pdf', repeat('a', 64), 'confirmed');
  insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id,
                              status, partner_ref, created_at, sent_at)
  values (p_rid, '00000000-0000-0000-0061-0000000000c1', 50000, p_eid,
          case when p_sent is null then 'pending' else 'sent' end,
          'pc_' || p_rid::text, p_created, p_sent);
  set local session_replication_role = origin;
end $$;

select pg_temp.member('00000000-0000-0000-0061-0000000000a1');  -- payout sent last month
select pg_temp.member('00000000-0000-0000-0061-0000000000a2');  -- payout sent 40 months ago
select pg_temp.member('00000000-0000-0000-0061-0000000000a3');  -- payout not sent yet
insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at)
values ('00000000-0000-0000-0061-0000000000c1', 'repair_shop', 'Shop', 'CA', 'verified', 'acct_c1', now());

select pg_temp.payout_date('00000000-0000-0000-0061-0000000000a1',
  '00000000-0000-0000-0061-0000000000b1', '00000000-0000-0000-0061-0000000000e1',
  now() - interval '40 months', now() - interval '1 month');
select pg_temp.payout_date('00000000-0000-0000-0061-0000000000a2',
  '00000000-0000-0000-0061-0000000000b2', '00000000-0000-0000-0061-0000000000e2',
  now() - interval '40 months', now() - interval '40 months');
select pg_temp.payout_date('00000000-0000-0000-0061-0000000000a3',
  '00000000-0000-0000-0061-0000000000b3', '00000000-0000-0000-0061-0000000000e3',
  now() - interval '1 month', null);

-- --- the window reads the sent date ---------------------------------------------

select ok(has_function_privilege('authenticated', 'public.pool_requests_paid_3y(uuid)', 'execute'),
  'members can read their own count');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0061-0000000000a1');
select is((select pool_requests_paid_3y('00000000-0000-0000-0061-0000000000a1')), 1,
  'a payout opened three years ago but sent last month counts: the request was paid when the money went out');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0061-0000000000a2');
select is((select pool_requests_paid_3y('00000000-0000-0000-0061-0000000000a2')), 0,
  'a payout sent more than three years ago is out of the record');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0061-0000000000a3');
select is((select pool_requests_paid_3y('00000000-0000-0000-0061-0000000000a3')), 0,
  'a payout not sent yet has paid nothing toward the record');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0061-0000000000a1');
select throws_ok($$select public.pool_requests_paid_3y('00000000-0000-0000-0061-0000000000a2')$$,
  '42501', 'you can only see your own record',
  'the count stays self-only as its dating changes');

reset role;

rollback;
