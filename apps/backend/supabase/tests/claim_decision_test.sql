-- Claim decisions (20261102370000_claim_decision.sql).
--
-- Properties this file pins:
--   * a reviewer's decide_claim records the refusal AND denies the claim in
--     one step, audit-trailing both;
--   * a second decision on the same claim is refused, and adds no review;
--   * a member who isn't a reviewer cannot decide at all.
begin;
select plan(8);

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

insert into public.member_roles (member_id, role)
values ('00000000-0000-0000-0017-0000000000a2', 'reviewer');

select pg_temp.member('00000000-0000-0000-0017-0000000000a1');
select pg_temp.member('00000000-0000-0000-0017-0000000000a2', 'NY');

insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                             status, description, public_summary, public_summary_confirmed_at,
                             current_score, submitted_at)
values ('00000000-0000-0000-0017-0000000000b1', '00000000-0000-0000-0017-0000000000a1',
        'car_damage', 'pool', 'A claim to decide', 100000, current_date - 5, 'in_review',
        'A request with a standing insured claim.',
        'Bumper after a slow backing-in', now(), 85::smallint, now() - interval '9 days');

insert into public.claims (id, request_id, partner_ref, gross_cents, member_share_cents,
                           paid_cents, status)
values ('00000000-0000-0000-0017-0000000000d1', '00000000-0000-0000-0017-0000000000b1',
        'pc_d1', 40000::bigint, 1000::bigint, 39000::bigint, 'recorded');
insert into public.claims (id, request_id, partner_ref, gross_cents, member_share_cents,
                           paid_cents, status)
values ('00000000-0000-0000-0017-0000000000d2', '00000000-0000-0000-0017-0000000000b1',
        'pc_d2', 20000::bigint, 500::bigint, 19500::bigint, 'recorded');

-- --- the reviewer decides ------------------------------------------------------

select pg_temp.login('00000000-0000-0000-0017-0000000000a2');
select lives_ok($$select public.decide_claim('00000000-0000-0000-0017-0000000000d1',
  'The photos show parking damage, not a collision.')$$,
  'a reviewer closes a standing claim in one step');
select is((select status from public.claims where partner_ref = 'pc_d1'),
  'denied'::public.claim_status, 'the claim is now denied');
select is((select count(*) from public.reviews where request_id = '00000000-0000-0000-0017-0000000000b1'),
  1::bigint, 'the reviewer''s refusal was recorded');
select is((select count(*) from public.reviews
           where request_id = '00000000-0000-0000-0017-0000000000b1' and decision = 'refuse'),
  1::bigint, 'the recorded decision is a refusal');
select is((select count(*) from private.audit_log where action = 'claim.denied'),
  1::bigint, 'the denial is audit-logged');

-- --- refusals ------------------------------------------------------------------

select throws_ok($$select public.decide_claim('00000000-0000-0000-0017-0000000000d1',
  'deciding twice is not a thing')$$,
  'P0002', 'claim not found, or already decided',
  'a decided claim cannot be decided again');
select is((select count(*) from public.reviews
           where request_id = '00000000-0000-0000-0017-0000000000b1'),
  1::bigint, 'the refused attempt recorded no review');

select pg_temp.login('00000000-0000-0000-0017-0000000000a1');
select throws_ok($$select public.decide_claim('00000000-0000-0000-0017-0000000000d2',
  'a member who is not a reviewer cannot decide')$$,
  '42501', 'reviewers only',
  'only a reviewer's decision can deny a claim');
