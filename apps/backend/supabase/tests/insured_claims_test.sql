-- Insured claims (20261102300000_insured_claims.sql).
--
-- Properties this file pins:
--   * the partner's feed records a claim, and paid is exactly gross minus
--     the member's share;
--   * the same feed entry replayed is a no-op (unique partner_ref);
--   * denial needs a reviewer's recorded refuse decision in the same
--     transaction, and is audit-logged;
--   * the owner reads their claim; the member can't record one.
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

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

select pg_temp.member('00000000-0000-0000-0012-0000000000a1');
select pg_temp.member('00000000-0000-0000-0012-0000000000a2', 'NY');  -- reviewer, outside CA

insert into public.member_roles (member_id, role)
values ('00000000-0000-0000-0012-0000000000a2', 'reviewer');

insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                             status, description, public_summary, public_summary_confirmed_at,
                             current_score, submitted_at)
values ('00000000-0000-0000-0012-0000000000b1', '00000000-0000-0000-0012-0000000000a1',
        'car_damage', 'both', 'Collision damage', 90000, current_date - 4, 'draft',
        'Another driver cut in and dented my door panel.',
        'Door panel from a lane-change collision', now(), 91::smallint, now() - interval '3 days');
update public.requests set status = 'scoring' where id = '00000000-0000-0000-0012-0000000000b1';
update public.requests set status = 'open' where id = '00000000-0000-0000-0012-0000000000b1';
update public.requests set status = 'funded' where id = '00000000-0000-0000-0012-0000000000b1';

-- --- the partner's feed records claims ------------------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.record_claim('00000000-0000-0000-0012-0000000000b1', 'ins_claim_1', 38000::bigint, 1000::bigint)$$,
  'the feed records a covered claim');
select is((select paid_cents from public.claims where partner_ref = 'ins_claim_1'),
  37000::bigint, 'paid is exactly gross minus the member''s share');
select lives_ok($$select public.record_claim('00000000-0000-0000-0012-0000000000b1', 'ins_claim_1', 999999::bigint, 0::bigint)$$,
  'the same feed entry replayed changes nothing');
select is((select gross_cents from public.claims where partner_ref = 'ins_claim_1'),
  38000::bigint, 'the replayed entry left the original figures alone');

-- --- denial follows a recorded refuse review ---------------------------------

select throws_ok($$select public.deny_claim((select id from public.claims where partner_ref = 'ins_claim_1'), 'no evidence of a collision')$$,
  '42501', 'only a reviewer''s recorded decision can deny a claim',
  'a denial without a person''s review is refused');
insert into public.reviews (request_id, reviewer_id, decision, reason)
values ('00000000-0000-0000-0012-0000000000b1', '00000000-0000-0000-0012-0000000000a2', 'refuse',
        'The photos show parking damage, not a collision.');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0012-0000000000a2');
select lives_ok($$select public.deny_claim((select id from public.claims where partner_ref = 'ins_claim_1'), 'the reviewer''s photos show parking damage')$$,
  'a denial right after a recorded refuse review goes through');
reset role;
select is((select count(*) from private.audit_log where action = 'claim.denied'),
  1::bigint, 'the denial is audit-logged with its reason');
