-- The books: double-entry journals, append-only history, and payout guards.
--
-- Properties this file pins:
--   * private.post_journal accepts a balanced journal and refuses (at commit)
--     one that doesn't balance or that touches another fund's account;
--   * fund-level ledger accounts are unique, so a journal line can't double-post;
--   * ledger lines and journals, scores, reviews, request_events and the audit
--     log are append-only: update and delete raise, even for the owner;
--   * a payout goes only to the request's verified payee, against an invoice on
--     that request, for a funded request, and never beyond captured money.
-- Deferred constraint triggers are forced with `set constraints all immediate`
-- inside the asserted statement, since the test transaction never commits.
begin;
select plan(29);

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

select pg_temp.member('00000000-0000-0000-0006-0000000000a1', 'CA');  -- requester
select pg_temp.member('00000000-0000-0000-0006-0000000000a2', 'NY');  -- giver
select pg_temp.payee('00000000-0000-0000-0006-0000000000c1');                                -- the request's shop
select pg_temp.payee('00000000-0000-0000-0006-0000000000c2');                                -- some other shop
select pg_temp.payee('00000000-0000-0000-0006-0000000000c3', 'repair_shop', 'pending');      -- not verified

-- --- journals --------------------------------------------------------------------
select lives_ok(
  $$select private.post_journal('protection', 'subscription', null, 'pi_test_1',
      '[{"code":"partner_cash","amount_cents":800},{"code":"available","amount_cents":-800}]');
    set constraints all immediate$$,
  'a balanced journal posts');
-- A successful `set constraints all immediate` sticks for the transaction; put
-- the default back so later statements see commit-time behaviour.
set constraints all deferred;
select is((select count(*) from private.ledger_lines l join private.ledger_journals j on j.id = l.journal_id
           where j.partner_ref = 'pi_test_1'), 2::bigint, 'both lines are recorded');
select throws_like(
  $$select private.post_journal('protection', 'subscription', null, 'pi_test_2',
      '[{"code":"partner_cash","amount_cents":800},{"code":"available","amount_cents":-700}]');
    set constraints all immediate$$,
  '%does not balance (off by 100 cents)', 'an unbalanced journal fails at commit');
select throws_like(
  $$select private.post_journal('protection', 'transfer', null, 'pi_test_3',
      '[{"code":"available","amount_cents":-500},{"code":"available","fund":"home_fund","amount_cents":500}]');
    set constraints all immediate$$,
  '%moves money between funds; the pools never mix', 'a journal touching another fund''s account fails at commit');
select throws_ok(
  $$select private.post_journal('protection', 'subscription', null, 'pi_test_4',
      '[{"code":"partner_cash","amount_cents":800},{"code":"petty_cash","amount_cents":-800}]')$$,
  '23503', 'unknown ledger account in journal', 'a line naming an unknown account fails');
select throws_ok(
  $$insert into private.ledger_accounts (fund, code) values ('protection', 'available')$$,
  '23505', null, 'a fund-level account cannot be duplicated (it would double-post)');

-- --- append-only -----------------------------------------------------------------
select throws_ok($$update private.ledger_lines set amount_cents = 1$$, '42501', 'ledger_lines is append-only',
  'ledger lines cannot be edited');
select throws_ok($$delete from private.ledger_lines$$, '42501', 'ledger_lines is append-only',
  'ledger lines cannot be deleted');
select throws_ok($$update private.ledger_journals set memo = 'oops'$$, '42501', 'ledger_journals is append-only',
  'journals cannot be edited');
select throws_ok($$delete from private.ledger_journals$$, '42501', 'ledger_journals is append-only',
  'journals cannot be deleted');

-- A request with a score, a review, events and an audit row to try to rewrite.
select pg_temp.request('00000000-0000-0000-0006-0000000000b9', '00000000-0000-0000-0006-0000000000a1');
select pg_temp.move('00000000-0000-0000-0006-0000000000b9', 'scoring');
select public.record_score('00000000-0000-0000-0006-0000000000b9', 50::smallint, '["thin evidence"]', 'm', '1', 'p1', 'h');
insert into public.reviews (request_id, reviewer_id, decision, reason)
values ('00000000-0000-0000-0006-0000000000b9', '00000000-0000-0000-0006-0000000000a2', 'needs_evidence', 'Please add the estimate.');
select private.audit('test.action', 'requests', '00000000-0000-0000-0006-0000000000b9');

select throws_ok($$update public.scores set score = 100 where request_id = '00000000-0000-0000-0006-0000000000b9'$$,
  '42501', 'scores is append-only', 'scores cannot be edited');
select throws_ok($$delete from public.scores where request_id = '00000000-0000-0000-0006-0000000000b9'$$,
  '42501', 'scores is append-only', 'scores cannot be deleted');
select throws_ok($$update public.reviews set decision = 'approve' where request_id = '00000000-0000-0000-0006-0000000000b9'$$,
  '42501', 'reviews is append-only', 'reviews cannot be edited');
select throws_ok($$delete from public.reviews where request_id = '00000000-0000-0000-0006-0000000000b9'$$,
  '42501', 'reviews is append-only', 'reviews cannot be deleted');
select throws_ok($$update public.request_events set to_status = 'paid' where request_id = '00000000-0000-0000-0006-0000000000b9'$$,
  '42501', 'request_events is append-only', 'request history cannot be edited');
select throws_ok($$delete from public.request_events where request_id = '00000000-0000-0000-0006-0000000000b9'$$,
  '42501', 'request_events is append-only', 'request history cannot be deleted');
select throws_ok($$update private.audit_log set action = 'nothing' where target_id = '00000000-0000-0000-0006-0000000000b9'$$,
  '42501', 'audit_log is append-only', 'the audit log cannot be edited');
select throws_ok($$delete from private.audit_log where target_id = '00000000-0000-0000-0006-0000000000b9'$$,
  '42501', 'audit_log is append-only', 'the audit log cannot be deleted');

-- --- payouts ------------------------------------------------------------------------
-- b1: funded, payee c1, 600.00 captured + 400.00 still pledged, with an invoice and a photo.
-- b2: open, payee c1, with an invoice. b3: funded, payee c3 (unverified), with an invoice.
select pg_temp.request('00000000-0000-0000-0006-0000000000b1', '00000000-0000-0000-0006-0000000000a1', 'people', 100000,
                       'car_damage', '00000000-0000-0000-0006-0000000000c1');
select pg_temp.request('00000000-0000-0000-0006-0000000000b2', '00000000-0000-0000-0006-0000000000a1', 'people', 100000,
                       'car_damage', '00000000-0000-0000-0006-0000000000c1');
select pg_temp.request('00000000-0000-0000-0006-0000000000b3', '00000000-0000-0000-0006-0000000000a1', 'people', 100000,
                       'car_damage', '00000000-0000-0000-0006-0000000000c3');
select pg_temp.move(id, 'scoring', 'open')
from unnest(array['00000000-0000-0000-0006-0000000000b1', '00000000-0000-0000-0006-0000000000b2',
                  '00000000-0000-0000-0006-0000000000b3']::uuid[]) id;
insert into public.contributions (request_id, contributor_id, source, amount_cents, status) values
  ('00000000-0000-0000-0006-0000000000b1', '00000000-0000-0000-0006-0000000000a2', 'gift', 60000, 'captured'),
  ('00000000-0000-0000-0006-0000000000b1', '00000000-0000-0000-0006-0000000000a2', 'gift', 40000, 'pledged'),
  ('00000000-0000-0000-0006-0000000000b3', '00000000-0000-0000-0006-0000000000a2', 'gift', 100000, 'captured');
select set_config('test.inv1', pg_temp.evidence('00000000-0000-0000-0006-0000000000b1', 'invoice')::text, true);
select set_config('test.photo1', pg_temp.evidence('00000000-0000-0000-0006-0000000000b1', 'photo')::text, true);
select set_config('test.inv2', pg_temp.evidence('00000000-0000-0000-0006-0000000000b2', 'invoice')::text, true);
select set_config('test.inv3', pg_temp.evidence('00000000-0000-0000-0006-0000000000b3', 'invoice')::text, true);

select is((select array_agg(status order by id) from public.requests
           where id in ('00000000-0000-0000-0006-0000000000b1', '00000000-0000-0000-0006-0000000000b3')),
  array['funded', 'funded']::public.request_status[], 'fixture: both requests are funded');

select throws_ok(
  $$insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id)
    values ('00000000-0000-0000-0006-0000000000b1', '00000000-0000-0000-0006-0000000000c2', 10000, current_setting('test.inv1')::uuid)$$,
  '42501', 'money goes only to the request''s named payee', 'a payout cannot go to another payee');
select throws_ok(
  $$insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id)
    values ('00000000-0000-0000-0006-0000000000b3', '00000000-0000-0000-0006-0000000000c3', 10000, current_setting('test.inv3')::uuid)$$,
  '42501', 'payee is not verified', 'a payout cannot go to an unverified payee');
select throws_ok(
  $$insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id)
    values ('00000000-0000-0000-0006-0000000000b1', '00000000-0000-0000-0006-0000000000c1', 10000, current_setting('test.photo1')::uuid)$$,
  '23514', 'a payout needs the payee''s final invoice on this request', 'a payout needs an invoice, not a photo');
select throws_ok(
  $$insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id)
    values ('00000000-0000-0000-0006-0000000000b1', '00000000-0000-0000-0006-0000000000c1', 10000, current_setting('test.inv2')::uuid)$$,
  '23514', 'a payout needs the payee''s final invoice on this request', 'the invoice must be on this request');
select throws_ok(
  $$insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id)
    values ('00000000-0000-0000-0006-0000000000b2', '00000000-0000-0000-0006-0000000000c1', 10000, current_setting('test.inv2')::uuid)$$,
  '23514', 'only funded requests are paid out', 'an open request is not paid out');
select throws_ok(
  $$insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id)
    values ('00000000-0000-0000-0006-0000000000b1', '00000000-0000-0000-0006-0000000000c1', 60001, current_setting('test.inv1')::uuid)$$,
  '23514', 'payouts cannot exceed captured contributions', 'pledged money cannot be paid out, only captured');
select lives_ok(
  $$insert into public.payouts (id, request_id, payee_id, amount_cents, invoice_evidence_id)
    values ('00000000-0000-0000-0006-0000000000f1', '00000000-0000-0000-0006-0000000000b1',
            '00000000-0000-0000-0006-0000000000c1', 60000, current_setting('test.inv1')::uuid)$$,
  'a payout of the captured amount to the verified payee against the invoice succeeds');
select throws_ok(
  $$insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id)
    values ('00000000-0000-0000-0006-0000000000b1', '00000000-0000-0000-0006-0000000000c1', 1, current_setting('test.inv1')::uuid)$$,
  '23514', 'payouts cannot exceed captured contributions', 'payouts together cannot exceed captured money');
select lives_ok(
  $$update public.payouts set status = 'sent', partner_ref = 'tr_test_1' where id = '00000000-0000-0000-0006-0000000000f1'$$,
  'the partner confirms the payout as sent');
select is((select array_agg(action order by id) from private.audit_log
           where target = 'payouts' and target_id = '00000000-0000-0000-0006-0000000000f1'),
  array['payout.pending', 'payout.sent'], 'every payout write is audit-logged');

select * from finish();
rollback;
