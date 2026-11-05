-- The member's own share rising with claims (20261102590000_paid_share.sql).
--
-- Properties this file pins:
--   * the share rule is published data, read by members;
--   * a member reads their own share only;
--   * no paid requests in three years means no share: the pool grants the whole
--     remaining need;
--   * one paid request moves a tenth of the need to the member's own share;
--   * the share caps at three tenths whatever the count;
--   * a smaller grant never means a refusal or a wait: the allocation row
--     exists with the reduced need recorded.
begin;
select plan(12);

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
-- with triggers off: these tests are about the share rule, not about how a
-- request got paid (requests_test and service_paths_test pin that).
create function pg_temp.paid_history(p_member uuid, p_from integer, p_to integer)
returns void language plpgsql as $$
declare
  idx integer;
  rid uuid;
  eid uuid;
begin
  set local session_replication_role = replica;
  for idx in p_from .. p_to loop
    rid := ('00000000-0000-0000-0059-00000000' || right('0000' || (idx)::text, 4))::uuid;
    eid := ('00000000-0000-0000-0059-00000000' || right('0000' || (100 + idx)::text, 4))::uuid;
    insert into public.requests (id, member_id, kind, funding, title, amount_cents,
                                 incident_on, status, public_summary, public_summary_confirmed_at,
                                 current_score, submitted_at, payee_id)
    values (rid, p_member, 'car_damage', 'pool', 'Prior request', 50000, current_date - 30,
            'draft', 'Old fender after a slow corner clipping', now(), 85::smallint,
            now() - interval '20 days',
            '00000000-0000-0000-0059-0000000000c1');
update public.requests set status = 'scoring' where id = rid;
update public.requests set status = 'open' where id = rid;
update public.requests set status = 'funded' where id = rid;
update public.requests set status = 'paid' where id = rid;
    insert into public.evidence (id, request_id, kind, original_path, redacted_path,
                                 sha256, redaction_status)
    values (eid, rid, 'invoice', 'x/' || rid::text || '/o.pdf', 'x/' || rid::text || '/r.pdf', repeat('a', 64), 'confirmed');
    insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id,
                                status, created_at, sent_at)
    values (rid, '00000000-0000-0000-0059-0000000000c1', 50000, eid, 'sent', now(), now());
  end loop;
  set local session_replication_role = origin;
end $$;

create function pg_temp.grant_of(p_run uuid, p_request uuid) returns bigint language sql as $$
  select grant_cents from public.pool_allocations where run_id = p_run and request_id = p_request;
$$;

create function pg_temp.need_of(p_run uuid, p_request uuid) returns bigint language sql as $$
  select need_cents from public.pool_allocations where run_id = p_run and request_id = p_request;
$$;

select pg_temp.member('00000000-0000-0000-0059-0000000000a1');  -- no history
select pg_temp.member('00000000-0000-0000-0059-0000000000a2');  -- one paid
select pg_temp.member('00000000-0000-0000-0059-0000000000a3');  -- four paid
insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at)
values ('00000000-0000-0000-0059-0000000000c1', 'repair_shop', 'Shop', 'CA', 'verified', 'acct_c1', now());

select pg_temp.paid_history('00000000-0000-0000-0059-0000000000a2', 1, 1);
select pg_temp.paid_history('00000000-0000-0000-0059-0000000000a3', 2, 5);

-- --- the rule is published and members read only their own share --------------------

select ok(has_function_privilege('authenticated', 'public.member_share_bps(uuid)', 'execute'),
  'members can read their share');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0059-0000000000a1');
select lives_ok($$select public.share_rule_version()$$,
  'a member reads the effective rule version');
select is((select public.member_share_bps('00000000-0000-0000-0059-0000000000a1')),
  0, 'no paid requests in three years means no share');
select throws_ok($$select public.member_share_bps('00000000-0000-0000-0059-0000000000a2')$$,
  '42501', 'you can only see your own record',
  'a member cannot read another member''s share');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0059-0000000000a2');
select is((select public.member_share_bps('00000000-0000-0000-0059-0000000000a2')),
  1000, 'one paid pool request moves a tenth of the need to the member''s own share');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0059-0000000000a3');
select is((select public.member_share_bps('00000000-0000-0000-0059-0000000000a3')),
  3000, 'the share caps at three tenths whatever the count');

-- --- the pool grants the need minus the member's own share ---------------------------

reset role;
-- Only this file's requests are on the board for the run: the seed's open pool
-- requests would otherwise share the band, and how big the seed board is must
-- never decide the figures this file pins.
update public.requests set status = 'withdrawn' where status = 'open';
insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                             status, description, public_summary, public_summary_confirmed_at,
                             current_score, submitted_at, payee_id)
values ('00000000-0000-0000-0059-0000000000b1', '00000000-0000-0000-0059-0000000000a1',
        'car_damage', 'pool', 'Fresh damage', 100000, current_date - 5, 'draft',
        'A door after a lane-change rub.', 'Door after a lane-change rub',
        now(), 85::smallint, now() - interval '9 days',
        '00000000-0000-0000-0059-0000000000c1'),
       ('00000000-0000-0000-0059-0000000000b2', '00000000-0000-0000-0059-0000000000a2',
        'car_damage', 'pool', 'Frequent claimant', 100000, current_date - 5, 'draft',
        'A fender from a slow corner clipping.', 'Fender after a slow corner',
        now(), 85::smallint, now() - interval '9 days',
        '00000000-0000-0000-0059-0000000000c1'),
       ('00000000-0000-0000-0059-0000000000b3', '00000000-0000-0000-0059-0000000000a3',
        'car_damage', 'pool', 'Capped claimant', 100000, current_date - 5, 'draft',
        'A bumper after a yard misjudgement.', 'Bumper after a yard misjudgement',
        now(), 85::smallint, now() - interval '9 days',
        '00000000-0000-0000-0059-0000000000c1');
update public.requests set status = 'scoring' where id = '00000000-0000-0000-0059-0000000000b2';
update public.requests set status = 'open' where id = '00000000-0000-0000-0059-0000000000b2';
update public.requests set status = 'scoring' where id = '00000000-0000-0000-0059-0000000000b3';
update public.requests set status = 'open' where id = '00000000-0000-0000-0059-0000000000b3';

update public.requests set status = 'scoring' where id = '00000000-0000-0000-0059-0000000000b1';
update public.requests set status = 'open' where id = '00000000-0000-0000-0059-0000000000b1';

set local role service_role;
select pg_temp.as_service();
-- The available balance is big enough that no band is squeezed: the rows show
-- each member's own need-minus-share figure whole, which is what this file pins.
select set_config('test.run1', public.run_pool_allocation('protection', 700000)::text, true);
select is((select reserve_cents from public.pool_runs
           where id = current_setting('test.run1')::uuid),
  140000::bigint, 'the fund keeps its reserve as before');
select is(((select settings from public.pool_runs
            where id = current_setting('test.run1')::uuid) ->> 'share_version')::int,
  1::int, 'the run records which share rule version it read');
select is(pg_temp.grant_of(current_setting('test.run1')::uuid, '00000000-0000-0000-0059-0000000000b1'),
  100000::bigint, 'the member with no history is granted the whole need');
select is(pg_temp.grant_of(current_setting('test.run1')::uuid, '00000000-0000-0000-0059-0000000000b2'),
  90000::bigint, 'one paid request shrinks the grant to nine tenths of the need');
select is(pg_temp.grant_of(current_setting('test.run1')::uuid, '00000000-0000-0000-0059-0000000000b3'),
  70000::bigint, 'the capped claimant gets a seven-tenths grant');
select is(pg_temp.need_of(current_setting('test.run1')::uuid, '00000000-0000-0000-0059-0000000000b2'),
  90000::bigint, 'the allocation stores the need with the member''s share already out');

-- A smaller grant is money the member carries themselves, never a refusal or a
-- wait: the allocation row exists and the request stays open like everyone
-- else's - the assertions above already show the grant and the row.

reset role;

rollback;
