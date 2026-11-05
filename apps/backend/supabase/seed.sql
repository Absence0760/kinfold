-- Local-stack seed. Runs on `supabase db reset`.
--
-- LOCAL-ONLY DEV DATA. Everything here is throwaway: fictional people, shops and
-- amounts, so the app has something to show on a laptop. The dev password grants
-- access to nothing outside a container on this machine, which is why it is
-- committed (see CLAUDE.md, "Local-dev env is committed; real secrets never are").
-- Never run this against a real project.
--
-- Dev logins (password for all: testtest). The web sign-in page offers each as a
-- one-click demo account; keep apps/web/src/lib/auth/demo-accounts.ts in step:
--   maria@test.com  member, CA: a draft, a funded request with a family loan
--   sam@test.com    member, CA: maria's brother and lender; an open request on the board
--   james@test.com  member + reviewer, NY (outside CA, so he can review maria and sam)
--   priya@test.com  member + appeal panel, TX: a request already paid from the pool
--   (also b5, sam's request needing evidence, and b6, maria's refused and appealed
--   request, so the review console at /app/review has work for james and priya)
--   kofi@test.com   member + reviewer, IL: a Home Fund repair half granted, a Home Fund loan
--   ben@test.com    member, TN: lends at 0% to five friends (on time, paused, behind,
--                   repaid, defaulted) and gave one mortgage gap in full
--   nora@test.com   member, PA: joined three days ago, identity check still pending
--   The wider community (thirteen more members, 23 more requests) is in the
--   section "the wider community" at the end; its other members sign in with the
--   same password (daniel, rosa, mei, tomas, hannah, grace, luis, aisha, omar, ivy
--   @test.com), and wren@test.com is a sign-up with no member row yet.
--
-- Where possible the data is made through the real functions (submit_request,
-- record_score, create_invite, pledge, set_loan_terms, set_loan_schedule, sign_loan), acting as
-- each member via request.jwt.claims, so the seed exercises the same rules the
-- app does. Writes only the service role can make (scores, pool runs, payouts)
-- are done directly, as postgres.

-- --- people ----------------------------------------------------------------------

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data, is_super_admin,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select '00000000-0000-0000-0000-000000000000', id::uuid, 'authenticated', 'authenticated', email,
       extensions.crypt('testtest', extensions.gen_salt('bf')),
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}', false, '', '', '', ''
from (values
  ('00000000-0000-0000-0000-0000000000a1', 'maria@test.com'),
  ('00000000-0000-0000-0000-0000000000a2', 'james@test.com'),
  ('00000000-0000-0000-0000-0000000000a3', 'priya@test.com'),
  ('00000000-0000-0000-0000-0000000000a4', 'sam@test.com')
) u (id, email);

insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select id::text, id,
       jsonb_build_object('sub', id::text, 'email', email, 'email_verified', true, 'phone_verified', false),
       'email', now(), now(), now()
from auth.users
where id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2',
             '00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000a4');

insert into public.members (id, display_name, region, status, joined_at) values
  ('00000000-0000-0000-0000-0000000000a1', 'Maria',  'CA', 'active', now() - interval '7 months'),
  ('00000000-0000-0000-0000-0000000000a2', 'James',  'NY', 'active', now() - interval '7 months'),
  ('00000000-0000-0000-0000-0000000000a3', 'Priya',  'TX', 'active', now() - interval '7 months'),
  ('00000000-0000-0000-0000-0000000000a4', 'Sam',    'CA', 'active', now() - interval '7 months');

insert into private.member_identity (member_id, provider, provider_ref)
select id, 'dev-kyc', 'dev_' || display_name from public.members
where id::text like '00000000-0000-0000-0000-0000000000a_';

insert into public.member_roles (member_id, role) values
  ('00000000-0000-0000-0000-0000000000a2', 'reviewer'),
  ('00000000-0000-0000-0000-0000000000a3', 'panel');

-- --- subscriptions: six captured months each, so the pool waiting period has passed ---

insert into public.income_verifications (id, member_id, method, monthly_income_cents, verified_at)
values
  ('00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000000a1', 'bank_link',     420000, now() - interval '7 months'),
  ('00000000-0000-0000-0000-0000000001a2', '00000000-0000-0000-0000-0000000000a2', 'tax_return',    800000, now() - interval '7 months'),
  ('00000000-0000-0000-0000-0000000001a3', '00000000-0000-0000-0000-0000000000a3', 'bank_link',     310000, now() - interval '7 months'),
  ('00000000-0000-0000-0000-0000000001a4', '00000000-0000-0000-0000-0000000000a4', 'self_attested', 140000, now() - interval '7 months');

insert into public.subscriptions (id, member_id, formula_version, income_verification_id, monthly_cents, starts_on)
select ('00000000-0000-0000-0000-0000000002' || right(iv.id::text, 2))::uuid, iv.member_id, 1, iv.id,
       public.subscription_amount(iv.monthly_income_cents, 1),   -- 42.00, 60.00 (cap), 31.00, 0 (below floor)
       date_trunc('month', now() - interval '6 months')::date
from public.income_verifications iv
where iv.id::text like '00000000-0000-0000-0000-0000000001a_';

insert into public.subscription_payments (subscription_id, member_id, period, amount_cents, status, partner_ref, captured_at)
select s.id, s.member_id, p::date, s.monthly_cents, 'captured',
       'dev_pi_' || right(s.member_id::text, 2) || '_' || to_char(p, 'YYYYMM'), p + interval '2 days'
from public.subscriptions s,
     generate_series(date_trunc('month', now() - interval '6 months'), date_trunc('month', now() - interval '1 month'),
                     interval '1 month') p
where s.id::text like '00000000-0000-0000-0000-0000000002a_';

insert into public.allocation_preferences (member_id, target, weight_pct) values
  ('00000000-0000-0000-0000-0000000000a1', 'car_damage', 50),
  ('00000000-0000-0000-0000-0000000000a1', 'highest_score', 50),
  ('00000000-0000-0000-0000-0000000000a4', 'home_help', 100);

-- --- payees and covered assets ----------------------------------------------------------

insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at) values
  ('00000000-0000-0000-0000-0000000000c1', 'repair_shop', 'Eastside Auto Body (dev)',         'CA', 'verified', 'dev_acct_eastside', now() - interval '1 year'),
  ('00000000-0000-0000-0000-0000000000c2', 'lender',      'Golden State Credit Union (dev)',  'CA', 'verified', 'dev_acct_gscu',     now() - interval '1 year'),
  ('00000000-0000-0000-0000-0000000000c3', 'repair_shop', 'Lone Star Collision (dev)',        'TX', 'verified', 'dev_acct_lonestar', now() - interval '1 year'),
  ('00000000-0000-0000-0000-0000000000c4', 'contractor',  'Golden Gate Contracting (dev)',    'CA', 'verified', 'dev_acct_goldengate', now() - interval '1 year');

insert into public.covered_assets (id, member_id, kind, description, value_cents, registered_on, verified_at) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a1', 'vehicle', '2016 Honda Fit',    850000,  current_date - 180, now() - interval '6 months'),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000a4', 'vehicle', '2012 Toyota Camry', 600000,  current_date - 180, now() - interval '6 months'),
  ('00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000a3', 'vehicle', '2019 Ford Focus',   1100000, current_date - 180, now() - interval '6 months');

-- --- requests ---------------------------------------------------------------------------
-- b1 maria  draft          home_repair, redaction auto-done, member confirms it in the app
-- b2 sam    open (board)   car_damage, pool, scored 86
-- b3 maria  funded         car_deductible, people: sam gives and lends
-- b4 priya  paid           car_damage, pool: pool grant, invoice, payout sent

insert into public.requests (id, member_id, kind, funding, title, description, amount_cents, incident_on, asset_id, payee_id) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', 'home_repair', 'people',
   'Roof leak over the kitchen', 'Storm damage; contractor quote to follow.', 240000, current_date - 3, null, null),
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000a4', 'car_damage', 'pool',
   'Rear-ended at a stop light', 'Other driver uninsured. Shop estimate attached.', 185000, current_date - 9,
   '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000c1'),
  ('00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000a1', 'car_deductible', 'people',
   'Deductible after a hailstorm', 'Insurer covers the rest; this is my deductible.', 100000, current_date - 20,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1'),
  ('00000000-0000-0000-0000-0000000000b4', '00000000-0000-0000-0000-0000000000a3', 'car_damage', 'pool',
   'Side mirror and door after a hit-and-run', 'Police report and photos attached.', 72000, current_date - 40,
   '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000c3');

insert into public.evidence (request_id, kind, original_path, redacted_path, sha256, captured_in_app, redaction_status) values
  ('00000000-0000-0000-0000-0000000000b1', 'photo',
   '00000000-0000-0000-0000-0000000000a1/b1-ceiling.jpg', '00000000-0000-0000-0000-0000000000a1/b1-ceiling-redacted.jpg', repeat('1', 64), true, 'auto_done'),
  ('00000000-0000-0000-0000-0000000000b2', 'photo',
   '00000000-0000-0000-0000-0000000000a4/b2-rear.jpg', '00000000-0000-0000-0000-0000000000a4/b2-rear.jpg', repeat('2', 64), true, 'confirmed'),
  ('00000000-0000-0000-0000-0000000000b2', 'estimate',
   '00000000-0000-0000-0000-0000000000a4/b2-estimate.pdf', '00000000-0000-0000-0000-0000000000a4/b2-estimate.pdf', repeat('3', 64), false, 'confirmed'),
  ('00000000-0000-0000-0000-0000000000b3', 'photo',
   '00000000-0000-0000-0000-0000000000a1/b3-hail.jpg', '00000000-0000-0000-0000-0000000000a1/b3-hail.jpg', repeat('4', 64), true, 'confirmed'),
  ('00000000-0000-0000-0000-0000000000b4', 'police_report',
   '00000000-0000-0000-0000-0000000000a3/b4-report.pdf', '00000000-0000-0000-0000-0000000000a3/b4-report.pdf', repeat('5', 64), false, 'confirmed'),
  ('00000000-0000-0000-0000-0000000000b4', 'invoice',
   '00000000-0000-0000-0000-0000000000a3/b4-invoice.pdf', '00000000-0000-0000-0000-0000000000a3/b4-invoice.pdf', repeat('6', 64), false, 'confirmed');

-- Each owner submits (the real eligibility checks run, pool waiting period included).
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', false);
select public.submit_request('00000000-0000-0000-0000-0000000000b2');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', false);
select public.submit_request('00000000-0000-0000-0000-0000000000b3');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}', false);
select public.submit_request('00000000-0000-0000-0000-0000000000b4');

-- The scoring service (no user) scores them; all three clear min_score and open.
select set_config('request.jwt.claims', '{"role":"service_role"}', false);
select public.record_score('00000000-0000-0000-0000-0000000000b2', 86::smallint,
  '["damage in photos matches the shop estimate", "estimate is itemised and dated after the incident"]',
  'dev-scorer', '0.0.1', 'score-v1', repeat('a', 64));
select public.record_score('00000000-0000-0000-0000-0000000000b3', 78::smallint,
  '["hail pattern consistent across panels", "no insurer letter yet showing the deductible"]',
  'dev-scorer', '0.0.1', 'score-v1', repeat('b', 64));
select public.record_score('00000000-0000-0000-0000-0000000000b4', 93::smallint,
  '["police report date matches the photos", "invoice from a verified shop"]',
  'dev-scorer', '0.0.1', 'score-v1', repeat('c', 64));

-- The redaction step writes the board summaries.
update public.requests set public_summary = 'Rear bumper and trunk after being rear-ended; uninsured driver.'
where id = '00000000-0000-0000-0000-0000000000b2';
update public.requests set public_summary = 'Side mirror and driver door after a hit-and-run.'
where id = '00000000-0000-0000-0000-0000000000b4';

-- Each owner confirms their summary, which is what puts it on the members-only board.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', false);
select public.confirm_public_summary('00000000-0000-0000-0000-0000000000b2');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}', false);
select public.confirm_public_summary('00000000-0000-0000-0000-0000000000b4');

-- b3: maria invites sam; he gives 300.00 and lends 700.00 at zero interest, which funds it.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', false);
select set_config('seed.invite', public.create_invite('00000000-0000-0000-0000-0000000000b3', 'brother'), false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', false);
select public.accept_invite(current_setting('seed.invite'));
select public.pledge('00000000-0000-0000-0000-0000000000b3', 30000, 'gift');
select public.pledge('00000000-0000-0000-0000-0000000000b3', 70000, 'loan');

-- The loan: repaid on the 15th, 7 monthly installments (the last takes the
-- remainder), forgive-the-rest if repayment ever stops. Sam sets the terms;
-- both sign. (imputed_rate_bps is written by the paperwork service.)
select public.set_loan_terms(id, 15, 3, 'forgive')
from public.family_loans where request_id = '00000000-0000-0000-0000-0000000000b3';
update public.family_loans set imputed_rate_bps = 0
where request_id = '00000000-0000-0000-0000-0000000000b3';
select public.set_loan_schedule(id, 7, (date_trunc('month', current_date + interval '1 month') + interval '14 days')::date)
from public.family_loans where request_id = '00000000-0000-0000-0000-0000000000b3';
select public.sign_loan(id) from public.family_loans where request_id = '00000000-0000-0000-0000-0000000000b3';
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', false);
select public.sign_loan(id) from public.family_loans where request_id = '00000000-0000-0000-0000-0000000000b3';

-- b4: a pool run granted priya's request in full; the partner captured it, the
-- shop was paid against its invoice. (Recorded directly: the pool run proper
-- would also allocate to sam's open request.)
select set_config('request.jwt.claims', '{"role":"service_role"}', false);
insert into public.pool_runs (id, fund, available_cents, reserve_cents, allocated_cents, settings, algorithm_version, run_at)
select '00000000-0000-0000-0000-0000000000f1', 'protection', 90000, 18000, 72000, to_jsonb(s), 'bands-v1', now() - interval '20 days'
from public.fund_settings s where s.fund = 'protection';
insert into public.pool_allocations (id, run_id, request_id, score, band, need_cents, grant_cents)
values ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000f1',
        '00000000-0000-0000-0000-0000000000b4', 93, 90, 72000, 72000);
insert into public.contributions (request_id, source, amount_cents, status, pool_allocation_id, partner_ref)
values ('00000000-0000-0000-0000-0000000000b4', 'pool', 72000, 'captured',
        '00000000-0000-0000-0000-0000000000f2', 'dev_pool_capture_b4');
insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id, status, partner_ref, created_at)
select '00000000-0000-0000-0000-0000000000b4', '00000000-0000-0000-0000-0000000000c3', 72000, e.id, 'sent',
       'dev_transfer_b4', now() - interval '15 days'
from public.evidence e where e.request_id = '00000000-0000-0000-0000-0000000000b4' and e.kind = 'invoice';
update public.requests set status = 'paid' where id = '00000000-0000-0000-0000-0000000000b4';

-- The books for that payout: committed from the pool, then paid out.
select public.post_journal('protection', 'pool_grant', '00000000-0000-0000-0000-0000000000f2', null,
  '[{"code":"available","amount_cents":72000},{"code":"committed","amount_cents":-72000}]');
select public.post_journal('protection', 'payout', '00000000-0000-0000-0000-0000000000b4', 'dev_transfer_b4',
  '[{"code":"available","amount_cents":-72000},{"code":"paid_out","amount_cents":72000}]');


-- --- work for the review console --------------------------------------------------------
-- b5 sam    needs_evidence  home_repair, people: scored below the minimum, so a person looks
-- b6 maria  refused         car_damage, people: james refused it, maria appealed (priya decides)

insert into public.requests (id, member_id, kind, funding, title, description, amount_cents, incident_on, payee_id) values
  ('00000000-0000-0000-0000-0000000000b5', '00000000-0000-0000-0000-0000000000a4', 'home_repair', 'people',
   'Burst pipe under the bathroom', 'Plumber came out; written quote still to come.', 120000, current_date - 5,
   '00000000-0000-0000-0000-0000000000c4'),
  ('00000000-0000-0000-0000-0000000000b6', '00000000-0000-0000-0000-0000000000a1', 'car_damage', 'people',
   'Scraped in a parking garage', 'Garage camera footage requested; shop estimate attached.', 65000, current_date - 12,
   '00000000-0000-0000-0000-0000000000c1');
insert into public.evidence (request_id, kind, original_path, redacted_path, sha256, captured_in_app, redaction_status) values
  ('00000000-0000-0000-0000-0000000000b5', 'photo',
   '00000000-0000-0000-0000-0000000000a4/b5-pipe.jpg', '00000000-0000-0000-0000-0000000000a4/b5-pipe.jpg', repeat('7', 64), false, 'confirmed'),
  ('00000000-0000-0000-0000-0000000000b6', 'estimate',
   '00000000-0000-0000-0000-0000000000a1/b6-estimate.pdf', '00000000-0000-0000-0000-0000000000a1/b6-estimate.pdf', repeat('8', 64), false, 'confirmed');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', false);
select public.submit_request('00000000-0000-0000-0000-0000000000b5');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', false);
select public.submit_request('00000000-0000-0000-0000-0000000000b6');
select set_config('request.jwt.claims', '{"role":"service_role"}', false);
select public.record_score('00000000-0000-0000-0000-0000000000b5', 58::smallint,
  '["one photo, taken outside the app", "no plumber quote or invoice yet"]',
  'dev-scorer', '0.0.1', 'score-v1', repeat('d', 64));
select public.record_score('00000000-0000-0000-0000-0000000000b6', 74::smallint,
  '["estimate from a verified shop", "photos of the damage are missing"]',
  'dev-scorer', '0.0.1', 'score-v1', repeat('e', 64));

-- james (NY) refuses b6; maria appeals, which leaves an open appeal for the panel.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', false);
select public.record_review('00000000-0000-0000-0000-0000000000b6', 'refuse',
  'The estimate is for a full rear panel, but the damage described is a scrape on the side.');
-- maria also declared insurer money that covered part of the same scrape, so
-- the request page can show what other money already paid for the damage.
insert into public.request_recoveries (request_id, source, amount_cents, recovered_on, note, partner_ref, verified_at, recorded_by)
  values ('00000000-0000-0000-0000-0000000000b6', 'insurance', 18000, current_date - 9,
          'the insurer confirmed the recovery letter', 'rf_dev_b6', now() - interval '6 days',
          '00000000-0000-0000-0000-0000000000a1');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', false);
select public.file_appeal('00000000-0000-0000-0000-0000000000b6',
  'The shop quoted the whole panel because the scrape runs from the door to the rear bumper. I can send photos.');


-- ========================================================================================
-- --- the wider community ----------------------------------------------------------------
-- ========================================================================================
-- Everything above is the four demo people's world, which the e2e suite
-- (apps/web/e2e-stack) asserts fact by fact; nothing below touches a row they
-- own, reads their requests, or makes them a supporter, lender or reviewer of
-- anything new. What follows fills the stack out so every screen has realistic
-- work on it: more members across the Census divisions, a request of every kind
-- in every status, family loans in every state, Home Fund loans, pool runs,
-- payouts, balanced books, cover, claims and invites.
--
-- Ids live in their own block, 00000000-0000-0000-5eed-…, which no pgTAP fixture
-- uses: members …-0000000000NN, requests …-0000000010NN, payees …-0000000020NN,
-- assets …-0000000030NN, income checks …-0000000040NN, subscriptions
-- …-0000000050NN, pool runs …-0000000060NN, allocations …-0000000061NN.
-- Dates are relative to current_date, so the seed reads the same on any day.
--
-- Same rule as above: made through the real functions, acting as each member
-- through request.jwt.claims, and written directly as postgres only where the
-- step is the service's or the partner's, or where time has to have passed
-- (a schedule can't be set in the past, so a loan's dates move back after it
-- is signed, standing in for months of collections).
--
-- The whole section runs as one DO block: the CLI sends seed.sql as a single
-- prepared batch, so a plain statement could not call a helper an earlier
-- statement created. Inside the block, `perform` is a statement-level select.

do $seed$
begin

create function pg_temp.m(n integer) returns uuid language sql immutable as
  $$ select ('00000000-0000-0000-5eed-0000000000' || lpad(n::text, 2, '0'))::uuid $$;
create function pg_temp.r(n integer) returns uuid language sql immutable as
  $$ select ('00000000-0000-0000-5eed-0000000010' || lpad(n::text, 2, '0'))::uuid $$;
create function pg_temp.p(n integer) returns uuid language sql immutable as
  $$ select ('00000000-0000-0000-5eed-0000000020' || lpad(n::text, 2, '0'))::uuid $$;
create function pg_temp.a(n integer) returns uuid language sql immutable as
  $$ select ('00000000-0000-0000-5eed-0000000030' || lpad(n::text, 2, '0'))::uuid $$;

-- Act as a member, or as the service (edge functions, the partner's webhooks).
create function pg_temp.act(p_member uuid) returns void language sql as
  $$ select set_config('request.jwt.claims',
                       json_build_object('sub', p_member, 'role', 'authenticated')::text, false) $$;
create function pg_temp.act_service() returns void language sql as
  $$ select set_config('request.jwt.claims', '{"role":"service_role"}', false) $$;

-- The loan a request's pledge created.
create function pg_temp.loan(p_request uuid) returns uuid language sql as
  $$ select id from public.family_loans where request_id = p_request $$;

-- Time passing on a signed schedule: every installment moves back p_months,
-- standing in for the months the partner has been collecting.
create function pg_temp.backdate(p_loan uuid, p_months integer) returns void language sql as $$
  update public.loan_installments set due_on = (due_on - make_interval(months => p_months))::date
  where loan_id = p_loan;
  update public.family_loans set created_at = created_at - make_interval(months => p_months + 1)
  where id = p_loan;
$$;

-- The partner settles installment p_seq in full, a day before it was due.
create function pg_temp.collect(p_loan uuid, p_seq integer) returns void language sql as $$
  select public.record_loan_payment(p_loan, p_seq,
    (select amount_cents - paid_cents from public.loan_installments where loan_id = p_loan and seq = p_seq));
  update public.loan_installments set paid_on = due_on - 1 where loan_id = p_loan and seq = p_seq;
$$;

-- --- people --------------------------------------------------------------------------------
--   01 Daniel  WA Pacific             lends Ivy a loan he later forgives
--   02 Rosa    AZ Mountain            two pool requests (one paid with an insurer claim)
--   03 Kofi    IL East North Central  REVIEWER (demo: kofi@test.com); a Home Fund loan
--   04 Mei     GA South Atlantic      APPEAL PANEL; a Home Fund repair paid by the pool
--   05 Tomás   FL South Atlantic      a fraud flag in review; a defaulted loan
--   06 Hannah  OH East North Central  a down payment repaying on time; dues still pending
--   07 Grace   MA New England         a paused loan; a proposed Home Fund loan
--   08 Luis    NM Mountain            a loan behind on payments; an upheld appeal
--   09 Aisha   MN West North Central  a restructured loan, a repaid loan, a denied claim
--   10 Ben     TN East South Central  LENDER with several loans (demo: ben@test.com)
--   11 Nora    PA Middle Atlantic     IDENTITY CHECK PENDING (demo: nora@test.com)
--   12 Omar    LA West South Central  joined twelve days ago; a draft
--   13 Ivy     CO Mountain            lends Aisha; her own deductible forgiven by Daniel
--   14 (auth user wren@test.com, no member row: signed up, never finished setting up)

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data, is_super_admin,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select '00000000-0000-0000-0000-000000000000', pg_temp.m(n), 'authenticated', 'authenticated', email,
       extensions.crypt('testtest', extensions.gen_salt('bf')),
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}', false, '', '', '', ''
from (values
  (1, 'daniel@test.com'), (2, 'rosa@test.com'), (3, 'kofi@test.com'), (4, 'mei@test.com'),
  (5, 'tomas@test.com'), (6, 'hannah@test.com'), (7, 'grace@test.com'), (8, 'luis@test.com'),
  (9, 'aisha@test.com'), (10, 'ben@test.com'), (11, 'nora@test.com'), (12, 'omar@test.com'),
  (13, 'ivy@test.com'), (14, 'wren@test.com')
) u (n, email);

insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select u.id::text, u.id,
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true, 'phone_verified', false),
       'email', now(), now(), now()
from auth.users u
where u.id::text like '00000000-0000-0000-5eed-0000000000__';

-- Everyone starts pending, as sign-up leaves them; the identity vendor's check
-- (record_identity_check, the service) is what makes a member active.
insert into public.members (id, display_name, region, status, joined_at) values
  (pg_temp.m(1),  'Daniel', 'WA', 'pending_verification', now() - interval '11 months'),
  (pg_temp.m(2),  'Rosa',   'AZ', 'pending_verification', now() - interval '10 months'),
  (pg_temp.m(3),  'Kofi',   'IL', 'pending_verification', now() - interval '14 months'),
  (pg_temp.m(4),  'Mei',    'GA', 'pending_verification', now() - interval '13 months'),
  (pg_temp.m(5),  'Tomás',  'FL', 'pending_verification', now() - interval '9 months'),
  (pg_temp.m(6),  'Hannah', 'OH', 'pending_verification', now() - interval '12 months'),
  (pg_temp.m(7),  'Grace',  'MA', 'pending_verification', now() - interval '10 months'),
  (pg_temp.m(8),  'Luis',   'NM', 'pending_verification', now() - interval '9 months'),
  (pg_temp.m(9),  'Aisha',  'MN', 'pending_verification', now() - interval '11 months'),
  (pg_temp.m(10), 'Ben',    'TN', 'pending_verification', now() - interval '16 months'),
  (pg_temp.m(11), 'Nora',   'PA', 'pending_verification', now() - interval '3 days'),
  (pg_temp.m(12), 'Omar',   'LA', 'pending_verification', now() - interval '12 days'),
  (pg_temp.m(13), 'Ivy',    'CO', 'pending_verification', now() - interval '10 months');

perform pg_temp.act_service();
perform public.record_identity_check(pg_temp.m(n), 'dev-kyc', 'dev_kyc_5eed_' || n)
from generate_series(1, 13) n
where n <> 11;   -- Nora's check hasn't come back yet

insert into public.member_roles (member_id, role) values
  (pg_temp.m(3), 'reviewer'),
  (pg_temp.m(4), 'panel');

-- --- income checks, subscriptions and dues -------------------------------------------------
-- One income check each (Nora's waits on her identity check); the dues follow
-- the published formula. History is the partner's captured months, written as
-- it reported them; this month's dues go through the real collection path
-- (enqueue_dues, then capture_dues) - except Hannah's, still pending.

insert into public.income_verifications (id, member_id, method, monthly_income_cents, provider_ref, verified_at)
select ('00000000-0000-0000-5eed-0000000040' || lpad(n::text, 2, '0'))::uuid, pg_temp.m(n), method::public.income_method,
       cents, case when method = 'bank_link' then 'dev_plaid_5eed_' || n end, now() - make_interval(months => months)
from (values
  (1, 'bank_link', 510000, 10), (2, 'tax_return', 380000, 9), (3, 'bank_link', 620000, 12),
  (4, 'bank_link', 455000, 12), (5, 'self_attested', 230000, 8), (6, 'bank_link', 395000, 11),
  (7, 'tax_return', 470000, 9), (8, 'bank_link', 275000, 8), (9, 'bank_link', 340000, 10),
  (10, 'tax_return', 910000, 15), (12, 'self_attested', 190000, 0), (13, 'bank_link', 430000, 9)
) v (n, method, cents, months);

-- `months` is how many months of dues are already behind each member.
insert into public.subscriptions (id, member_id, formula_version, income_verification_id, monthly_cents, starts_on)
select ('00000000-0000-0000-5eed-0000000050' || right(iv.id::text, 2))::uuid, iv.member_id, 1, iv.id,
       public.subscription_amount(iv.monthly_income_cents, 1),
       date_trunc('month', now() - make_interval(months => v.months))::date
from public.income_verifications iv
join (values (1, 10), (2, 9), (3, 12), (4, 12), (5, 8), (6, 11), (7, 9), (8, 8), (9, 10), (10, 15), (12, 0), (13, 9))
  v (n, months) on iv.member_id = pg_temp.m(v.n);

insert into public.subscription_payments (subscription_id, member_id, period, amount_cents, status, partner_ref, captured_at)
select s.id, s.member_id, p::date, s.monthly_cents, 'captured',
       'dev_pi_5eed_' || right(s.member_id::text, 2) || '_' || to_char(p, 'YYYYMM'), p + interval '2 days'
from public.subscriptions s,
     generate_series(s.starts_on, date_trunc('month', now() - interval '1 month'), interval '1 month') p
where s.id::text like '00000000-0000-0000-5eed-0000000050__' and s.monthly_cents > 0;

perform pg_temp.act_service();
perform public.capture_dues(public.enqueue_dues(s.member_id, date_trunc('month', current_date)::date),
                           'dev_pi_5eed_' || right(s.member_id::text, 2) || '_' || to_char(current_date, 'YYYYMM'))
from public.subscriptions s
where s.id::text like '00000000-0000-0000-5eed-0000000050__' and s.monthly_cents > 0
  and s.member_id <> pg_temp.m(6);
perform public.enqueue_dues(pg_temp.m(6), date_trunc('month', current_date)::date);   -- Hannah's: pending

-- This month's captured dues land in the protection fund's dues account, the
-- only money premiums are paid from.
perform public.post_journal('protection', 'dues', null, 'dev_dues_5eed_' || to_char(current_date, 'YYYYMM'),
  jsonb_build_array(
    jsonb_build_object('code', 'partner_cash', 'amount_cents', -t.total),
    jsonb_build_object('code', 'dues', 'amount_cents', t.total)))
from (select sum(amount_cents) as total from public.subscription_payments
      where member_id::text like '00000000-0000-0000-5eed-%' and status = 'captured'
        and period = date_trunc('month', current_date)::date) t;

insert into public.allocation_preferences (member_id, target, weight_pct) values
  (pg_temp.m(1), 'car_damage', 100),
  (pg_temp.m(3), 'home_help', 60), (pg_temp.m(3), 'highest_score', 40),
  (pg_temp.m(10), 'highest_score', 100);

-- --- payees and covered assets ---------------------------------------------------------------

insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at) values
  (pg_temp.p(1),  'repair_shop',   'Cascade Collision Works (dev)',        'WA', 'verified', 'dev_acct_cascade',    now() - interval '1 year'),
  (pg_temp.p(2),  'repair_shop',   'Saguaro Auto Repair (dev)',            'AZ', 'verified', 'dev_acct_saguaro',    now() - interval '1 year'),
  (pg_temp.p(3),  'contractor',    'Prairie Home Builders (dev)',          'IL', 'verified', 'dev_acct_prairie',    now() - interval '1 year'),
  (pg_temp.p(4),  'contractor',    'Peachtree Roofing and Repair (dev)',   'GA', 'verified', 'dev_acct_peachtree',  now() - interval '1 year'),
  (pg_temp.p(5),  'lender',        'Gulf Coast Mortgage Co-op (dev)',      'FL', 'verified', 'dev_acct_gulfcoast',  now() - interval '1 year'),
  (pg_temp.p(6),  'title_company', 'Buckeye Title and Escrow (dev)',       'OH', 'verified', 'dev_acct_buckeye',    now() - interval '1 year'),
  (pg_temp.p(7),  'lender',        'Bay State Community Lending (dev)',    'MA', 'verified', 'dev_acct_baystate',   now() - interval '1 year'),
  (pg_temp.p(8),  'repair_shop',   'Rio Grande Body Shop (dev)',           'NM', 'verified', 'dev_acct_riogrande',  now() - interval '1 year'),
  (pg_temp.p(9),  'contractor',    'North Star Plumbing and Heating (dev)','MN', 'verified', 'dev_acct_northstar',  now() - interval '1 year'),
  (pg_temp.p(10), 'repair_shop',   'Front Range Auto Body (dev)',          'CO', 'verified', 'dev_acct_frontrange', now() - interval '1 year');
-- A shop the partner is still verifying: pledges wait for it.
insert into public.payees (id, kind, legal_name, region, status) values
  (pg_temp.p(11), 'repair_shop', 'Bayou Auto Works (dev)', 'LA', 'pending');

insert into public.covered_assets (id, member_id, kind, description, value_cents, registered_on, verified_at) values
  (pg_temp.a(1),  pg_temp.m(1),  'vehicle', '2018 Subaru Outback',   1450000, current_date - 240, now() - interval '8 months'),
  (pg_temp.a(2),  pg_temp.m(2),  'vehicle', '2015 Nissan Versa',      520000, current_date - 230, now() - interval '7 months'),
  (pg_temp.a(3),  pg_temp.m(3),  'home',    'Two-flat in Rockford',  21000000, current_date - 300, now() - interval '10 months'),
  (pg_temp.a(4),  pg_temp.m(4),  'home',    'Bungalow in Macon',     16500000, current_date - 300, now() - interval '10 months'),
  (pg_temp.a(5),  pg_temp.m(5),  'vehicle', '2014 Ford F-150',        900000, current_date - 210, now() - interval '7 months'),
  (pg_temp.a(6),  pg_temp.m(6),  'vehicle', '2017 Kia Soul',          780000, current_date - 260, now() - interval '8 months'),
  (pg_temp.a(9),  pg_temp.m(9),  'vehicle', '2013 Honda Odyssey',     610000, current_date - 250, now() - interval '8 months'),
  (pg_temp.a(13), pg_temp.m(13), 'vehicle', '2020 Mazda 3',          1300000, current_date - 220, now() - interval '7 months');

-- Each owner states the vehicle's class and picks a cover plan in the app.
perform pg_temp.act(pg_temp.m(1));  perform public.set_vehicle_class(pg_temp.a(1), 'suv');    perform public.set_my_plan('standard');
perform pg_temp.act(pg_temp.m(2));  perform public.set_vehicle_class(pg_temp.a(2), 'sedan');  perform public.set_my_plan('standard');
perform pg_temp.act(pg_temp.m(5));  perform public.set_vehicle_class(pg_temp.a(5), 'pickup'); perform public.set_my_plan('basic');
perform pg_temp.act(pg_temp.m(6));  perform public.set_vehicle_class(pg_temp.a(6), 'micro_car'); perform public.set_my_plan('basic');
perform pg_temp.act(pg_temp.m(9));  perform public.set_vehicle_class(pg_temp.a(9), 'van');    perform public.set_my_plan('standard');
perform pg_temp.act(pg_temp.m(13)); perform public.set_vehicle_class(pg_temp.a(13), 'sedan'); perform public.set_my_plan('basic');

-- The service pays this month's premiums for two of them out of the dues account.
perform pg_temp.act_service();
perform public.pay_cover_premium(pg_temp.m(1), 'dev_premium_5eed_01_' || to_char(current_date, 'YYYYMM'));
perform public.pay_cover_premium(pg_temp.m(2), 'dev_premium_5eed_02_' || to_char(current_date, 'YYYYMM'));

-- --- requests ------------------------------------------------------------------------------
-- R01 Daniel car_damage     pool    open      on the board, score 88
-- R02 Rosa   car_deductible pool    open      on the board, score 76
-- R03 Kofi   home_repair    pool    open      on the board, half granted by the Home Fund run
-- R04 Mei    home_repair    pool    paid      granted in full by the Home Fund run, contractor paid
-- R05 Tomás  mortgage_gap   people  funded    Ben gives the whole amount; not yet collected
-- R06 Hannah down_payment   people  paid      Ben's 0% loan, three payments made on time
-- R07 Grace  loan_payoff    people  paid      Ben gives and lends; the loan is paused
-- R08 Luis   car_damage     people  paid      Ben's loan, two payments missed
-- R09 Aisha  home_repair    people  paid      Ivy's loan, restructured over a longer term
-- R10 Ivy    car_deductible people  paid      Daniel's loan, forgiven
-- R11 Rosa   car_damage     people  open      Luis offered a loan; Rosa signed, Luis hasn't
-- R12 Omar   car_damage     pool    draft     new member; the shop is still being verified
-- R13 Hannah car_damage     pool    scoring   submitted, waiting for a score
-- R14 Grace  home_repair    people  needs_evidence  scored low; Kofi asked for the quote
-- R15 Tomás  car_damage     pool    in_review a duplicate-photo flag routed it to a person
-- R16 Aisha  car_deductible people  refused   Kofi refused it (and the insurer claim with it); appeal open
-- R17 Luis   home_repair    pool    in_review James refused it; the panel upheld Luis's appeal
-- R18 Ivy    mortgage_gap   people  withdrawn the lender agreed a payment plan
-- R19 Kofi   car_damage     people  expired   open past the window, nobody pledged
-- R20 Mei    loan_payoff    people  open      invites: one open, one revoked, one expired, one accepted
-- R21 Rosa   car_damage     pool    paid      the protection pool and an insurer claim paid the shop
-- R22 Aisha  car_damage     people  paid      Ben's small loan, repaid in full
-- R23 Tomás  car_damage     people  paid      Ben's loan, defaulted to mediation

insert into public.requests (id, member_id, kind, funding, title, description, amount_cents, incident_on, asset_id, payee_id) values
  (pg_temp.r(1),  pg_temp.m(1),  'car_damage', 'pool', 'Sideswiped on the interstate',
   'A truck drifted into my lane. Shop estimate and dashcam stills attached.', 235000, current_date - 6, pg_temp.a(1), pg_temp.p(1)),
  (pg_temp.r(2),  pg_temp.m(2),  'car_deductible', 'pool', 'Deductible after a fender bender',
   'Insurer covers the repair past my deductible; their letter is attached.', 50000, current_date - 11, pg_temp.a(2), pg_temp.p(2)),
  (pg_temp.r(3),  pg_temp.m(3),  'home_repair', 'pool', 'Furnace failed in the cold',
   'The heat exchanger cracked. Two contractor quotes attached.', 480000, current_date - 15, null, pg_temp.p(3)),
  (pg_temp.r(4),  pg_temp.m(4),  'home_repair', 'pool', 'Storm tore off part of the roof',
   'Tarped the same day. Roofer quote and photos attached.', 300000, current_date - 45, null, pg_temp.p(4)),
  (pg_temp.r(5),  pg_temp.m(5),  'mortgage_gap', 'people', 'Two months behind after a layoff',
   'New job starts next month; the credit union confirmed the amount to catch up.', 260000, current_date - 20, null, pg_temp.p(5)),
  (pg_temp.r(6),  pg_temp.m(6),  'down_payment', 'people', 'The last of a down payment',
   'Closing is set; the title company holds the escrow.', 500000, current_date - 150, null, pg_temp.p(6)),
  (pg_temp.r(7),  pg_temp.m(7),  'loan_payoff', 'people', 'Paying off a high-interest car loan',
   'Payoff letter from the lender attached.', 180000, current_date - 100, null, pg_temp.p(7)),
  (pg_temp.r(8),  pg_temp.m(8),  'car_damage', 'people', 'Hail dents across the hood',
   'Body shop estimate attached.', 90000, current_date - 160, null, pg_temp.p(8)),
  (pg_temp.r(9),  pg_temp.m(9),  'home_repair', 'people', 'Water heater flooded the basement',
   'Plumber invoice attached.', 150000, current_date - 90, null, pg_temp.p(9)),
  (pg_temp.r(10), pg_temp.m(13), 'car_deductible', 'people', 'Deductible after a deer strike',
   'Insurer letter states the deductible.', 75000, current_date - 70, pg_temp.a(13), pg_temp.p(10)),
  (pg_temp.r(11), pg_temp.m(2),  'car_damage', 'people', 'Cracked windshield and a dented door',
   'Shop estimate attached.', 110000, current_date - 8, pg_temp.a(2), pg_temp.p(2)),
  (pg_temp.r(12), pg_temp.m(12), 'car_damage', 'pool', 'Backed into a pole',
   'Still getting an estimate.', 70000, current_date - 2, null, pg_temp.p(11)),
  (pg_temp.r(13), pg_temp.m(6),  'car_damage', 'pool', 'Rear window smashed in a break-in',
   'Police report and photos attached.', 130000, current_date - 4, pg_temp.a(6), pg_temp.p(1)),
  (pg_temp.r(14), pg_temp.m(7),  'home_repair', 'people', 'Porch steps rotted through',
   'A photo for now; the carpenter is coming next week.', 65000, current_date - 10, null, pg_temp.p(3)),
  (pg_temp.r(15), pg_temp.m(5),  'car_damage', 'pool', 'Front bumper after a parking-lot collision',
   'Estimate and photos attached.', 200000, current_date - 9, pg_temp.a(5), pg_temp.p(2)),
  (pg_temp.r(16), pg_temp.m(9),  'car_deductible', 'people', 'Deductible for a cracked bumper',
   'Insurer letter attached.', 60000, current_date - 25, pg_temp.a(9), pg_temp.p(10)),
  (pg_temp.r(17), pg_temp.m(8),  'home_repair', 'pool', 'Swamp cooler leaked through the ceiling',
   'Contractor quote and photos attached.', 220000, current_date - 30, null, pg_temp.p(3)),
  (pg_temp.r(18), pg_temp.m(13), 'mortgage_gap', 'people', 'One missed mortgage payment',
   'Medical bills this spring; the lender letter is attached.', 350000, current_date - 40, null, pg_temp.p(7)),
  (pg_temp.r(19), pg_temp.m(3),  'car_damage', 'people', 'Door dinged in a parking garage',
   'Shop estimate attached.', 85000, current_date - 75, null, pg_temp.p(8)),
  (pg_temp.r(20), pg_temp.m(4),  'loan_payoff', 'people', 'Clearing a payday loan',
   'Payoff statement from the lender attached.', 140000, current_date - 14, null, pg_temp.p(5)),
  (pg_temp.r(21), pg_temp.m(2),  'car_damage', 'pool', 'Rear quarter panel after a hit-and-run',
   'Police report, photos and the shop invoice attached.', 165000, current_date - 50, pg_temp.a(2), pg_temp.p(2)),
  (pg_temp.r(22), pg_temp.m(9),  'car_damage', 'people', 'Side mirror knocked off',
   'Shop invoice attached.', 30000, current_date - 130, pg_temp.a(9), pg_temp.p(10)),
  (pg_temp.r(23), pg_temp.m(5),  'car_damage', 'people', 'Tailgate after being backed into',
   'Shop estimate attached.', 50000, current_date - 170, pg_temp.a(5), pg_temp.p(2));

-- Evidence, as the app uploads it: in-app photos plus documents, every copy
-- redacted and confirmed by its owner (Omar's draft is still uploading).
insert into public.evidence (request_id, kind, original_path, redacted_path, sha256, captured_in_app, redaction_status)
select pg_temp.r(e.n), e.kind::public.evidence_kind,
       right(o.owner::text, 12) || '/r' || e.n || '-' || e.kind || '.' || e.ext,
       right(o.owner::text, 12) || '/r' || e.n || '-' || e.kind || '-redacted.' || e.ext,
       md5('5eed-r' || e.n || '-' || e.kind) || md5('5eed-r' || e.n || '-' || e.kind || '-2'),
       e.kind = 'photo', 'confirmed'
from (values
  (1, 'photo', 'jpg'), (1, 'estimate', 'pdf'), (2, 'statement', 'pdf'), (3, 'photo', 'jpg'), (3, 'estimate', 'pdf'),
  (4, 'photo', 'jpg'), (4, 'estimate', 'pdf'), (4, 'invoice', 'pdf'), (5, 'statement', 'pdf'), (5, 'invoice', 'pdf'),
  (6, 'contract', 'pdf'), (6, 'invoice', 'pdf'), (7, 'statement', 'pdf'), (7, 'invoice', 'pdf'),
  (8, 'photo', 'jpg'), (8, 'invoice', 'pdf'), (9, 'photo', 'jpg'), (9, 'invoice', 'pdf'),
  (10, 'statement', 'pdf'), (10, 'invoice', 'pdf'), (11, 'photo', 'jpg'), (11, 'estimate', 'pdf'),
  (13, 'police_report', 'pdf'), (13, 'photo', 'jpg'), (14, 'photo', 'jpg'),
  (15, 'photo', 'jpg'), (15, 'estimate', 'pdf'), (16, 'statement', 'pdf'), (17, 'photo', 'jpg'), (17, 'estimate', 'pdf'),
  (18, 'statement', 'pdf'), (19, 'estimate', 'pdf'), (20, 'statement', 'pdf'),
  (21, 'police_report', 'pdf'), (21, 'photo', 'jpg'), (21, 'invoice', 'pdf'),
  (22, 'photo', 'jpg'), (22, 'invoice', 'pdf'), (23, 'estimate', 'pdf'), (23, 'invoice', 'pdf')
) e (n, kind, ext)
join public.requests q on q.id = pg_temp.r(e.n)
cross join lateral (select q.member_id as owner) o;
insert into public.evidence (request_id, kind, original_path, sha256, captured_in_app, redaction_status)
values (pg_temp.r(12), 'photo', right(pg_temp.m(12)::text, 12) || '/r12-photo.jpg', md5('5eed-r12') || md5('5eed-r12-2'), true, 'pending');

-- A duplicate-photo match on R15, raised before it is scored: a high-severity
-- signal sends the score to a person instead of the board.
perform pg_temp.act_service();
perform public.record_fraud_signal(pg_temp.r(15), 'duplicate_photo', 'high',
  '{"matched": "a photo from an unrelated 2024 listing"}');

-- Every request except the draft is submitted by its owner.

declare
  q public.requests;
begin
  for q in select * from public.requests
           where id::text like '00000000-0000-0000-5eed-0000000010__' and id <> pg_temp.r(12) order by id loop
    perform pg_temp.act(q.member_id);
    perform public.submit_request(q.id);
  end loop;
end;

-- The scoring service scores all but R13, which is still being scored.
perform pg_temp.act_service();
perform public.record_score(pg_temp.r(n), s::smallint, reasons::jsonb, 'dev-scorer', '0.0.1', 'score-v1',
                           md5('5eed-score-' || n) || md5('5eed-score-' || n || '-2'))
from (values
  (1, 88, '["damage in the photos matches the estimate", "dashcam stills dated the day of the incident"]'),
  (2, 76, '["insurer letter states the deductible", "no photos of the damage yet"]'),
  (3, 81, '["two independent quotes agree within 6%", "photos taken in the app"]'),
  (4, 92, '["roofer quote is itemised", "storm date matches the weather record"]'),
  (5, 82, '["lender letter confirms the arrears", "offer letter for the new job"]'),
  (6, 85, '["purchase contract and escrow instructions match"]'),
  (7, 83, '["payoff letter from the lender, dated this month"]'),
  (8, 71, '["estimate from a verified shop", "photos taken outside the app"]'),
  (9, 80, '["plumber invoice dated after the incident", "photos taken in the app"]'),
  (10, 78, '["insurer letter states the deductible"]'),
  (11, 74, '["estimate from a verified shop", "one photo"]'),
  (14, 55, '["one photo", "no quote or invoice yet"]'),
  (15, 84, '["estimate is itemised", "a photo matches an unrelated listing"]'),
  (16, 72, '["insurer letter attached", "the letter names a different vehicle"]'),
  (17, 79, '["contractor quote attached", "photos taken in the app"]'),
  (18, 80, '["lender letter confirms the missed payment"]'),
  (19, 77, '["estimate from a verified shop"]'),
  (20, 75, '["payoff statement from the lender"]'),
  (21, 90, '["police report date matches the photos", "invoice from a verified shop"]'),
  (22, 86, '["invoice from a verified shop", "photos taken in the app"]'),
  (23, 73, '["estimate from a verified shop"]')
) v (n, s, reasons);

-- The redaction step writes each pool request's board summary; the owner
-- confirms it, which is what puts it on the members-only board.
update public.requests q set public_summary = v.summary
from (values
  (1,  'Driver-side doors and mirror after a truck sideswiped the car on the interstate.'),
  (2,  'Deductible for a rear fender repair; the insurer covers the rest.'),
  (3,  'Cracked furnace heat exchanger; no heat in the house.'),
  (4,  'Roof section torn off in a storm; tarped until the repair.'),
  (21, 'Rear quarter panel after a hit-and-run; police report filed.')
) v (n, summary)
where q.id = pg_temp.r(v.n);

declare
  q public.requests;
begin
  for q in select * from public.requests
           where id in (pg_temp.r(1), pg_temp.r(2), pg_temp.r(3), pg_temp.r(4), pg_temp.r(21)) order by id loop
    perform pg_temp.act(q.member_id);
    perform public.confirm_public_summary(q.id);
  end loop;
end;

-- --- reviews and appeals -------------------------------------------------------------------
-- Reviewers only take requests from outside their own state.

-- Kofi (IL) asks Grace (MA) for the carpenter's quote.
perform pg_temp.act(pg_temp.m(3));
perform public.record_review(pg_temp.r(14), 'needs_evidence',
  'One photo of the steps is a start; please add the carpenter''s written quote.');

-- James (NY) refuses Luis's (NM) roof-leak request; Luis appeals and Mei (the
-- panel, GA) upholds it, which sends it back to a person.
perform pg_temp.act('00000000-0000-0000-0000-0000000000a2');
perform public.record_review(pg_temp.r(17), 'refuse',
  'The quote is for a full ceiling replacement, but the photos show one stained panel.');
perform pg_temp.act(pg_temp.m(8));
perform public.file_appeal(pg_temp.r(17),
  'The stain is the part you can see; the contractor opened the ceiling and the joists are wet. Photos of that attached.');
perform pg_temp.act(pg_temp.m(4));
perform public.decide_appeal(a.id, true,
  'The new photos show water damage past the visible stain; the quote fits. Send it back for review.')
from public.appeals a where a.request_id = pg_temp.r(17);

-- Aisha's insurer reports a claim on the van behind R16. Kofi refuses R16
-- (the letter names another vehicle) and, in the same step, denies the claim
-- tied to it: a claim is only denied on a reviewer's recorded refusal. Aisha
-- appeals the refusal; that appeal is still open for the panel.
perform pg_temp.act_service();
perform public.record_claim(pg_temp.r(16), 'dev_claim_5eed_16', 50000, 10000);

begin
  perform pg_temp.act(pg_temp.m(3));
  perform public.record_review(pg_temp.r(16), 'refuse',
    'The insurer letter is for a 2019 Toyota, not the Odyssey on this request.');
  perform public.deny_claim((select id from public.claims where partner_ref = 'dev_claim_5eed_16'),
    'The letter names a different vehicle than the one covered.');
end;
perform pg_temp.act(pg_temp.m(9));
perform public.file_appeal(pg_temp.r(16),
  'The insurer sent the wrong letter; the corrected one for the Odyssey is attached.');

-- Ivy withdraws R18 (the lender agreed a plan); R19 sat open past the window
-- and the service expires it.
perform pg_temp.act(pg_temp.m(13));
perform public.withdraw_request(pg_temp.r(18));
perform pg_temp.act_service();
perform public.expire_request(pg_temp.r(19));

-- --- invites and pledges -------------------------------------------------------------------
-- Each request's owner makes an invite link for the people helping; they accept it.

create function pg_temp.invite(p_request uuid, p_relationship text, p_who uuid) returns void language plpgsql as $$
declare
  v_token text;
begin
  perform pg_temp.act((select member_id from public.requests where id = p_request));
  v_token := public.create_invite(p_request, p_relationship);
  perform pg_temp.act(p_who);
  perform public.accept_invite(v_token);
end $$;

perform pg_temp.invite(pg_temp.r(5),  'friend',   pg_temp.m(10));
perform pg_temp.invite(pg_temp.r(6),  'uncle',    pg_temp.m(10));
perform pg_temp.invite(pg_temp.r(7),  'neighbor', pg_temp.m(10));
perform pg_temp.invite(pg_temp.r(8),  'friend',   pg_temp.m(10));
perform pg_temp.invite(pg_temp.r(9),  'sister',   pg_temp.m(13));
perform pg_temp.invite(pg_temp.r(10), 'friend',   pg_temp.m(1));
perform pg_temp.invite(pg_temp.r(11), 'cousin',   pg_temp.m(8));
perform pg_temp.invite(pg_temp.r(20), 'friend',   pg_temp.m(6));
perform pg_temp.invite(pg_temp.r(22), 'uncle',    pg_temp.m(10));
perform pg_temp.invite(pg_temp.r(23), 'friend',   pg_temp.m(10));

-- R20's other links: one Mei cancelled, one that ran out unused, one still open.
perform pg_temp.act(pg_temp.m(4));
perform public.create_invite(pg_temp.r(20), 'brother');
perform public.create_invite(pg_temp.r(20), 'coworker');
perform public.create_invite(pg_temp.r(20), 'aunt');
perform public.revoke_invite(i.id)
from public.request_invites i
where i.request_id = pg_temp.r(20) and i.relationship = 'brother';
-- Time passing: the coworker's link was made weeks ago and has expired.
update public.request_invites set created_at = now() - interval '30 days', expires_at = now() - interval '2 days'
where request_id = pg_temp.r(20) and relationship = 'coworker';

-- The pledges. A loan pledge opens a 0% family loan the two sides then set up.
perform pg_temp.act(pg_temp.m(10));
perform public.pledge(pg_temp.r(5), 260000, 'gift');           -- R05 fully pledged: funded
perform public.pledge(pg_temp.r(6), 500000, 'loan');
perform public.pledge(pg_temp.r(7), 30000, 'gift');
perform public.pledge(pg_temp.r(7), 150000, 'loan');
perform public.pledge(pg_temp.r(8), 90000, 'loan');
perform public.pledge(pg_temp.r(22), 30000, 'loan');
perform public.pledge(pg_temp.r(23), 50000, 'loan');
perform pg_temp.act(pg_temp.m(13));
perform public.pledge(pg_temp.r(9), 150000, 'loan');
perform pg_temp.act(pg_temp.m(1));
perform public.pledge(pg_temp.r(10), 75000, 'loan');
perform pg_temp.act(pg_temp.m(8));
perform public.pledge(pg_temp.r(11), 60000, 'loan');            -- R11 stays open: $500 still to raise
perform pg_temp.act(pg_temp.m(6));
perform public.pledge(pg_temp.r(20), 25000, 'gift');            -- R20: a first gift
-- A member on the board gives to Daniel's open pool request.
perform pg_temp.act(pg_temp.m(7));
perform public.pledge(pg_temp.r(1), 15000, 'gift');
-- Mei's charity paid part of her payday loan, which she declared.
perform pg_temp.act(pg_temp.m(4));
perform public.record_recovery(pg_temp.r(20), 'charity', 20000, current_date - 5,
  'the church emergency fund paid part of it');

-- The lender sets each loan's terms (payday, pause months a year, what happens
-- if repayment stops); a schedule starting next month; both sides sign.
create function pg_temp.setup_loan(p_request uuid, p_months integer, p_plan public.default_plan,
                                   p_both_sign boolean default true) returns void language plpgsql as $$
declare
  l public.family_loans;
begin
  select * into l from public.family_loans where request_id = p_request;
  perform pg_temp.act(l.lender_id);
  perform public.set_loan_terms(l.id, 15, 3, p_plan);
  perform public.set_loan_schedule(l.id, p_months,
    (date_trunc('month', current_date + interval '1 month') + interval '14 days')::date);
  update public.family_loans set imputed_rate_bps = 0 where id = l.id;   -- the paperwork service
  perform pg_temp.act(l.borrower_id);
  perform public.sign_loan(l.id);
  if p_both_sign then
    perform pg_temp.act(l.lender_id);
    perform public.sign_loan(l.id);
  end if;
end $$;

perform pg_temp.setup_loan(pg_temp.r(6),  10, 'forgive');
perform pg_temp.setup_loan(pg_temp.r(7),   6, 'forgive');
perform pg_temp.setup_loan(pg_temp.r(8),   6, 'forgive');
perform pg_temp.setup_loan(pg_temp.r(9),  10, 'forgive');
perform pg_temp.setup_loan(pg_temp.r(10),  5, 'forgive');
perform pg_temp.setup_loan(pg_temp.r(22),  3, 'forgive');
perform pg_temp.setup_loan(pg_temp.r(23),  4, 'mediate');
perform pg_temp.setup_loan(pg_temp.r(11),  6, 'forgive', false);   -- proposed: Luis hasn't signed

-- --- collection and payout -----------------------------------------------------------------
-- For each fully pledged people request: the partner collects the pledges,
-- pays the payee against its invoice, and the request is paid (which is what
-- makes its loans active).
create function pg_temp.pay_out(p_request uuid, p_ref text) returns void language plpgsql as $$
declare
  q public.requests;
  v_payout uuid;
begin
  perform pg_temp.act_service();
  select * into q from public.requests where id = p_request;
  perform public.capture_contributions(p_request);
  v_payout := public.create_payout(p_request, q.payee_id, q.amount_cents,
    (select id from public.evidence where request_id = p_request and kind = 'invoice'), p_ref);
  perform public.report_payout(v_payout, 'sent');
  perform public.post_journal('people', 'payout', p_request, p_ref,
    jsonb_build_array(
      jsonb_build_object('code', 'partner_cash', 'amount_cents', -q.amount_cents),
      jsonb_build_object('code', 'paid_out', 'amount_cents', q.amount_cents)));
  update public.requests set status = 'paid' where id = p_request;
end $$;

perform pg_temp.pay_out(pg_temp.r(n), 'dev_transfer_5eed_' || n) from unnest(array[6, 7, 8, 9, 10, 22, 23]) n;

-- --- the loans, months on ------------------------------------------------------------------
perform pg_temp.act_service();

-- R06 Hannah <- Ben: three months in, every payment on time.
perform pg_temp.backdate(pg_temp.loan(pg_temp.r(6)), 3);
perform pg_temp.collect(pg_temp.loan(pg_temp.r(6)), s) from generate_series(1, 3) s;

-- R07 Grace <- Ben: two payments made, then Grace pauses for two months.
perform pg_temp.backdate(pg_temp.loan(pg_temp.r(7)), 2);
perform pg_temp.collect(pg_temp.loan(pg_temp.r(7)), s) from generate_series(1, 2) s;
perform pg_temp.act(pg_temp.m(7));
perform public.pause_loan(pg_temp.loan(pg_temp.r(7)), 2, 'Hours cut over the winter');

-- R08 Luis <- Ben: the first payment came in; the next two were missed.
perform pg_temp.act_service();
perform pg_temp.backdate(pg_temp.loan(pg_temp.r(8)), 4);
perform pg_temp.collect(pg_temp.loan(pg_temp.r(8)), 1);

-- R09 Aisha <- Ivy: two payments, then a longer schedule both sides signed.
perform pg_temp.backdate(pg_temp.loan(pg_temp.r(9)), 2);
perform pg_temp.collect(pg_temp.loan(pg_temp.r(9)), s) from generate_series(1, 2) s;
perform pg_temp.act(pg_temp.m(9));
perform public.restructure_loan(pg_temp.loan(pg_temp.r(9)), 16,
  (date_trunc('month', current_date + interval '1 month') + interval '14 days')::date);
perform pg_temp.act(pg_temp.m(13));
perform public.sign_loan_restructure(pg_temp.loan(pg_temp.r(9)));

-- R10 Ivy <- Daniel: one payment, then Daniel forgives the rest as a gift.
perform pg_temp.act_service();
perform pg_temp.backdate(pg_temp.loan(pg_temp.r(10)), 1);
perform pg_temp.collect(pg_temp.loan(pg_temp.r(10)), 1);
perform pg_temp.act(pg_temp.m(1));
perform public.forgive_loan(pg_temp.loan(pg_temp.r(10)),
  public.loan_outstanding_cents(pg_temp.loan(pg_temp.r(10))), extract(year from current_date)::integer);

-- R22 Aisha <- Ben: three small payments, repaid in full.
perform pg_temp.act_service();
perform pg_temp.backdate(pg_temp.loan(pg_temp.r(22)), 3);
perform pg_temp.collect(pg_temp.loan(pg_temp.r(22)), s) from generate_series(1, 3) s;

-- R23 Tomás <- Ben: nothing came in for four months; the plan they agreed at
-- signing (mediation) takes over.
perform pg_temp.backdate(pg_temp.loan(pg_temp.r(23)), 4);
perform public.apply_default_plan(pg_temp.loan(pg_temp.r(23)));

-- --- the pools ------------------------------------------------------------------------------
-- The Home Fund run, through the real allocation: Mei's roof (score band 90)
-- is granted in full, Kofi's furnace (band 80) gets half of what's left.
-- Luis's ceiling (R17) is with a person, so it isn't a candidate.
perform pg_temp.act_service();
perform set_config('seed.home_run', public.run_pool_allocation('home_fund', 600000)::text, false);
-- Both runs are dated in the previous month, which the open-books tests never
-- publish (they publish two and three months back from their own fixtures).
update public.pool_runs set run_at = date_trunc('month', now()) - interval '10 days'
where id = current_setting('seed.home_run')::uuid;
perform public.post_journal('home_fund', 'pool_grant', a.id, null,
  jsonb_build_array(
    jsonb_build_object('code', 'available', 'amount_cents', a.grant_cents),
    jsonb_build_object('code', 'committed', 'amount_cents', -a.grant_cents)))
from public.pool_allocations a where a.run_id = current_setting('seed.home_run')::uuid and a.grant_cents > 0;

-- R04 is covered: the partner collects the grant and pays the roofer.
perform public.capture_contributions(pg_temp.r(4));
perform public.report_payout(
  public.create_payout(pg_temp.r(4), pg_temp.p(4), 300000,
    (select id from public.evidence where request_id = pg_temp.r(4) and kind = 'invoice'), 'dev_transfer_5eed_4'),
  'sent');
perform public.post_journal('home_fund', 'payout', pg_temp.r(4), 'dev_transfer_5eed_4',
  '[{"code":"available","amount_cents":-300000},{"code":"paid_out","amount_cents":300000}]');
update public.requests set status = 'paid' where id = pg_temp.r(4);

-- A protection run that granted Rosa's hit-and-run in full (recorded directly,
-- like b4 above: the real run would also allocate to the open board requests).
-- The insurer's claim on the same damage was paid too.
insert into public.pool_runs (id, fund, available_cents, reserve_cents, allocated_cents, settings, algorithm_version, run_at)
select '00000000-0000-0000-5eed-000000006001', 'protection', 206250, 41250, 165000, to_jsonb(s), 'bands-v1',
       date_trunc('month', now()) - interval '20 days'
from public.fund_settings s where s.fund = 'protection';
insert into public.pool_allocations (id, run_id, request_id, score, band, need_cents, grant_cents)
values ('00000000-0000-0000-5eed-000000006101', '00000000-0000-0000-5eed-000000006001', pg_temp.r(21), 90, 90, 165000, 165000);
insert into public.contributions (request_id, source, amount_cents, status, pool_allocation_id, partner_ref)
values (pg_temp.r(21), 'pool', 165000, 'captured', '00000000-0000-0000-5eed-000000006101', 'dev_pool_capture_5eed_21');
perform public.report_payout(
  public.create_payout(pg_temp.r(21), pg_temp.p(2), 165000,
    (select id from public.evidence where request_id = pg_temp.r(21) and kind = 'invoice'), 'dev_transfer_5eed_21'),
  'sent');
update public.requests set status = 'paid' where id = pg_temp.r(21);
perform public.post_journal('protection', 'pool_grant', '00000000-0000-0000-5eed-000000006101', null,
  '[{"code":"available","amount_cents":165000},{"code":"committed","amount_cents":-165000}]');
perform public.post_journal('protection', 'payout', pg_temp.r(21), 'dev_transfer_5eed_21',
  '[{"code":"available","amount_cents":-165000},{"code":"paid_out","amount_cents":165000}]');
perform public.mark_claim_paid(public.record_claim(pg_temp.r(21), 'dev_claim_5eed_21', 60000, 15000),
                              'dev_claim_paid_5eed_21');


-- --- Home Fund loans --------------------------------------------------------------------------
-- Opened by the lending partner; the borrower sets and signs a monthly
-- schedule; the partner's disbursement makes it active.
perform set_config('seed.hf1', public.create_fund_loan(pg_temp.m(3), 1200000, false, 0, 0, 0, 'monthly', 0, 'dev_hf_5eed_1')::text, false);
perform set_config('seed.hf2', public.create_fund_loan(pg_temp.m(4), 800000, false, 0, 0, 0, 'income', 800, 'dev_hf_5eed_2')::text, false);
perform set_config('seed.hf3', public.create_fund_loan(pg_temp.m(7), 950000, false, 0, 0, 0, 'monthly', 0, 'dev_hf_5eed_3')::text, false);

-- Kofi's: 24 months, signed, disbursed, two payments made.
perform pg_temp.act(pg_temp.m(3));
perform public.set_fund_loan_schedule(current_setting('seed.hf1')::uuid, 24,
  (date_trunc('month', current_date + interval '1 month'))::date);
perform public.sign_fund_loan(current_setting('seed.hf1')::uuid);
perform pg_temp.act_service();
perform public.activate_fund_loan(current_setting('seed.hf1')::uuid);
update public.fund_loan_installments set due_on = (due_on - interval '2 months')::date
where loan_id = current_setting('seed.hf1')::uuid;
perform public.record_fund_loan_payment(current_setting('seed.hf1')::uuid, s, 50000) from generate_series(1, 2) s;

-- Grace's: a 36-month schedule she has set up but not yet signed.
perform pg_temp.act(pg_temp.m(7));
perform public.set_fund_loan_schedule(current_setting('seed.hf3')::uuid, 36,
  (date_trunc('month', current_date + interval '1 month'))::date);


end
$seed$;

select set_config('request.jwt.claims', '', false);
