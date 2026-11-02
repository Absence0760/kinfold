-- Claim appeals (20261102350000_claim_appeal.sql).
--
-- Properties this file pins:
--   * the requester appeals a denied claim with a written reason and it
--     re-opens (back to `recorded`, decision cleared, audit-logged);
--   * a re-opened claim counts toward insured cover again;
--   * a short reason, another member, and a claim that isn't denied are all
--     refused.
begin;
select plan(7);

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

select pg_temp.member('00000000-0000-0000-0017-0000000000a1');  -- requester
select pg_temp.member('00000000-0000-0000-0017-0000000000a2');  -- another member

insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                             status, description, public_summary, public_summary_confirmed_at,
                             current_score, submitted_at)
values ('00000000-0000-0000-0017-0000000000b1', '00000000-0000-0000-0017-0000000000a1',
        'car_damage', 'pool', 'A denied claim', 100000, current_date - 5, 'open',
        'A request whose insurer claim was denied.',
        'Door panel after a slow scrape in a lot', now(), 85::smallint,
        now() - interval '9 days');

-- The fixtures run as postgres (the owner): a denied claim with its reason.
insert into public.claims (id, request_id, partner_ref, gross_cents, member_share_cents,
                           paid_cents, status, reason, decided_by, decided_at)
values ('00000000-0000-0000-0017-0000000000d1', '00000000-0000-0000-0017-0000000000b1',
        'pc_a1', 40000::bigint, 1000::bigint, 39000::bigint, 'denied',
        'The photos show parking damage, not a lane change.',
        null, null);

-- --- the requester's appeal re-opens the claim ----------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0017-0000000000a1');
select lives_ok($$select public.appeal_claim('00000000-0000-0000-0017-0000000000d1',
  'It was a lane change at speed; the dashcam shows contact at 25 mph.')$$,
  'the requester appeals their denied claim with a written reason');
select is((select status from public.claims where partner_ref = 'pc_a1'),
  'recorded'::public.claim_status, 'the appeal re-opens the claim for a fresh decision');
select is((select count(*) from private.audit_log where action = 'claim.appealed'),
  1::bigint, 'the appeal is audit-logged with its reason');
select is(public.insured_cover_cents('00000000-0000-0000-0017-0000000000b1'),
  40000::bigint, 'the re-opened claim counts toward insured cover again');

-- --- refusals ------------------------------------------------------------------

select throws_ok($$select public.appeal_claim('00000000-0000-0000-0017-0000000000d1', 'short')$$,
  '23514', 'an appeal needs the written reason (at least 10 characters)',
  'an appeal without a written reason is refused');

-- Another member can't appeal someone else's claim.
insert into public.claims (id, request_id, partner_ref, gross_cents, member_share_cents,
                           paid_cents, status, reason, decided_by, decided_at)
values ('00000000-0000-0000-0017-0000000000d2', '00000000-0000-0000-0017-0000000000b1',
        'pc_a2', 20000::bigint, 500::bigint, 19500::bigint, 'denied',
        'Duplicate of an earlier claim.', null, null);
select pg_temp.login('00000000-0000-0000-0017-0000000000a2');
select throws_ok($$select public.appeal_claim('00000000-0000-0000-0017-0000000000d2',
  'That was my damage too, please reconsider.')$$,
  '42501', 'only the requester can appeal their claim',
  'another member cannot appeal this claim');

-- A claim that isn't denied has nothing to appeal.
select throws_ok($$select public.appeal_claim('00000000-0000-0000-0017-0000000000d1',
  'appealing what is already open')$$,
  'P0002', 'claim not found or not denied',
  'a claim that is not denied has nothing to appeal');
