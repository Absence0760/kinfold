-- The supporter's view (20261102240000_support_view.sql).
--
-- Properties this file pins:
--   * a supporter reads their request through `support_requests` and sees
--     exactly the ask: kind, funding, title, story, amount, status, incident
--     date — and the payee's id only once they're verified;
--   * a supporter can no longer read the requests ROW: the whole-row policy
--     is dropped, so `current_score` and friends stay the owner's and the
--     console's;
--   * the owner still reads their own row;
--   * a stranger reads nothing from the view.
begin;
select plan(9);

-- --- fixtures ------------------------------------------------------------------
-- Temporary helpers, gone at rollback. They run as postgres (the owner).

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

-- An open people-funded request with a payee in a given verification state.
create function pg_temp.request_in(p_request uuid, p_member uuid, p_payee uuid,
                                   p_payee_status public.payee_status)
returns void language sql as $$
begin
  insert into public.payees (id, kind, legal_name, region, status, partner_account_ref)
  values (p_payee, 'repair_shop', 'Shop', 'CA', p_payee_status, 'acct_' || right(p_payee::text, 2));
  insert into public.requests (id, member_id, payee_id, kind, funding, title, amount_cents,
                               incident_on, status, description, public_summary,
                               public_summary_confirmed_at, current_score, submitted_at)
  values (p_request, p_member, p_payee, 'car_damage', 'people', 'Bumper needs fixing', 123456,
          current_date - 3, 'open', 'A shopping trolley clipped my bumper last Tuesday.',
          'Rear bumper after a parking-lot hit', now(), 87::smallint, now());
end $$;

-- A supporter standing in for someone who accepted an invite.
create function pg_temp.support(p_request uuid, p_member uuid) returns void language sql as $$
  insert into public.request_supporters (request_id, member_id, relationship)
  values (p_request, p_member, 'family');
$$;

select pg_temp.member('00000000-0000-0000-0009-0000000000a1');  -- owner
select pg_temp.member('00000000-0000-0000-0009-0000000000a2');  -- supporter
select pg_temp.member('00000000-0000-0000-0009-0000000000a3');  -- stranger
-- R1 with a verified payee.
select pg_temp.request_in('00000000-0000-0000-0009-0000000000b1', '00000000-0000-0000-0009-0000000000a1',
                          '00000000-0000-0000-0009-0000000000c1', 'verified');
-- R2 with a payee still pending.
select pg_temp.request_in('00000000-0000-0000-0009-0000000000b2', '00000000-0000-0000-0009-0000000000a1',
                          '00000000-0000-0000-0009-0000000000c2', 'pending');
select pg_temp.support('00000000-0000-0000-0009-0000000000b1', '00000000-0000-0000-0009-0000000000a2');
select pg_temp.support('00000000-0000-0000-0009-0000000000b2', '00000000-0000-0000-0009-0000000000a2');

-- --- the supporter sees exactly the ask --------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0009-0000000000a2');
select is((select count(*) from public.support_requests), 2::bigint,
  'the supporter reads both requests they back, and nothing else');
select is((select funding from public.support_requests
           where id = '00000000-0000-0000-0009-0000000000b1'),
  'people', 'the view carries the fields the supporter's page uses');
select is((select count(*) from public.support_requests
    where id = '00000000-0000-0000-0009-0000000000b1'
      and amount_cents = 123456 and status = 'open'
      and incident_on = current_date - 3),
  1, 'ask, status and incident date come through as they are');
select isnull((select payee_id from public.support_requests
               where id = '00000000-0000-0000-0009-0000000000b2'),
  'an unverified payee stays unlinked for a supporter');
select isnot((select payee_id from public.support_requests
              where id = '00000000-0000-0000-0009-0000000000b1'),
  NULL, 'a verified payee's id comes through for the page to read the name');

-- --- the whole row is no longer the supporter's -------------------------------

select is((select count(*) from public.requests where id = '00000000-0000-0000-0009-0000000000b1'),
  0::bigint, 'a supporter can't read the request row: the whole-row policy is gone');

-- --- the owner still reads their own row --------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0009-0000000000a1');
select is((select count(*) from public.requests where id = '00000000-0000-0000-0009-0000000000b1'),
  1::bigint, 'the owner still reads their own request');

-- --- a stranger reads nothing --------------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0009-0000000000a3');
select is((select count(*) from public.support_requests), 0::bigint,
  'a stranger reads nothing from the view');
select is((select count(*) from public.requests), 0::bigint, 'and nothing from the table either');
