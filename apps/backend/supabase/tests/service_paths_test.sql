-- Service paths: payouts, refunds net of payouts, and the private writes edge
-- functions make (20261030120500_service_paths.sql).
--
-- Properties this file pins:
--   * while a payout is pending or sent, a request can't be refused, withdrawn
--     or expired; record_review routes a refusal to in_review (still writing the
--     review and an audit row); once the partner reports the payout returned,
--     the refusal goes through;
--   * a partner-reported payout status (returned, sent) is recorded whatever
--     the request's state or the payee's status since the payout was created;
--   * refunds_due takes live payouts out of the oldest captured money first and
--     refunds only the rest; mark_refunded records how much went back;
--   * a request is 'paid' only once a payout was sent and captured money covers it;
--   * record_fraud_signal, resolve_fraud_signal and record_identity_check are
--     service-only, validate their target, audit-log, and the identity check
--     activates a pending member but never lifts a suspension.
-- Service-role steps run as the real service_role (set local role).
begin;
select plan(40);

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

-- As the service role itself (not postgres), so the grants are under test too.
create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

select pg_temp.member('00000000-0000-0000-000a-0000000000a1', 'CA');                          -- ida, requester
select pg_temp.member('00000000-0000-0000-000a-0000000000a2', 'NY');                          -- gus, giver
select pg_temp.member('00000000-0000-0000-000a-0000000000a3', 'NY');                          -- rae, reviewer
select pg_temp.member('00000000-0000-0000-000a-0000000000a4', 'CA', 'pending_verification');  -- pia, verifying
select pg_temp.member('00000000-0000-0000-000a-0000000000a5', 'CA', 'suspended');             -- sol, suspended
insert into public.member_roles (member_id, role) values ('00000000-0000-0000-000a-0000000000a3', 'reviewer');
select pg_temp.payee('00000000-0000-0000-000a-0000000000c1');

-- p1, p2, p3: ida's, people-funded, each with an invoice from the verified shop.
select pg_temp.request(id, '00000000-0000-0000-000a-0000000000a1', 'people', 100000, 'car_damage',
                       '00000000-0000-0000-000a-0000000000c1')
from unnest(array['00000000-0000-0000-000a-0000000000b1', '00000000-0000-0000-000a-0000000000b2',
                  '00000000-0000-0000-000a-0000000000b3']::uuid[]) id;
select pg_temp.move(id, 'scoring', 'open')
from unnest(array['00000000-0000-0000-000a-0000000000b1', '00000000-0000-0000-000a-0000000000b2',
                  '00000000-0000-0000-000a-0000000000b3']::uuid[]) id;
select set_config('test.inv' || right(id::text, 1), pg_temp.evidence(id, 'invoice')::text, true)
from unnest(array['00000000-0000-0000-000a-0000000000b1', '00000000-0000-0000-000a-0000000000b2',
                  '00000000-0000-0000-000a-0000000000b3']::uuid[]) id;
-- Captured money, the older contribution first. p3 has one 1000.00 contribution.
insert into public.contributions (id, request_id, contributor_id, source, amount_cents, status, created_at) values
  ('00000000-0000-0000-000a-0000000000e1', '00000000-0000-0000-000a-0000000000b1', '00000000-0000-0000-000a-0000000000a2', 'gift', 60000, 'captured', now() - interval '1 hour'),
  ('00000000-0000-0000-000a-0000000000e2', '00000000-0000-0000-000a-0000000000b1', '00000000-0000-0000-000a-0000000000a2', 'gift', 40000, 'captured', now()),
  ('00000000-0000-0000-000a-0000000000e3', '00000000-0000-0000-000a-0000000000b2', '00000000-0000-0000-000a-0000000000a2', 'gift', 60000, 'captured', now() - interval '1 hour'),
  ('00000000-0000-0000-000a-0000000000e4', '00000000-0000-0000-000a-0000000000b2', '00000000-0000-0000-000a-0000000000a2', 'gift', 40000, 'captured', now()),
  ('00000000-0000-0000-000a-0000000000e5', '00000000-0000-0000-000a-0000000000b3', '00000000-0000-0000-000a-0000000000a2', 'gift', 100000, 'captured', now());
-- p1: 300.00 already sent to the shop.
insert into public.payouts (id, request_id, payee_id, amount_cents, invoice_evidence_id, status)
values ('00000000-0000-0000-000a-0000000000f1', '00000000-0000-0000-000a-0000000000b1',
        '00000000-0000-0000-000a-0000000000c1', 30000, current_setting('test.inv1')::uuid, 'sent');

select is((select array_agg(status order by id) from public.requests where member_id = '00000000-0000-0000-000a-0000000000a1'),
  array['funded', 'funded', 'funded']::public.request_status[], 'fixture: all three requests are funded');

-- --- money with the payee: a person handles it ----------------------------------------
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000a-0000000000a3');
select is(public.record_review('00000000-0000-0000-000a-0000000000b1', 'refuse', 'The invoice is for another car.'),
  'in_review'::public.request_status, 'refusing a request with money at the payee routes it to review instead');
reset role;
select is((select count(*) from public.reviews where request_id = '00000000-0000-0000-000a-0000000000b1' and decision = 'refuse')
        + (select count(*) from private.audit_log where action = 'review.refuse_held_for_payout'
           and target_id = '00000000-0000-0000-000a-0000000000b1'), 2::bigint,
  'the refusal is still written down, and the hold is audit-logged');
insert into public.reviews (request_id, reviewer_id, decision, reason)
values ('00000000-0000-0000-000a-0000000000b1', '00000000-0000-0000-000a-0000000000a3', 'refuse', 'Direct refusal attempt.');
select throws_ok($$update public.requests set status = 'refused' where id = '00000000-0000-0000-000a-0000000000b1'$$,
  '23514', 'a payout to the payee is pending or sent; a person handles this request until it is returned',
  'even with a same-transaction review, a request with a sent payout cannot be refused');
select pg_temp.move('00000000-0000-0000-000a-0000000000b1', 'open');
select throws_ok($$update public.requests set status = 'withdrawn' where id = '00000000-0000-0000-000a-0000000000b1'$$,
  '23514', 'a payout to the payee is pending or sent; a person handles this request until it is returned',
  'a request with a sent payout cannot be withdrawn');
select throws_ok($$update public.requests set status = 'expired' where id = '00000000-0000-0000-000a-0000000000b1'$$,
  '23514', 'a payout to the payee is pending or sent; a person handles this request until it is returned',
  'a request with a sent payout cannot expire');
select lives_ok(
  $$update public.payouts set status = 'returned' where id = '00000000-0000-0000-000a-0000000000f1'$$,
  'the partner reports the payout returned, even though the request is no longer funded');
set local role authenticated;
select is(public.record_review('00000000-0000-0000-000a-0000000000b1', 'refuse', 'Second look: still another car.'),
  'refused'::public.request_status, 'once the payout is returned, the request can be refused');
reset role;
set local role service_role;
select pg_temp.as_service();
select results_eq(
  $$select contribution_id, refund_cents from public.refunds_due
    where request_id = '00000000-0000-0000-000a-0000000000b1' order by created_at$$,
  $$values ('00000000-0000-0000-000a-0000000000e1'::uuid, 60000::bigint), ('00000000-0000-0000-000a-0000000000e2', 40000)$$,
  'with the payout returned, all the captured money is refunded');

-- --- refunds net of payouts --------------------------------------------------------------
-- p2: a 700.00 payout fails, the request is refused, then the partner reports it sent after all.
reset role;
insert into public.payouts (id, request_id, payee_id, amount_cents, invoice_evidence_id, status)
values ('00000000-0000-0000-000a-0000000000f2', '00000000-0000-0000-000a-0000000000b2',
        '00000000-0000-0000-000a-0000000000c1', 70000, current_setting('test.inv2')::uuid, 'pending');
update public.payouts set status = 'failed' where id = '00000000-0000-0000-000a-0000000000f2';
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000a-0000000000a3');
select is(public.record_review('00000000-0000-0000-000a-0000000000b2', 'refuse', 'Photos show a different vehicle.'),
  'refused'::public.request_status, 'a failed payout does not hold a refusal');
reset role;
select lives_ok($$update public.payouts set status = 'sent' where id = '00000000-0000-0000-000a-0000000000f2'$$,
  'a late "sent" report from the partner is still recorded on a refused request');
set local role service_role;
select pg_temp.as_service();
select results_eq(
  $$select contribution_id, refund_cents from public.refunds_due
    where request_id = '00000000-0000-0000-000a-0000000000b2' order by created_at$$,
  $$values ('00000000-0000-0000-000a-0000000000e4'::uuid, 30000::bigint)$$,
  'the payout takes the oldest money first; only what the payee did not get is refunded');
select throws_ok($$select public.mark_refunded('00000000-0000-0000-000a-0000000000e3', 're_sp_1')$$,
  'P0002', 'contribution not found or not due a refund', 'money that reached the payee is not refunded');
select lives_ok($$select public.mark_refunded('00000000-0000-0000-000a-0000000000e4', 're_sp_2')$$,
  'the service refunds the part not paid out');
reset role;
select is((select (status, refunded_cents, amount_cents)::text from public.contributions
           where id = '00000000-0000-0000-000a-0000000000e4'), '(refunded,30000,40000)',
  'the refund records how much went back, not the whole contribution');
select is((select count(*) from public.refunds_due where request_id = '00000000-0000-0000-000a-0000000000b2'), 0::bigint,
  'nothing more is due on the request');

-- --- 'paid' needs a sent payout covered by captured money ------------------------------------
select throws_ok($$update public.requests set status = 'paid' where id = '00000000-0000-0000-000a-0000000000b3'$$,
  '23514', 'a request is paid once a payout to its payee has been sent', 'a request is not paid before any payout is sent');
insert into public.payouts (id, request_id, payee_id, amount_cents, invoice_evidence_id, status)
values ('00000000-0000-0000-000a-0000000000f3', '00000000-0000-0000-000a-0000000000b3',
        '00000000-0000-0000-000a-0000000000c1', 100000, current_setting('test.inv3')::uuid, 'pending');
update public.payees set status = 'suspended' where id = '00000000-0000-0000-000a-0000000000c1';
select lives_ok($$update public.payouts set status = 'sent' where id = '00000000-0000-0000-000a-0000000000f3'$$,
  'the partner''s "sent" is recorded even if the payee was suspended after the payout was created');
select ok((select sent_at is not null from public.payouts where id = '00000000-0000-0000-000a-0000000000f3'),
  'a payout records when it was sent (the open books count it by that)');
select ok((select sent_at is not null from public.payouts where id = '00000000-0000-0000-000a-0000000000f1'),
  'a payout recorded as sent when it is created gets a sent time');
update public.payees set status = 'verified' where id = '00000000-0000-0000-000a-0000000000c1';
update public.contributions set status = 'released' where id = '00000000-0000-0000-000a-0000000000e5';
select throws_ok($$update public.requests set status = 'paid' where id = '00000000-0000-0000-000a-0000000000b3'$$,
  '23514', 'captured contributions (0) do not cover the payouts sent (100000)',
  'a request is not paid if captured money does not cover what was sent');
update public.contributions set status = 'captured' where id = '00000000-0000-0000-000a-0000000000e5';
select lives_ok($$update public.requests set status = 'paid' where id = '00000000-0000-0000-000a-0000000000b3'$$,
  'a sent payout covered by captured money lets the request be paid');

-- --- service-only wrappers for private writes -------------------------------------------------
select ok(not has_function_privilege('anon', 'public.record_fraud_signal(uuid, text, text, jsonb)', 'execute')
          and not has_function_privilege('anon', 'public.resolve_fraud_signal(bigint)', 'execute')
          and not has_function_privilege('anon', 'public.record_identity_check(uuid, text, text)', 'execute')
          and has_function_privilege('service_role', 'public.record_fraud_signal(uuid, text, text, jsonb)', 'execute')
          and has_function_privilege('service_role', 'public.resolve_fraud_signal(bigint)', 'execute')
          and has_function_privilege('service_role', 'public.record_identity_check(uuid, text, text)', 'execute'),
  'the private-write wrappers are executable by the service role and not by anon');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000a-0000000000a1');
select throws_ok($$select public.record_fraud_signal('00000000-0000-0000-000a-0000000000b1', 'x', 'low')$$,
  '42501', 'permission denied for function record_fraud_signal', 'members cannot record fraud signals');
select throws_ok($$select public.resolve_fraud_signal(1)$$,
  '42501', 'permission denied for function resolve_fraud_signal', 'members cannot resolve fraud signals');
select pg_temp.login('00000000-0000-0000-000a-0000000000a4');
select throws_ok($$select public.record_identity_check('00000000-0000-0000-000a-0000000000a4', 'kyc', 'me')$$,
  '42501', 'permission denied for function record_identity_check', 'members cannot verify themselves');

reset role;
set local role service_role;
select pg_temp.as_service();
select isnt(set_config('test.sig', public.record_fraud_signal('00000000-0000-0000-000a-0000000000b1', 'duplicate_photo', 'high',
  '{"matched_request":"other"}')::text, true), null, 'the service records a fraud signal');
select throws_ok($$select public.record_fraud_signal('00000000-0000-0000-000a-0000000000b1', 'x', 'medium')$$,
  '23514', null, 'severity is low or high');
select throws_ok($$select public.record_fraud_signal('00000000-0000-0000-000a-00000000ffff', 'x', 'low')$$,
  'P0002', 'request not found', 'a signal needs a real request');
select lives_ok($$select public.resolve_fraud_signal(current_setting('test.sig')::bigint)$$, 'the service resolves it');
select throws_ok($$select public.resolve_fraud_signal(current_setting('test.sig')::bigint)$$,
  'P0002', 'signal not found or already resolved', 'a signal is resolved once');
reset role;
select is((select (severity, kind, detail ->> 'matched_request', resolved_at is not null)::text from private.fraud_signals
           where id = current_setting('test.sig')::bigint), '(high,duplicate_photo,other,t)',
  'the signal is stored with its detail and resolution');
select is((select array_agg(action order by id) from private.audit_log
           where target_id = '00000000-0000-0000-000a-0000000000b1' and action like 'fraud_signal.%'),
  array['fraud_signal.recorded', 'fraud_signal.resolved'], 'recording and resolving are audit-logged');

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.record_identity_check('00000000-0000-0000-000a-0000000000a4', 'kyc-vendor', 'ref_1')$$,
  'the service records a passed identity check');
select lives_ok($$select public.record_identity_check('00000000-0000-0000-000a-0000000000a4', 'kyc-vendor', 'ref_2')$$,
  're-verifying updates the reference');
select throws_ok($$select public.record_identity_check('00000000-0000-0000-000a-0000000000a5', 'kyc-vendor', 'ref_3')$$,
  '23514', 'member is suspended; an identity check does not change that', 'an identity check never lifts a suspension');
select throws_ok($$select public.record_identity_check('00000000-0000-0000-000a-00000000ffff', 'kyc-vendor', 'ref_4')$$,
  'P0002', 'member not found', 'an identity check needs a real member');
reset role;
select is((select (m.status, i.provider, i.provider_ref)::text from public.members m
           join private.member_identity i on i.member_id = m.id
           where m.id = '00000000-0000-0000-000a-0000000000a4'), '(active,kyc-vendor,ref_2)',
  'the member becomes active and the vendor''s latest reference is kept');
select is((select count(*) from private.audit_log where action = 'identity.verified'
           and target_id = '00000000-0000-0000-000a-0000000000a4'), 2::bigint, 'each identity check is audit-logged');
select is((select status from public.members where id = '00000000-0000-0000-000a-0000000000a5'),
  'suspended'::public.member_status, 'the suspended member stays suspended');

select * from finish();
rollback;
