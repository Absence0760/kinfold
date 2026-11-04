-- Evidence lifecycle and "other money for the same damage" (20261101150000
-- migration).
--
-- Properties this file pins:
--   * money covering the same damage is recorded by the requester (or the
--     service), never by a stranger; positive amounts only; the service
--     verifies it once against a partner reference — retrying the same
--     reference is a no-op, a second reference on a verified recovery is not;
--   * recovered money never counts as funding (the request stays open when
--     pledges + other money reach the ask) but the pledge cap and the pool
--     run's need subtract it;
--   * redaction: the service writes the redacted copy (pending or rejected ->
--     auto_done, only while the request is draft or needs_evidence), the
--     member confirms (existing rule) or rejects an auto_done copy;
--   * summaries: the service writes them, the member asks for a change with
--     a note, and only while a summary exists;
--   * deleting an evidence row queues its original file (redacted too when
--     set); the queue is read and closed only by the service.
begin;
select plan(43);

-- --- fixtures ------------------------------------------------------------------

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

create function pg_temp.payee(p_id uuid, p_kind public.payee_kind default 'repair_shop',
                              p_status public.verification_status default 'verified')
returns uuid language sql as $$
  insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at)
  values (p_id, p_kind, 'Payee ' || right(p_id::text, 4), 'CA', p_status,
          case when p_status = 'verified' then 'acct_' || p_id::text end,
          case when p_status = 'verified' then now() end)
  returning id;
$$;

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

create function pg_temp.vehicle(p_id uuid, p_member uuid, p_registered date default current_date - 200)
returns uuid language sql as $$
  insert into public.covered_assets (id, member_id, kind, description, value_cents, registered_on, verified_at)
  values (p_id, p_member, 'vehicle', 'Test car', 1200000, p_registered, now())
  returning id;
$$;

create function pg_temp.request(p_id uuid, p_member uuid, p_funding public.funding_mode default 'people',
                                p_amount bigint default 100000, p_kind public.request_kind default 'car_damage',
                                p_payee uuid default null, p_asset uuid default null)
returns uuid language sql as $$
  insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on, payee_id, asset_id)
  values (p_id, p_member, p_kind, p_funding, 'Test request', p_amount, current_date - 5, p_payee, p_asset)
  returning id;
$$;

-- Pending evidence at a fixed original path, so the delete-queue assertions can
-- name the path.
create function pg_temp.evidence_at(p_request uuid, p_path text) returns uuid
language sql as $$
  insert into public.evidence (request_id, kind, original_path, sha256, redaction_status)
  values (p_request, 'photo', p_path, repeat('9', 64), 'pending')
  returning id;
$$;

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

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
$$;

select pg_temp.member('00000000-0000-0000-000b-0000000000a1');
select pg_temp.member('00000000-0000-0000-000b-0000000000a2', 'NY');
select pg_temp.member('00000000-0000-0000-000b-0000000000a3');
select pg_temp.cover('00000000-0000-0000-000b-0000000000a3');
select pg_temp.payee('00000000-0000-0000-000b-0000000000c1');
select pg_temp.vehicle('00000000-0000-0000-000b-0000000000e1', '00000000-0000-0000-000b-0000000000a3');

-- ana owns b1 (people) and b3 (draft, for the redaction/summary tests);
-- cy owns b2 (pool).
select pg_temp.request('00000000-0000-0000-000b-0000000000b1', '00000000-0000-0000-000b-0000000000a1',
                       'people', 100000, 'car_damage', '00000000-0000-0000-000b-0000000000c1');
select pg_temp.request('00000000-0000-0000-000b-0000000000b2', '00000000-0000-0000-000b-0000000000a3',
                       'pool', 100000, 'car_damage', '00000000-0000-0000-000b-0000000000c1',
                       '00000000-0000-0000-000b-0000000000e1');
select pg_temp.request('00000000-0000-0000-000b-0000000000b3', '00000000-0000-0000-000b-0000000000a1',
                       'people', 50000, 'home_repair', '00000000-0000-0000-000b-0000000000c1');

-- --- recorded money for the same damage -----------------------------------------
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000b-0000000000a1');
select ok((public.record_recovery('00000000-0000-0000-000b-0000000000b1', 'insurance', 20000,
  current_date - 4, 'insurer confirmed the recovery letter')) IS NOT NULL,
  'the requester declares money covered elsewhere');
select ok((public.record_recovery('00000000-0000-0000-000b-0000000000b1', 'fema', 15000,
  current_date - 3)) IS NOT NULL, 'disaster money for the same damage is declared too');
select throws_ok($$select public.record_recovery('00000000-0000-0000-000b-0000000000b1', 'state', 0, current_date)$$,
  '23514', 'money covered must be positive', 'only positive amounts are declared');

select pg_temp.login('00000000-0000-0000-000b-0000000000a2');
select throws_ok($$select public.record_recovery('00000000-0000-0000-000b-0000000000b1', 'own_cover', 100, current_date)$$,
  '42501', 'money for the same damage is recorded by the requester or the service',
  'a stranger records no money for someone else''s damage');
select is((select count(*) from public.request_recoveries
           where request_id = '00000000-0000-0000-000b-0000000000b1'), 0::bigint,
  'the stranger sees none of the declared money');

-- The service verifies a recovery once; a webhook retry of the same
-- reference is a no-op; a second reference is refused.
reset role;
set local role service_role;
select pg_temp.as_service();
select throws_ok($$select public.verify_recovery(
  (select id from public.request_recoveries
     where request_id = '00000000-0000-0000-000b-0000000000b1' and source = 'insurance'),
  '')$$,
  '23514', 'verification needs the partner''s reference', 'verification needs a reference');
select lives_ok($$select public.verify_recovery(
  (select id from public.request_recoveries
     where request_id = '00000000-0000-0000-000b-0000000000b1' and source = 'insurance'),
  'rf1')$$, 'the service verifies insurance money against a partner reference');
select lives_ok($$select public.verify_recovery(
  (select id from public.request_recoveries
     where request_id = '00000000-0000-0000-000b-0000000000b1' and source = 'insurance'),
  'rf1')$$, 'the same reference twice is a no-op');
select throws_ok($$select public.verify_recovery(
  (select id from public.request_recoveries
     where request_id = '00000000-0000-0000-000b-0000000000b1' and source = 'insurance'),
  'rf2')$$,
  'P0002', 'recovery not found or already verified', 'a verified recovery takes no second reference');
select is((select partner_ref from public.request_recoveries
           where request_id = '00000000-0000-0000-000b-0000000000b1' and source = 'insurance'),
  'rf1', 'verification stores the partner reference');

-- --- pledged money net of other money -------------------------------------------
reset role;
select pg_temp.move('00000000-0000-0000-000b-0000000000b1', 'scoring', 'open');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000b-0000000000a1');
select set_config('seed.invite', public.create_invite('00000000-0000-0000-000b-0000000000b1', 'neighbour'), false);
select pg_temp.login('00000000-0000-0000-000b-0000000000a2');
select isnt(public.accept_invite(current_setting('seed.invite')), NULL,
  'the stranger accepts it and becomes a supporter');
select throws_ok($$select public.pledge('00000000-0000-0000-000b-0000000000b1', 65001, 'gift')$$,
  '23514', 'pledge must be between 1 and 65000 cents',
  'the pledge cap subtracts the declared insurance and disaster money');
select ok((public.pledge('00000000-0000-0000-000b-0000000000b1', 65000, 'gift')) IS NOT NULL,
  'pledges up to the ask minus other money fit');
select is((select status from public.requests where id = '00000000-0000-0000-000b-0000000000b1'),
  'open'::public.request_status, 'other money never funds a request by itself');

-- --- pool run: need net of other money ------------------------------------------
reset role;
select pg_temp.move('00000000-0000-0000-000b-0000000000b2', 'scoring', 'open');
update public.requests set current_score = 80::smallint
  where id = '00000000-0000-0000-000b-0000000000b2';
set local role service_role;
select pg_temp.as_service();
select ok((public.record_recovery('00000000-0000-0000-000b-0000000000b2', 'insurance', 30000,
  current_date - 4)) IS NOT NULL, 'the service records money the insurer already moved');
select ok((public.run_pool_allocation('protection', 200000)) IS NOT NULL, 'the pool runs');
select results_eq(
  $$select need_cents, grant_cents from public.pool_allocations
    where request_id = '00000000-0000-0000-000b-0000000000b2'$$,
  $$values (70000::bigint, 70000::bigint)$$,
  'the pool run''s need subtracts money already covered by insurance');
select is((select status from public.requests where id = '00000000-0000-0000-000b-0000000000b2'),
  'open'::public.request_status, 'a pool grant plus insurance money does not fund by itself');

-- --- redaction lifecycle ----------------------------------------------------------
select set_config('seed.e1', pg_temp.evidence_at('00000000-0000-0000-000b-0000000000b3',
  'a1/e1-original.jpg')::text, false);
set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.set_redaction_done(current_setting('seed.e1')::uuid,
  'a1/e1-redacted.jpg', 'ph-e1')$$, 'the service writes the redacted copy');
select is((select redaction_status from public.evidence
           where id::text = current_setting('seed.e1')), 'auto_done'::public.redaction_status,
  'a fresh redaction marks auto_done');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-000b-0000000000a1');
select lives_ok($$select public.reject_redaction(current_setting('seed.e1')::uuid)$$,
  'the member rejects an auto_done copy');
select is((select redaction_status from public.evidence
           where id::text = current_setting('seed.e1')), 'rejected'::public.redaction_status,
  'the rejected copy stays rejected');

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.set_redaction_done(current_setting('seed.e1')::uuid,
  'a1/e1-redacted-v2.jpg', 'ph-e1-v2')$$, 'redaction re-runs over a rejected copy');
select is((select redaction_status from public.evidence
           where id::text = current_setting('seed.e1')), 'auto_done'::public.redaction_status,
  'the re-run marks auto_done again');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-000b-0000000000a1');
select lives_ok($$select public.confirm_redaction(current_setting('seed.e1')::uuid)$$,
  'the member confirms the re-run copy');
select is((select redaction_status from public.evidence
           where id::text = current_setting('seed.e1')), 'confirmed'::public.redaction_status,
  'confirmation lands on the member''s copy');

select pg_temp.login('00000000-0000-0000-000b-0000000000a2');
select throws_ok($$select public.reject_redaction(current_setting('seed.e1')::uuid)$$,
  'P0002', 'evidence not found or not ready to reject', 'another member rejects nothing');

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000b-0000000000a1');
select throws_ok($$select public.set_redaction_done(current_setting('seed.e1')::uuid, 'x')$$,
  '42501', 'permission denied for function set_redaction_done', 'redaction is service-side');

reset role;
-- Redaction refuses to touch evidence on a submitted request.
select set_config('seed.e2', pg_temp.evidence_at('00000000-0000-0000-000b-0000000000b1',
  'a1/e2-original.jpg')::text, false);
set local role service_role;
select pg_temp.as_service();
select throws_ok($$select public.set_redaction_done(current_setting('seed.e2')::uuid, 'x')$$,
  'P0002', 'evidence not found, not waiting for redaction, or its request was already submitted',
  'redaction stops once the request was submitted');

-- --- the file-deletion queue ------------------------------------------------------
reset role;
select lives_ok($$delete from public.evidence where id::text = current_setting('seed.e2')$$,
  'the owner removed the evidence row');
set local role service_role;
select pg_temp.as_service();
select results_eq(
  $$select bucket, path from public.pending_evidence_deletions$$,
  $$values ('evidence-original'::text, 'a1/e2-original.jpg'::text)$$,
  'the queue holds exactly the removed file for the service');
reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000b-0000000000a2');
select throws_ok($$select count(*) from public.pending_evidence_deletions$$,
  '42501', 'permission denied for view pending_evidence_deletions', 'members cannot read the file queue');

reset role;
set local role service_role;
select pg_temp.as_service();
select throws_ok($$select public.mark_evidence_deleted(999999999)$$,
  'P0002', 'deletion entry not found', 'marking only works for queued entries');
select lives_ok($$select public.mark_evidence_deleted(
  (select id from public.pending_evidence_deletions where path = 'a1/e2-original.jpg'))$$,
  'the service marks the queued file deleted');
select is((select count(*) from public.pending_evidence_deletions), 0::bigint,
  'the queue empties once processed');

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000b-0000000000a1');
select throws_ok($$select public.mark_evidence_deleted(1)$$,
  '42501', 'permission denied for function mark_evidence_deleted', 'members cannot close the file queue');

-- --- summaries ----------------------------------------------------------------------
reset role;
set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.set_public_summary('00000000-0000-0000-000b-0000000000b3',
  'Roof leak over the kitchen.')$$, 'the service writes the public summary');
select is((select public_summary from public.requests
           where id = '00000000-0000-0000-000b-0000000000b3'),
  'Roof leak over the kitchen.', 'the summary is stored on the request');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-000b-0000000000a1');
select throws_ok($$select public.request_summary_change('00000000-0000-0000-000b-0000000000b1', '')$$,
  '23514', 'tell us what is wrong with the summary', 'the member must say what is wrong');
select throws_ok($$select public.request_summary_change('00000000-0000-0000-000b-0000000000b1',
  'put it this way')$$,
  'P0002', 'request not found, has no summary yet, or is not yours',
  'no summary change possible before a summary exists');
select lives_ok($$select public.request_summary_change('00000000-0000-0000-000b-0000000000b3',
  'It was the skylight, not the whole kitchen roof.')$$, 'the requester asks for a different summary');
select is((select summary_change_note from public.requests
           where id = '00000000-0000-0000-000b-0000000000b3'),
  'It was the skylight, not the whole kitchen roof.', 'the note is stored for the service');

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000b-0000000000a1');
select throws_ok($$select public.set_public_summary('00000000-0000-0000-000b-0000000000b3', 'x')$$,
  '42501', 'permission denied for function set_public_summary', 'members cannot write summaries');

select * from finish();
rollback;