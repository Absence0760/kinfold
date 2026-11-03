-- The share applied is logged on the allocation row (20261102620000_allocation_share_logged.sql).
--
-- Properties this file pins:
--   * the allocation carries the share the need line actually applied;
--   * a member with no paid pool requests has zero logged;
--   * the logged share explains the need: amount minus the logged share
--     recomputes need_cents, so the fairness audit can replay a run without
--     knowing how often the member had been paid at the time it ran.
begin;
select plan(4);

-- --- fixtures ------------------------------------------------------------------

create function pg_temp.member(p_id uuid, p_region text default 'CA') returns void
language sql as $$
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
  values (p_id, 'Member ' || right(p_id::text, 4), p_region, 'active');
$$;

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

-- p_from..p_to past pool requests, each paid with a payout sent now, written
-- with triggers off: this file is about the share logged on the allocation,
-- not about how a request got paid (requests_test and service_paths_test pin
-- that).
create function pg_temp.paid_history(p_member uuid, p_from integer, p_to integer)
returns void language plpgsql as $$
declare
  idx integer;
  rid uuid;
  eid uuid;
begin
  set local session_replication_role = replica;
  for idx in p_from .. p_to loop
    rid := ('00000000-0000-0000-0062-00000000' || format('%04d', idx))::uuid;
    eid := ('00000000-0000-0000-0062-00000000' || format('%04d', 100 + idx))::uuid;
    insert into public.requests (id, member_id, kind, funding, title, amount_cents,
                                 incident_on, status, public_summary, public_summary_confirmed_at,
                                 current_score, submitted_at, payee_id)
    values (rid, p_member, 'car_damage', 'pool', 'Prior request', 50000, current_date - 30,
            'paid', 'Old fender after a slow corner clipping', now(), 85::smallint,
            now() - interval '20 days',
            '00000000-0000-0000-0062-0000000000c1');
    insert into public.evidence (id, request_id, kind, original_path, redacted_path,
                                 sha256, redaction_status)
    values (eid, rid, 'invoice', 'x/o.pdf', 'x/r.pdf', repeat('a', 64), 'confirmed');
    insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id,
                                status, created_at, sent_at)
    values (rid, '00000000-0000-0000-0062-0000000000c1', 50000, eid, 'sent', now(), now());
  end loop;
  set local session_replication_role = origin;
end $$;

create function pg_temp.share_of(p_run uuid, p_request uuid) returns integer language sql as $$
  select share_bps from public.pool_allocations where run_id = p_run and request_id = p_request;
$$;

create function pg_temp.need_of(p_run uuid, p_request uuid) returns bigint language sql as $$
  select need_cents from public.pool_allocations where run_id = p_run and request_id = p_request;
$$;

select pg_temp.member('00000000-0000-0000-0062-0000000000a1');  -- no history
select pg_temp.member('00000000-0000-0000-0062-0000000000a2');  -- one paid
select pg_temp.member('00000000-0000-0000-0062-0000000000a3');  -- four paid
insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at)
values ('00000000-0000-0000-0062-0000000000c1', 'repair_shop', 'Shop', 'CA', 'verified', 'acct_c1', now());

select pg_temp.paid_history('00000000-0000-0000-0062-0000000000a2', 1, 1);
select pg_temp.paid_history('00000000-0000-0000-0062-0000000000a3', 2, 5);

-- --- the allocation logs the share it applied -------------------------------------

insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                             status, description, public_summary, public_summary_confirmed_at,
                             current_score, submitted_at, payee_id)
values ('00000000-0000-0000-0062-0000000000b1', '00000000-0000-0000-0062-0000000000a1',
        'car_damage', 'pool', 'Fresh damage', 100000, current_date - 5, 'open',
        'A door after a lane-change rub.', 'Door after a lane-change rub',
        now(), 85::smallint, now() - interval '9 days',
        '00000000-0000-0000-0062-0000000000c1'),
       ('00000000-0000-0000-0062-0000000000b2', '00000000-0000-0000-0062-0000000000a2',
        'car_damage', 'pool', 'Frequent claimant', 100000, current_date - 5, 'open',
        'A fender from a slow corner clipping.', 'Fender after a slow corner',
        now(), 85::smallint, now() - interval '9 days',
        '00000000-0000-0000-0062-0000000000c1'),
       ('00000000-0000-0000-0062-0000000000b3', '00000000-0000-0000-0062-0000000000a3',
        'car_damage', 'pool', 'Capped claimant', 100000, current_date - 5, 'open',
        'A bumper after a yard misjudgement.', 'Bumper after a yard misjudgement',
        now(), 85::smallint, now() - interval '9 days',
        '00000000-0000-0000-0062-0000000000c1');

set local role service_role;
select pg_temp.as_service();
select set_config('test.run1', public.run_pool_allocation('protection', 400000)::text, true);

select is(pg_temp.share_of(current_setting('test.run1')::uuid,
                           '00000000-0000-0000-0062-0000000000b1'),
  0, 'a member with no paid pool requests has zero share logged');
select is(pg_temp.share_of(current_setting('test.run1')::uuid,
                           '00000000-0000-0000-0062-0000000000b2'),
  1000, 'one paid request logs a tenth-of-need share on the allocation row');
select is(pg_temp.share_of(current_setting('test.run1')::uuid,
                           '00000000-0000-0000-0062-0000000000b3'),
  3000, 'the capped claimant logs the capped share, three tenths');
select is(pg_temp.need_of(current_setting('test.run1')::uuid,
                          '00000000-0000-0000-0062-0000000000b3'),
  70000::bigint,
  'amount minus the logged share recomputes the need: the audit replays without '
  'the moving paid-window');

reset role;

rollback;
