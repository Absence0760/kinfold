-- The member's own share answers on their own record (20261102600000_paid_share_console.sql).
--
-- Properties this file pins:
--   * a signed-in member reads their own share with no arguments at all, so
--     there is nothing to point at another member;
--   * the numbers are the published rule's, same as the pool reads: no paid
--     requests means no share, one paid request a tenth, four the cap;
--   * the rule's version travels with the answer, so a member can name which
--     published rule priced their share.
begin;
select plan(8);

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

-- p_from..p_to past pool requests, each paid with a payout sent now, written
-- with triggers off: these tests are about what the member reads back, not
-- about how a request got paid (requests_test and service_paths_test pin that).
create function pg_temp.paid_history(p_member uuid, p_from integer, p_to integer)
returns void language plpgsql as $$
declare
  idx integer;
  rid uuid;
  eid uuid;
begin
  set local session_replication_role = replica;
  for idx in p_from .. p_to loop
    rid := ('00000000-0000-0000-0060-00000000' || format('%04d', idx))::uuid;
    eid := ('00000000-0000-0000-0060-00000000' || format('%04d', 100 + idx))::uuid;
    insert into public.requests (id, member_id, kind, funding, title, amount_cents,
                                 incident_on, status, public_summary, public_summary_confirmed_at,
                                 current_score, submitted_at, payee_id)
    values (rid, p_member, 'car_damage', 'pool', 'Prior request', 50000, current_date - 30,
            'paid', 'Old fender after a slow corner clipping', now(), 85::smallint,
            now() - interval '20 days',
            '00000000-0000-0000-0060-0000000000c1');
    insert into public.evidence (id, request_id, kind, original_path, redacted_path,
                                 sha256, redaction_status)
    values (eid, rid, 'invoice', 'x/o.pdf', 'x/r.pdf', repeat('a', 64), 'confirmed');
    insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id,
                                status, created_at, sent_at)
    values (rid, '00000000-0000-0000-0060-0000000000c1', 50000, eid, 'sent', now(), now());
  end loop;
  set local session_replication_role = origin;
end $$;

select pg_temp.member('00000000-0000-0000-0060-0000000000a1');  -- no history
select pg_temp.member('00000000-0000-0000-0060-0000000000a2');  -- one paid
select pg_temp.member('00000000-0000-0000-0060-0000000000a3');  -- four paid
insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at)
values ('00000000-0000-0000-0060-0000000000c1', 'repair_shop', 'Shop', 'CA', 'verified', 'acct_c1', now());

select pg_temp.paid_history('00000000-0000-0000-0060-0000000000a2', 1, 1);
select pg_temp.paid_history('00000000-0000-0000-0060-0000000000a3', 2, 5);

-- --- what the member reads back -------------------------------------------------

select ok(has_function_privilege('authenticated', 'public.my_share()', 'execute'),
  'a member can read their own share');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0060-0000000000a1');
select is((select requests_paid_3y from public.my_share()), 0,
  'a member with no paid pool requests in three years reads zero');
select is((select share_bps from public.my_share()), 0,
  'no paid requests means no share of the next repair');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0060-0000000000a2');
select is((select requests_paid_3y from public.my_share()), 1,
  'the count the member reads is the pool''s own count');
select is((select share_bps from public.my_share()), 1000,
  'one paid pool request moves a tenth of the need to the member''s own share');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0060-0000000000a3');
select is((select requests_paid_3y from public.my_share()), 4,
  'four paid pool requests read as four');
select is((select share_bps from public.my_share()), 3000,
  'the share reads at the published cap whatever the count');
select is((select rule_version from public.my_share()), 1,
  'the rule version travels with the answer');

reset role;

rollback;
