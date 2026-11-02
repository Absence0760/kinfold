-- Invite lifecycle: preview before the click, revoking a link, and the names on
-- both sides (20261101180000_invite_preview.sql).
--
-- Properties this file pins:
--   * an owner can cancel a waiting link (audited); a stranger can't cancel
--     one at all, an already-cancelled link can't be cancelled again, and an
--     accepted link can't be;
--   * a cancelled link no longer accepts, and its preview refuses — same answer
--     as a used or expired link, so cancelling is invisible to a stranger;
--   * the preview before the click names the owner, the request and the
--     relationship, and writes to the audit log like any other PII read;
--   * accepting with an account that has no member row says "finish setting
--     up your account" instead of failing on a foreign key;
--   * the owner reads the supporters' names and each supporter reads the
--     owner's; a stranger reads nothing, and a supporter doesn't collect the
--     other supporters' names.
begin;
select plan(17);

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

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;

select pg_temp.member('00000000-0000-0000-000f-0000000000a1');  -- owner
select pg_temp.member('00000000-0000-0000-000f-0000000000a2');  -- supporter
select pg_temp.member('00000000-0000-0000-000f-0000000000a3');  -- stranger

-- b1: the owner's request, open for help.
insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on, status)
values ('00000000-0000-0000-000f-0000000000b1', '00000000-0000-0000-000f-0000000000a1',
        'car_damage', 'people', 'Rear bumper after a parking-lot hit', 100000, current_date - 5, 'open');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-000f-0000000000a1');
select set_config('test.live', public.create_invite('00000000-0000-0000-000f-0000000000b1', 'cousin'), true);
select set_config('test.gone', public.create_invite('00000000-0000-0000-000f-0000000000b1', 'sister'), true);
select set_config('test.taken', public.create_invite('00000000-0000-0000-000f-0000000000b1', 'friend'), true);
select is((select count(*) from public.request_invites where request_id = '00000000-0000-0000-000f-0000000000b1'),
  3::bigint, 'the owner creates three links');

-- The supporter joins through the "friend" link.
select pg_temp.login('00000000-0000-0000-000f-0000000000a2');
select is(public.accept_invite(current_setting('test.taken')),
  '00000000-0000-0000-000f-0000000000b1'::uuid, 'the supporter accepts and gets the request');

-- --- cancelling a link ------------------------------------------------------------

select pg_temp.login('00000000-0000-0000-000f-0000000000a3');
select throws_ok(
  $$select public.revoke_invite((select id from public.request_invites
                                 where request_id = '00000000-0000-0000-000f-0000000000b1'))$$,
  'P0002', 'invite not found', 'a stranger cannot cancel someone else''s link');

select pg_temp.login('00000000-0000-0000-000f-0000000000a1');
select is_ok(
  $$select public.revoke_invite((select id from public.request_invites
                                 where request_id = '00000000-0000-0000-000f-0000000000b1'
                                   and relationship = 'sister'))$$,
  'the owner cancels the "sister" link');
select is((select count(*) from private.audit_log where action = 'invite.revoked'),
  1::bigint, 'cancelling is written down in the audit log');
select throws_ok(
  $$select public.revoke_invite((select id from public.request_invites
                                 where request_id = '00000000-0000-0000-000f-0000000000b1'
                                   and relationship = 'sister'))$$,
  '23514', 'the link was already used or cancelled', 'a cancelled link is not cancelled twice');
select throws_ok(
  $$select public.revoke_invite((select id from public.request_invites
                                 where request_id = '00000000-0000-0000-000f-0000000000b1'
                                   and accepted_at is not null))$$,
  '23514', 'the link was already used or cancelled',
  'an accepted link stays in the record and can''t be cancelled');

-- A cancelled link answers like a used one.
select pg_temp.login('00000000-0000-0000-000f-0000000000a3');
select throws_ok($$select public.accept_invite(current_setting('test.gone'))$$,
  'P0002', 'invite not found, used or expired', 'a cancelled link no longer accepts');
select throws_ok($$select public.invite_preview(current_setting('test.gone'))$$,
  'P0002', 'invite not found', 'a cancelled link previews nothing');
select throws_ok($$select public.invite_preview(current_setting('test.taken'))$$,
  'P0002', 'invite not found', 'an accepted link previews nothing more');

-- --- the preview before the click -------------------------------------------------

select pg_temp.login('00000000-0000-0000-000f-0000000000a3');
select set_config('test.preview', public.invite_preview(current_setting('test.live'))::text, true);
select results_eq(
  $$select (current_setting('test.preview')::jsonb ->> 'owner_name')::text,
            (current_setting('test.preview')::jsonb ->> 'relationship')::text,
            (current_setting('test.preview')::jsonb ->> 'title')::text,
            (current_setting('test.preview')::jsonb ->> 'kind')::text,
            (current_setting('test.preview')::jsonb ->> 'status')::text,
            (current_setting('test.preview')::jsonb ->> 'amount_cents')::bigint$$,
  $$values ('Member 00a1', 'cousin', 'Rear bumper after a parking-lot hit',
            'car_damage', 'open', 100000::bigint)$$,
  'before accepting, the invitee sees who invited them and what they are joining');
select is((select count(*) from private.audit_log where action = 'invite.preview'),
  1::bigint, 'the preview is written down in the audit log');

-- Accepting with an account that was never finished, not a foreign-key crash.
select pg_temp.login('00000000-0000-0000-000f-0000000000a9');
select throws_ok($$select public.accept_invite(current_setting('test.live'))$$,
  '42501', 'finish setting up your account',
  'an account with no member row is told what to do');

-- --- the names on both sides ------------------------------------------------------

select pg_temp.login('00000000-0000-0000-000f-0000000000a1');
select results_eq(
  $$select ((public.request_names('00000000-0000-0000-000f-0000000000b1')) ->> 'owner_name')::text,
            ((public.request_names('00000000-0000-0000-000f-0000000000b1') -> 'supporters' -> 0 ->> 'name')::text),
            ((public.request_names('00000000-0000-0000-000f-0000000000b1') -> 'supporters' -> 0 ->> 'relationship')::text)$$,
  $$values ('Member 00a1', 'Member 00a2', 'friend')$$,
  'the owner reads the supporter''s name and what the supporter said they are');

select pg_temp.login('00000000-0000-0000-000f-0000000000a2');
select results_eq(
  $$select ((public.request_names('00000000-0000-0000-000f-0000000000b1')) ->> 'owner_name')::text,
            ((public.request_names('00000000-0000-0000-000f-0000000000b1')) ->> 'me_name')::text$$,
  $$values ('Member 00a1', 'Member 00a2')$$,
  'a supporter reads their own name and the owner''s');
select is((public.request_names('00000000-0000-0000-000f-0000000000b1') -> 'supporters')::jsonb,
  '[]'::jsonb, 'a supporter doesn''t collect the other supporters'' names');

select pg_temp.login('00000000-0000-0000-000f-0000000000a3');
select throws_ok($$select public.request_names('00000000-0000-0000-000f-0000000000b1')$$,
  'P0002', 'request not found', 'a stranger reads no names at all');

rollback;