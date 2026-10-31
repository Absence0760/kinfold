-- Board and open-books privacy (20261030120600_board_privacy.sql).
--
-- Properties this file pins:
--   * a request reaches the board only once its member has confirmed the public
--     summary; only the member can confirm; changing the summary clears it;
--   * the board shows the exact amount only while a request is open, otherwise
--     an amount band; a 10-point score band; the month; the Census division for
--     a small state; closed requests leave after 12 months, open ones stay;
--   * a member reads only their own pool allocations;
--   * nobody but the service reads pool runs;
--   * raised-so-far shows to strangers only while a request is open;
--   * publish_open_books is service-only, publishes a month a week after it
--     ends, hides 1 to 10 requests, any total one request dominates and the
--     short-run count of a small month, rounds dollars to $1,000, and publishes
--     a month once; anyone reads the result and only the service writes it.
begin;
select plan(42);

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

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

-- A request already in a given state, inserted with triggers off: these tests
-- are about what the board and the open books show, not how a request got
-- there (requests_test and service_paths_test pin that).
create function pg_temp.request_in(p_id uuid, p_member uuid, p_status public.request_status,
                                   p_amount bigint, p_score smallint,
                                   p_kind public.request_kind default 'car_damage',
                                   p_submitted timestamptz default now(),
                                   p_confirmed boolean default true)
returns uuid language plpgsql as $$
begin
  set local session_replication_role = replica;
  insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                               status, public_summary, public_summary_confirmed_at, current_score, submitted_at)
  values (p_id, p_member, p_kind, 'pool', 'Test request', p_amount, current_date - 5,
          p_status, 'Rear bumper after a parking-lot hit',
          case when p_confirmed then now() end, p_score, p_submitted);
  set local session_replication_role = origin;
  return p_id;
end $$;

-- A sent payout to the shop, made at p_at.
create function pg_temp.sent_payout(p_request uuid, p_amount bigint, p_at timestamptz)
returns void language plpgsql as $$
begin
  set local session_replication_role = replica;
  insert into public.payouts (request_id, payee_id, amount_cents, invoice_evidence_id, status, created_at, sent_at)
  values (p_request, '00000000-0000-0000-000c-0000000000c1', p_amount,
          '00000000-0000-0000-000c-0000000000e1', 'sent', p_at, p_at);
  set local session_replication_role = origin;
end $$;

select pg_temp.member('00000000-0000-0000-000c-0000000000a1', 'NY');  -- nia, requester
select pg_temp.member('00000000-0000-0000-000c-0000000000a2', 'CA');  -- cal, another member
insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at)
values ('00000000-0000-0000-000c-0000000000c1', 'repair_shop', 'Shop', 'NY', 'verified', 'acct_c1', now());

-- b1: open, summary not yet confirmed. b2: paid. b3: paid 13 months ago. b4: open, submitted 13 months ago.
select pg_temp.request_in('00000000-0000-0000-000c-0000000000b1', '00000000-0000-0000-000c-0000000000a1',
                          'open', 123456, 87::smallint, p_confirmed => false);
select pg_temp.request_in('00000000-0000-0000-000c-0000000000b2', '00000000-0000-0000-000c-0000000000a1',
                          'paid', 300000, 92::smallint);
select pg_temp.request_in('00000000-0000-0000-000c-0000000000b3', '00000000-0000-0000-000c-0000000000a1',
                          'paid', 300000, 92::smallint, p_submitted => now() - interval '13 months');
select pg_temp.request_in('00000000-0000-0000-000c-0000000000b4', '00000000-0000-0000-000c-0000000000a1',
                          'open', 50000, 75::smallint, p_submitted => now() - interval '13 months');
insert into public.evidence (id, request_id, kind, original_path, redacted_path, sha256, redaction_status)
values ('00000000-0000-0000-000c-0000000000e1', '00000000-0000-0000-000c-0000000000b2', 'invoice',
        'x/original.pdf', 'x/redacted.pdf', repeat('a', 64), 'confirmed');

-- --- the member confirms the summary ---------------------------------------------
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000c-0000000000a2');
select is((select count(*) from public.board_requests where id = '00000000-0000-0000-000c-0000000000b1'), 0::bigint,
  'a request whose summary the member has not confirmed is not on the board');
select throws_ok($$select public.confirm_public_summary('00000000-0000-0000-000c-0000000000b1')$$,
  'P0002', 'request not found', 'another member cannot confirm the summary');

select pg_temp.login('00000000-0000-0000-000c-0000000000a1');
select lives_ok($$select public.confirm_public_summary('00000000-0000-0000-000c-0000000000b1')$$,
  'the member confirms their own summary');

select pg_temp.login('00000000-0000-0000-000c-0000000000a2');
select is((select count(*) from public.board_requests where id = '00000000-0000-0000-000c-0000000000b1'), 1::bigint,
  'once confirmed, the request is on the board');

-- --- what the board shows ----------------------------------------------------------
select is((select (amount_cents, amount_band_min_cents, amount_band_max_cents, score_band)::text
           from public.board_requests where id = '00000000-0000-0000-000c-0000000000b1'),
  '(123456,100000,250000,80)',
  'an open request shows its exact ask, its amount band and a 10-point score band');
select is((select (amount_cents, amount_band_min_cents, amount_band_max_cents)::text
           from public.board_requests where id = '00000000-0000-0000-000c-0000000000b2'),
  '(,250000,500000)', 'a paid request shows only its amount band');
select is((select area from public.board_requests where id = '00000000-0000-0000-000c-0000000000b1'),
  'Middle Atlantic', 'a state with under 1,000 active members shows as its Census division');
select is((select month_of from public.board_requests where id = '00000000-0000-0000-000c-0000000000b1'),
  date_trunc('month', now())::date, 'the board shows the month, not the week or day');
select is((select count(*) from public.board_requests where id = '00000000-0000-0000-000c-0000000000b3'), 0::bigint,
  'a request closed more than 12 months ago has left the board');
select is((select count(*) from public.board_requests where id = '00000000-0000-0000-000c-0000000000b4'), 1::bigint,
  'a request still open stays on the board however old');
select is(public.request_raised_cents('00000000-0000-0000-000c-0000000000b3'), null::bigint,
  'raised so far is hidden once a request has left the board');
select is(public.request_raised_cents('00000000-0000-0000-000c-0000000000b2'), null::bigint,
  'raised so far is hidden from strangers once a request on the board is paid');
select is(public.request_raised_cents('00000000-0000-0000-000c-0000000000b4'), 0::bigint,
  'raised so far shows to members while a request on the board is open');

-- Band edges, a big state, and the fallback division.
reset role;
select pg_temp.request_in(('00000000-0000-0000-000c-0000000001' || lpad(i::text, 2, '0'))::uuid,
                          '00000000-0000-0000-000c-0000000000a1', 'paid', amount, 70::smallint)
from (values (1, 49999::bigint), (2, 50000::bigint), (3, 10000000::bigint)) v (i, amount);
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                        created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin,
                        confirmation_token, recovery_token, email_change_token_new, email_change)
select '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', id::text || '@test.invalid',
       'x', now(), now(), now(), '{"provider":"email"}', '{}', false, '', '', '', ''
from (select gen_random_uuid() as id from generate_series(1, 1000)) g;
insert into public.members (id, display_name, region, status)
select id, 'Texan', 'TX', 'active' from auth.users where email like '%@test.invalid'
  and id not in (select id from public.members);
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000c-0000000000a2');
select is((select array_agg((amount_band_min_cents, amount_band_max_cents)::text order by id) from public.board_requests
           where id::text like '00000000-0000-0000-000c-0000000001%'),
  array['(0,50000)', '(50000,100000)', '(10000000,)'],
  'amount bands: a band''s lower edge belongs to it, and the top band is open');
select is(public.board_area('TX'), 'TX', 'a state with 1,000 or more active members shows as itself');
select is(public.board_area('PR'), 'Other', 'a region outside the divisions shows as Other');
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok($$select public.board_area('TX')$$, '42501', null, 'anon cannot ask how big a state is');
reset role;
update public.requests set public_summary = public_summary, title = 'Renamed'
where id = '00000000-0000-0000-000c-0000000000b2';
select ok((select public_summary_confirmed_at is not null from public.requests
           where id = '00000000-0000-0000-000c-0000000000b2'),
  'an update that leaves the summary unchanged keeps the confirmation');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000c-0000000000a2');

-- Changing the summary takes the request off the board until it is confirmed again.
reset role;
update public.requests set public_summary = 'Rear bumper and tail light'
where id = '00000000-0000-0000-000c-0000000000b1';
select is((select public_summary_confirmed_at from public.requests where id = '00000000-0000-0000-000c-0000000000b1'),
  null::timestamptz, 'changing the summary clears the confirmation');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000c-0000000000a2');
select is((select count(*) from public.board_requests where id = '00000000-0000-0000-000c-0000000000b1'), 0::bigint,
  'a changed summary is off the board until confirmed again');
select throws_ok($$select public.pledge('00000000-0000-0000-000c-0000000000b1', 1000, 'gift')$$,
  '42501', 'ask the member for an invite to give to this request',
  'a stranger cannot give to a request whose summary is not confirmed');

-- --- pool allocations and pool runs ------------------------------------------------------
reset role;
insert into public.pool_runs (id, fund, available_cents, reserve_cents, allocated_cents, settings, algorithm_version, run_at)
values ('00000000-0000-0000-000c-0000000000f1', 'protection', 1000000, 200049, 300000, '{}', 'test',
        date_trunc('month', now()) - interval '2 months' + interval '3 days');
insert into public.pool_allocations (run_id, request_id, score, band, need_cents, grant_cents)
values ('00000000-0000-0000-000c-0000000000f1', '00000000-0000-0000-000c-0000000000b2', 92, 90, 400000, 300000);

set local role authenticated;
select is((select count(*) from public.pool_allocations), 0::bigint,
  'a member cannot read another member''s pool allocation');
select pg_temp.login('00000000-0000-0000-000c-0000000000a1');
select is((select count(*) from public.pool_allocations), 1::bigint,
  'a member reads their own pool allocation');
select throws_ok('select count(*) from public.pool_runs', '42501', 'permission denied for table pool_runs',
  'a member cannot read pool runs');

-- --- publishing the open books ------------------------------------------------------------
select throws_ok($$select public.publish_open_books(date_trunc('month', now() - interval '2 months')::date)$$,
  '42501', 'permission denied for function publish_open_books', 'a member cannot publish the open books');

-- Two months ago: protection paid 3 requests (b2 and two more), home_fund paid 12.
-- Three months ago: home_fund paid 11, one of them most of the money.
reset role;
select pg_temp.sent_payout('00000000-0000-0000-000c-0000000000b2', 300000,
                           date_trunc('month', now()) - interval '2 months' + interval '4 days');
select pg_temp.sent_payout(pg_temp.request_in(gen_random_uuid(), '00000000-0000-0000-000c-0000000000a1',
                             'paid', 100000, 90::smallint), 100000,
                           date_trunc('month', now()) - interval '2 months' + interval '5 days')
from generate_series(1, 2);
select pg_temp.sent_payout(pg_temp.request_in(gen_random_uuid(), '00000000-0000-0000-000c-0000000000a1',
                             'paid', 1234567, 90::smallint, 'home_repair'), 1234567,
                           date_trunc('month', now()) - interval '2 months' + interval '6 days')
from generate_series(1, 12);
select pg_temp.sent_payout(pg_temp.request_in(gen_random_uuid(), '00000000-0000-0000-000c-0000000000a1',
                             'paid', amount, 90::smallint, 'home_repair'), amount,
                           date_trunc('month', now()) - interval '3 months' + interval '6 days')
from (select case when i = 1 then 10000000 else 100000 end as amount from generate_series(1, 11) i) a;

set local role service_role;
select pg_temp.as_service();
select throws_ok($$select public.publish_open_books(date_trunc('month', now())::date)$$,
  '23514', 'a month is published a week after it ends', 'the current month cannot be published');
select throws_ok($$select public.publish_open_books((date_trunc('month', now()) - interval '20 days')::date)$$,
  '22023', 'p_month must be the first day of a month', 'only whole months are published');
select lives_ok($$select public.publish_open_books(date_trunc('month', now() - interval '2 months')::date)$$,
  'the service publishes a month that ended over a week ago');
select lives_ok($$select public.publish_open_books(date_trunc('month', now() - interval '3 months')::date)$$,
  'the service publishes the month before');
select throws_ok($$select public.publish_open_books(date_trunc('month', now() - interval '2 months')::date)$$,
  '23505', null, 'a month is published once');

reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select is((select (requests_paid, paid_out_cents)::text from public.open_books
           where fund = 'protection' and month = date_trunc('month', now() - interval '2 months')::date),
  '(,)', '3 requests paid: the count shows as 10 or fewer and the total is hidden');
select is((select (requests_paid, paid_out_cents)::text from public.open_books
           where fund = 'home_fund' and month = date_trunc('month', now() - interval '2 months')::date),
  '(12,14800000)', '12 requests paid: the count shows and the total is rounded to $1,000');
select is((select (requests_paid, paid_out_cents)::text from public.open_books
           where fund = 'home_fund' and month = date_trunc('month', now() - interval '3 months')::date),
  '(11,)', 'a total one request makes up half of is hidden');
select is((select (pool_runs, pool_runs_short, allocated_cents, reserve_cents)::text from public.open_books
           where fund = 'protection' and month = date_trunc('month', now() - interval '2 months')::date),
  '(1,,,200000)', 'a one-request month shows its run count but hides how many fell short and the grant; the reserve is rounded');
select throws_ok('select count(*) from public.pool_runs', '42501', 'permission denied for table pool_runs',
  'anon cannot read pool runs');
select throws_ok($$insert into public.open_books (fund, month, pool_runs, pool_runs_short) values ('protection', '2020-01-01', 0, 0)$$,
  '42501', 'permission denied for table open_books', 'anon cannot write the open books');
reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000c-0000000000a1');
select throws_ok($$update public.open_books set requests_paid = 99$$,
  '42501', 'permission denied for table open_books', 'a member cannot change the open books');
select is(public.request_raised_cents('00000000-0000-0000-000c-0000000000b2'), 0::bigint,
  'the member still sees what their own paid request raised');
reset role;
select is(private.round_thousand(150000), 200000::bigint, 'rounding: $1,500 rounds to $2,000');
select is(private.round_thousand(149999), 100000::bigint, 'rounding: just under $1,500 rounds to $1,000');
select is(private.census_division('VT'), 'New England', 'Vermont is in New England');
select throws_ok('select count(*) from public.public_stats', '42P01', null,
  'the live stats view is gone');

reset role;
select * from finish();
rollback;
