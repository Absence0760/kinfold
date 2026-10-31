-- Funding from people: invites, pledges, all-or-nothing release, and
-- zero-interest family loans.
--
-- Properties this file pins:
--   * an invite token is returned once, accepted once, never by the owner;
--   * nobody pledges to their own request; gifts need an invite unless the
--     request is on the pool board and the giver is verified; loans need an
--     invite AND a verified lender; a pledge never exceeds what's still needed;
--   * the request flips to funded when fully pledged, and withdrawal, expiry or
--     refusal releases pledges and cancels loans not yet in force;
--   * a loan schedule sums exactly to the principal, signing needs both parties
--     and that exact schedule, installments over the principal fail at commit;
--   * only the lender forgives, and forgiving to zero marks the loan forgiven.
-- Deferred constraint triggers are forced with `set constraints all immediate`
-- inside the asserted statement, since the test transaction never commits.
begin;
select plan(50);

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

select pg_temp.member('00000000-0000-0000-0004-0000000000a1', 'CA');                          -- owen, requester
select pg_temp.member('00000000-0000-0000-0004-0000000000a2', 'CA');                          -- fay, his sister
select pg_temp.member('00000000-0000-0000-0004-0000000000a3', 'NY');                          -- sam, a stranger
select pg_temp.member('00000000-0000-0000-0004-0000000000a4', 'CA', 'pending_verification');  -- uma, invited, unverified

-- b1: people only, 1000.00. b2: pool + on the board. b3: pool, no public summary yet.
select pg_temp.request('00000000-0000-0000-0004-0000000000b1', '00000000-0000-0000-0004-0000000000a1', 'people', 100000);
select pg_temp.request('00000000-0000-0000-0004-0000000000b2', '00000000-0000-0000-0004-0000000000a1', 'pool', 50000);
select pg_temp.request('00000000-0000-0000-0004-0000000000b3', '00000000-0000-0000-0004-0000000000a1', 'pool', 50000);
select pg_temp.move('00000000-0000-0000-0004-0000000000b1', 'scoring', 'open');
select pg_temp.move('00000000-0000-0000-0004-0000000000b2', 'scoring', 'open');
select pg_temp.move('00000000-0000-0000-0004-0000000000b3', 'scoring', 'open');
update public.requests set public_summary = 'Rear bumper after a parking-lot hit', current_score = 88
where id = '00000000-0000-0000-0004-0000000000b2';

-- --- invites -------------------------------------------------------------------
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0004-0000000000a1');
select is(length(set_config('test.token', public.create_invite('00000000-0000-0000-0004-0000000000b1', 'sister'), true)), 48,
  'the owner creates an invite and gets a 48-character token back');
select set_config('test.token2', public.create_invite('00000000-0000-0000-0004-0000000000b1', 'cousin'), true);
select is((select count(*) from public.request_invites where request_id = '00000000-0000-0000-0004-0000000000b1'), 2::bigint,
  'the owner sees their invites');
select throws_ok($$select token_sha256 from public.request_invites$$, '42501', 'permission denied for table request_invites',
  'not even the owner can read the token hash back');
select throws_ok($$select public.accept_invite(current_setting('test.token'))$$,
  '42501', 'you cannot accept an invite to your own request', 'the owner cannot accept their own invite');

select pg_temp.login('00000000-0000-0000-0004-0000000000a2');
select throws_ok($$select public.create_invite('00000000-0000-0000-0004-0000000000b1', 'friend')$$,
  'P0002', 'request not found', 'only the owner creates invites');
select is((select count(*) from public.requests where id = '00000000-0000-0000-0004-0000000000b1'), 0::bigint,
  'before accepting, the request is not visible');
select is(public.accept_invite(current_setting('test.token')), '00000000-0000-0000-0004-0000000000b1'::uuid,
  'an invited person accepts and gets the request id');
select is((select relationship from public.request_supporters
           where request_id = '00000000-0000-0000-0004-0000000000b1' and member_id = '00000000-0000-0000-0004-0000000000a2'),
  'sister', 'accepting adds the supporter with the relationship');
select is((select count(*) from public.requests where id = '00000000-0000-0000-0004-0000000000b1'), 1::bigint,
  'a supporter can read the request they back');

select pg_temp.login('00000000-0000-0000-0004-0000000000a3');
select throws_ok($$select public.accept_invite(current_setting('test.token'))$$,
  'P0002', 'invite not found, used or expired', 'an invite cannot be reused');

select pg_temp.login('00000000-0000-0000-0004-0000000000a4');
select lives_ok($$select public.accept_invite(current_setting('test.token2'))$$, 'a second invite is accepted');

-- --- pledge rules ----------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0004-0000000000a1');
select throws_ok($$select public.pledge('00000000-0000-0000-0004-0000000000b2', 1000, 'gift')$$,
  '42501', 'you cannot pledge to your own request', 'nobody pledges to their own request');

select pg_temp.login('00000000-0000-0000-0004-0000000000a3');
select throws_ok($$select public.pledge('00000000-0000-0000-0004-0000000000b1', 1000, 'gift')$$,
  '42501', 'ask the member for an invite to give to this request', 'a stranger cannot give to a people-only request');
select throws_ok($$select public.pledge('00000000-0000-0000-0004-0000000000b3', 1000, 'gift')$$,
  '42501', 'ask the member for an invite to give to this request',
  'a stranger cannot give to a pool request that is not on the board');
select lives_ok($$select public.pledge('00000000-0000-0000-0004-0000000000b2', 1000, 'gift')$$,
  'a verified stranger gives to a request on the board');
select throws_ok($$select public.pledge('00000000-0000-0000-0004-0000000000b2', 1000, 'loan')$$,
  '42501', 'only invited, verified family and friends can lend', 'a stranger cannot lend');
select throws_ok($$select public.pledge('00000000-0000-0000-0004-0000000000b2', 1000, 'pool')$$,
  '42501', 'pool money is allocated by the pool run, not pledged', 'nobody pledges pool money');

select pg_temp.login('00000000-0000-0000-0004-0000000000a4');
select lives_ok($$select public.pledge('00000000-0000-0000-0004-0000000000b1', 10000, 'gift')$$,
  'an invited person gives even before verifying');
select throws_ok($$select public.pledge('00000000-0000-0000-0004-0000000000b1', 10000, 'loan')$$,
  '42501', 'only invited, verified family and friends can lend', 'an invited but unverified person cannot lend');

select pg_temp.login('00000000-0000-0000-0004-0000000000a2');
select lives_ok($$select public.pledge('00000000-0000-0000-0004-0000000000b1', 40000, 'loan')$$,
  'an invited, verified sister lends');
select is((select (status, principal_cents, borrower_id)::text from public.family_loans
           where request_id = '00000000-0000-0000-0004-0000000000b1'),
  '(proposed,40000,00000000-0000-0000-0004-0000000000a1)', 'the loan pledge creates a proposed loan for the amount');
select throws_ok($$select public.pledge('00000000-0000-0000-0004-0000000000b1', 50001, 'gift')$$,
  '23514', 'pledge must be between 1 and 50000 cents', 'a pledge cannot exceed what is still needed');
select throws_ok($$select public.pledge('00000000-0000-0000-0004-0000000000b1', 0, 'gift')$$,
  '23514', 'pledge must be between 1 and 50000 cents', 'a pledge must be positive');
select lives_ok($$select public.pledge('00000000-0000-0000-0004-0000000000b1', 50000, 'gift')$$,
  'the last pledge fills the request');
select is((select status from public.requests where id = '00000000-0000-0000-0004-0000000000b1'),
  'funded'::public.request_status, 'a fully pledged request flips to funded');
select is(public.request_raised_cents('00000000-0000-0000-0004-0000000000b1'), 100000::bigint,
  'raised equals the amount, never more');
select throws_ok($$select public.pledge('00000000-0000-0000-0004-0000000000b1', 1, 'gift')$$,
  '23514', 'this request is not taking pledges', 'a funded request takes no more pledges');

-- --- all-or-nothing release --------------------------------------------------------
reset role;
-- b4 withdrawn, b5 expired, b6 refused: each has a gift and a loan pledged by fay.
select pg_temp.request(id, '00000000-0000-0000-0004-0000000000a1', 'people', 100000)
from unnest(array['00000000-0000-0000-0004-0000000000b4', '00000000-0000-0000-0004-0000000000b5',
                  '00000000-0000-0000-0004-0000000000b6']::uuid[]) id;
select pg_temp.move(id, 'scoring', 'open')
from unnest(array['00000000-0000-0000-0004-0000000000b4', '00000000-0000-0000-0004-0000000000b5',
                  '00000000-0000-0000-0004-0000000000b6']::uuid[]) id;
insert into public.request_supporters (request_id, member_id, relationship)
select id, '00000000-0000-0000-0004-0000000000a2', 'sister'
from unnest(array['00000000-0000-0000-0004-0000000000b4', '00000000-0000-0000-0004-0000000000b5',
                  '00000000-0000-0000-0004-0000000000b6']::uuid[]) id;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0004-0000000000a2');
select public.pledge(id, 10000, 'gift'), public.pledge(id, 20000, 'loan')
from unnest(array['00000000-0000-0000-0004-0000000000b4', '00000000-0000-0000-0004-0000000000b5',
                  '00000000-0000-0000-0004-0000000000b6']::uuid[]) id;

select pg_temp.login('00000000-0000-0000-0004-0000000000a1');
select public.withdraw_request('00000000-0000-0000-0004-0000000000b4');
reset role;
select pg_temp.move('00000000-0000-0000-0004-0000000000b5', 'expired');
insert into public.reviews (request_id, reviewer_id, decision, reason)
values ('00000000-0000-0000-0004-0000000000b6', '00000000-0000-0000-0004-0000000000a3', 'refuse', 'Estimate is for another car.');
select pg_temp.move('00000000-0000-0000-0004-0000000000b6', 'in_review', 'refused');

select is((select array_agg(distinct status) from public.contributions where request_id = '00000000-0000-0000-0004-0000000000b4'),
  array['released'::public.contribution_status], 'withdrawing releases every pledge');
select is((select array_agg(distinct status) from public.contributions where request_id = '00000000-0000-0000-0004-0000000000b5'),
  array['released'::public.contribution_status], 'expiry releases every pledge');
select is((select array_agg(distinct status) from public.contributions where request_id = '00000000-0000-0000-0004-0000000000b6'),
  array['released'::public.contribution_status], 'refusal releases every pledge');
select is((select array_agg(status order by request_id) from public.family_loans
           where request_id in ('00000000-0000-0000-0004-0000000000b4', '00000000-0000-0000-0004-0000000000b5',
                                '00000000-0000-0000-0004-0000000000b6')),
  array['cancelled', 'cancelled', 'cancelled']::public.loan_status[], 'closing a request cancels its unsigned loans');
select is(public.request_raised_cents('00000000-0000-0000-0004-0000000000b4'), 0::bigint,
  'released pledges no longer count as raised');

-- --- family loans --------------------------------------------------------------------
-- l1: owen borrows 1000.00 from fay. l2: no schedule. l3: small loan for over-forgiveness.
insert into public.family_loans (id, borrower_id, lender_id, principal_cents) values
  ('00000000-0000-0000-0004-0000000000d1', '00000000-0000-0000-0004-0000000000a1', '00000000-0000-0000-0004-0000000000a2', 100000),
  ('00000000-0000-0000-0004-0000000000d2', '00000000-0000-0000-0004-0000000000a1', '00000000-0000-0000-0004-0000000000a2', 100000),
  ('00000000-0000-0000-0004-0000000000d3', '00000000-0000-0000-0004-0000000000a1', '00000000-0000-0000-0004-0000000000a2', 1000);

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0004-0000000000a3');
select throws_ok($$select public.set_loan_schedule('00000000-0000-0000-0004-0000000000d1', 3, '2026-12-01')$$,
  'P0002', 'loan not found', 'only the borrower or lender sets a schedule');

select pg_temp.login('00000000-0000-0000-0004-0000000000a1');
select lives_ok($$select public.set_loan_schedule('00000000-0000-0000-0004-0000000000d1', 3, '2026-12-01')$$,
  'the borrower sets a three-month schedule');
select results_eq(
  $$select seq, due_on, amount_cents from public.loan_installments
    where loan_id = '00000000-0000-0000-0004-0000000000d1' order by seq$$,
  $$values (1, '2026-12-01'::date, 33333::bigint), (2, '2027-01-01', 33333), (3, '2027-02-01', 33334)$$,
  'installments are equal monthly, the last takes the remainder');
select throws_ok($$select public.set_loan_schedule('00000000-0000-0000-0004-0000000000d1', 0, '2026-12-01')$$,
  '23514', 'schedule must be 1 to 480 months', 'a schedule needs at least one month');
select throws_ok($$select public.set_loan_schedule('00000000-0000-0000-0004-0000000000d3', 1001, '2026-12-01')$$,
  '23514', 'schedule must be 1 to 480 months', 'a schedule has at most 480 months');
select throws_ok($$select public.sign_loan('00000000-0000-0000-0004-0000000000d2')$$,
  '23514', 'set a repayment schedule that adds up to the amount lent', 'a loan cannot be signed without a schedule');
select is(public.sign_loan('00000000-0000-0000-0004-0000000000d1'), 'proposed'::public.loan_status,
  'one signature leaves the loan proposed');

select pg_temp.login('00000000-0000-0000-0004-0000000000a2');
select is(public.sign_loan('00000000-0000-0000-0004-0000000000d1'), 'signed'::public.loan_status,
  'the second signature puts the loan in force');
select throws_ok($$select public.set_loan_schedule('00000000-0000-0000-0004-0000000000d1', 6, '2026-12-01')$$,
  '23514', 'a signed loan''s schedule can only change by agreement (restructure)', 'a signed schedule is fixed');

reset role;
select throws_ok(
  $$insert into public.loan_installments (loan_id, seq, due_on, amount_cents)
    values ('00000000-0000-0000-0004-0000000000d1', 4, '2027-03-01', 1);
    set constraints all immediate$$,
  '23514', 'installments (100001) exceed the principal (100000): Kinfold loans carry no interest',
  'installments over the principal fail at commit');
select throws_ok(
  $$update public.loan_installments set amount_cents = amount_cents + 1
    where loan_id = '00000000-0000-0000-0004-0000000000d1' and seq = 3;
    set constraints all immediate$$,
  '23514', 'installments (100001) exceed the principal (100000): Kinfold loans carry no interest',
  'raising an installment over the principal fails at commit');

-- Unsigned loan d2 can't be forgiven; d3 needs to be in force for the over-forgiveness check.
update public.family_loans set status = 'signed', borrower_signed_at = now(), lender_signed_at = now()
where id = '00000000-0000-0000-0004-0000000000d3';

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0004-0000000000a1');
select throws_ok($$select public.forgive_loan('00000000-0000-0000-0004-0000000000d1', 1000, 2026)$$,
  '42501', 'only the lender can forgive an active loan', 'the borrower cannot forgive their own loan');

select pg_temp.login('00000000-0000-0000-0004-0000000000a2');
select throws_ok($$select public.forgive_loan('00000000-0000-0000-0004-0000000000d2', 1000, 2026)$$,
  '42501', 'only the lender can forgive an active loan', 'a loan not yet in force cannot be forgiven');
select lives_ok($$select public.forgive_loan('00000000-0000-0000-0004-0000000000d1', 60000, 2026)$$,
  'the lender forgives part of the balance');
select is((select (status, public.loan_outstanding_cents(id))::text from public.family_loans
           where id = '00000000-0000-0000-0004-0000000000d1'), '(signed,40000)',
  'part-forgiveness reduces the balance and keeps the loan in force');
select lives_ok($$select public.forgive_loan('00000000-0000-0000-0004-0000000000d1', 40000, 2027)$$,
  'the lender forgives the rest');
select is((select status from public.family_loans where id = '00000000-0000-0000-0004-0000000000d1'),
  'forgiven'::public.loan_status, 'forgiving to zero marks the loan forgiven');
select throws_ok(
  $$select public.forgive_loan('00000000-0000-0000-0004-0000000000d3', 2000, 2026);
    set constraints all immediate$$,
  '23514', 'payments and forgiveness exceed the principal', 'forgiving more than is owed fails at commit');

reset role;
select * from finish();
rollback;
