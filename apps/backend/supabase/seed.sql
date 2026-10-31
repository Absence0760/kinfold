-- Local-stack seed. Runs on `supabase db reset`.
--
-- LOCAL-ONLY DEV DATA. Everything here is throwaway: fictional people, shops and
-- amounts, so the app has something to show on a laptop. The dev password grants
-- access to nothing outside a container on this machine, which is why it is
-- committed (see CLAUDE.md, "Local-dev env is committed; real secrets never are").
-- Never run this against a real project.
--
-- Dev logins (password for all: testtest):
--   maria@test.com  member, CA: a draft, a funded request with a family loan
--   sam@test.com    member, CA: maria's brother and lender; an open request on the board
--   james@test.com  member + reviewer, NY (outside CA, so he can review maria and sam)
--   priya@test.com  member + appeal panel, TX: a request already paid from the pool
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
  ('00000000-0000-0000-0000-0000000000c3', 'repair_shop', 'Lone Star Collision (dev)',        'TX', 'verified', 'dev_acct_lonestar', now() - interval '1 year');

insert into public.covered_assets (id, member_id, kind, description, value_cents, registered_on, verified_at) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a1', 'vehicle', '2016 Honda Fit',    850000,  current_date - 180, now() - interval '6 months'),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000a4', 'vehicle', '2012 Toyota Camry', 600000,  current_date - 180, now() - interval '6 months'),
  ('00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000a3', 'vehicle', '2019 Ford Focus',   1100000, current_date - 180, now() - interval '6 months');

-- --- requests ---------------------------------------------------------------------------
-- b1 maria  draft          home_repair, evidence still being redacted
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
   '00000000-0000-0000-0000-0000000000a1/b1-ceiling.jpg', null, repeat('1', 64), true, 'pending'),
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
  '[{"code":"committed","amount_cents":72000},{"code":"paid_out","amount_cents":-72000}]');

select set_config('request.jwt.claims', '', false);
