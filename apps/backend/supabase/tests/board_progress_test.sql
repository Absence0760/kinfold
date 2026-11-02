-- What the board view now says about a request's money
-- (20261102200000_board_progress.sql).
--
-- Properties this file pins:
--   * an open request on the board carries its raised-so-far, the same figure
--     pledge caps against, so the page does not have to ask per card;
--   * a finished request's raised-so-far is not on the view: the ask is no
--     longer being funded, and the old followup only asked for open ones;
--   * taking_pledges answers whether a pledge would be accepted now: open and
--     the payee verified, so the board's copy can say so up front instead of
--     refusing the first gift;
--   * giving updates the board figure on the next read.
begin;
select plan(8);

-- --- fixtures ------------------------------------------------------------------
-- Temporary helpers, gone at rollback. They run as postgres (the owner); clients
-- can't create members or drop requests into a state.

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

-- A request already on the board, inserted with triggers off: these tests are
-- about what the view answers, not how a request got there.
create function pg_temp.request_in(p_id uuid, p_member uuid, p_status public.request_status,
                                   p_amount bigint, p_score smallint, p_payee uuid)
returns uuid language plpgsql as $$
begin
  set local session_replication_role = replica;
  insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                               status, public_summary, public_summary_confirmed_at, current_score,
                               submitted_at, payee_id)
  values (p_id, p_member, 'car_damage', 'pool', 'Test request', p_amount, current_date - 5,
          p_status, 'Rear bumper after a parking-lot hit', now(), p_score, now(), p_payee);
  set local session_replication_role = origin;
  return p_id;
end $$;

-- A pledge already on a request, made by someone else.
create function pg_temp.pledge_of(p_request uuid, p_member uuid, p_amount bigint)
returns void language sql as $$
  insert into public.contributions (request_id, contributor_id, source, amount_cents, status)
  values (p_request, p_member, 'gift', p_amount, 'pledged');
$$;

select pg_temp.member('00000000-0000-0000-000e-0000000000a1');                        -- owner
select pg_temp.member('00000000-0000-0000-000e-0000000000a2');                        -- board reader
insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at)
values ('00000000-0000-0000-000e-0000000000c1', 'repair_shop', 'Shop', 'CA', 'verified', 'acct_c1', now()),
       ('00000000-0000-0000-000e-0000000000c2', 'repair_shop', 'Shop still checked', 'CA', 'pending', null, null);

-- b1: open, payee verified, 40000 pledged. b2: open, payee still being checked.
-- b3: paid (money already collected).
select pg_temp.request_in('00000000-0000-0000-000e-0000000000b1', '00000000-0000-0000-000e-0000000000a1',
                          'open', 123456, 87::smallint, '00000000-0000-0000-000e-0000000000c1');
select pg_temp.request_in('00000000-0000-0000-000e-0000000000b2', '00000000-0000-0000-000e-0000000000a1',
                          'open', 50000, 80::smallint, '00000000-0000-0000-000e-0000000000c2');
select pg_temp.request_in('00000000-0000-0000-000e-0000000000b3', '00000000-0000-0000-000e-0000000000a1',
                          'paid', 300000, 92::smallint, '00000000-0000-0000-000e-0000000000c1');
select pg_temp.pledge_of('00000000-0000-0000-000e-0000000000b1', '00000000-0000-0000-000e-0000000000a2', 40000);

-- --- the open request answers for the page ---------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-000e-0000000000a2');
select is((select raised_cents from public.board_requests
           where id = '00000000-0000-0000-000e-0000000000b1'),
  40000::bigint, 'an open request on the board carries its raised-so-far');
select is((select taking_pledges from public.board_requests
           where id = '00000000-0000-0000-000e-0000000000b1'),
  true, 'an open request with a verified payee is taking pledges');
select is((select taking_pledges from public.board_requests
           where id = '00000000-0000-0000-000e-0000000000b2'),
  false, 'an open request whose payee is still being checked is not taking pledges');
select throws_ok($$select public.pledge('00000000-0000-0000-000e-0000000000b2', 1000::bigint, 'gift')$$,
  '23514', 'pledges open once the request''s payee is verified',
  'the answer the board gives is the rule pledge applies');

-- Giving on b1 moves the figure on the next read.
select lives_ok($$select public.pledge('00000000-0000-0000-000e-0000000000b1', 2500::bigint, 'gift')$$,
  'a gift to an open request with a verified payee goes through');
select is((select raised_cents from public.board_requests
           where id = '00000000-0000-0000-000e-0000000000b1'),
  42500::bigint, 'a new pledge shows up in the board figure right away');

-- --- a finished request keeps its money figures off the board --------------------

select isnull((select raised_cents from public.board_requests
               where id = '00000000-0000-0000-000e-0000000000b3'),
  'a paid request on the board shares no raised-so-far');
select is((select taking_pledges from public.board_requests
           where id = '00000000-0000-0000-000e-0000000000b3'),
  false, 'a paid request is not taking pledges');
