-- A denial always carries the person's words (20261102670000_denial_reason.sql).
--
-- Properties this file pins:
--   * a standing claim cannot be denied with no reason or a short one: the
--     console door refuses before anything is written, so the refusal AND the
--     denial both leave nothing behind;
--   * a denial with words lands the reason on the claim, audit-logged, next to
--     the reviewer's own recorded refusal;
--   * the table itself backstops the door: a wordless denial cannot be written
--     by any route, and ten characters is accepted exactly.
begin;
select plan(12);

-- --- fixtures ------------------------------------------------------------------

create function pg_temp.member(p_id uuid, p_region text default 'CA',
                               p_status public.member_status default 'active')
returns uuid language plpgsql as $$
begin
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
  return p_id;
end $$;

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

select pg_temp.member('00000000-0000-0000-0020-0000000000a1');               -- requester, CA
select pg_temp.member('00000000-0000-0000-0020-0000000000a2', 'NY');         -- reviewer, outside CA

insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                             status, description, public_summary, public_summary_confirmed_at,
                             current_score, submitted_at)
values ('00000000-0000-0000-0020-0000000000b1', '00000000-0000-0000-0020-0000000000a1',
        'car_damage', 'both', 'Collision damage', 90000, current_date - 4, 'draft',
        'Another driver cut in and dented my door panel.',
        'Door panel from a lane-change collision', now(), 91::smallint, now() - interval '3 days'),
       ('00000000-0000-0000-0020-0000000000b2', '00000000-0000-0000-0020-0000000000a1',
        'car_damage', 'both', 'Second collision damage', 90000, current_date - 4, 'draft',
        'A shop van clipped my bumper in the loading bay.',
        'Bumper from a loading-bay scrape', now(), 88::smallint, now() - interval '3 days');
update public.requests set status = 'scoring' where id = '00000000-0000-0000-0020-0000000000b2';
update public.requests set status = 'open' where id = '00000000-0000-0000-0020-0000000000b2';
update public.requests set status = 'funded' where id = '00000000-0000-0000-0020-0000000000b2';

update public.requests set status = 'scoring' where id = '00000000-0000-0000-0020-0000000000b1';
update public.requests set status = 'open' where id = '00000000-0000-0000-0020-0000000000b1';
update public.requests set status = 'funded' where id = '00000000-0000-0000-0020-0000000000b1';

-- Two standing claims from the partner's feed, nothing decided yet.
insert into public.claims (id, request_id, partner_ref, gross_cents, member_share_cents,
                           paid_cents, status)
values ('00000000-0000-0000-0020-0000000000d1', '00000000-0000-0000-0020-0000000000b1',
        'dr_c1', 40000::bigint, 1000::bigint, 39000::bigint, 'recorded'),
       ('00000000-0000-0000-0020-0000000000d2', '00000000-0000-0000-0020-0000000000b2',
        'dr_c2', 20000::bigint, 500::bigint, 19500::bigint, 'recorded');

-- --- a wordless denial is refused before anything is written ---------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0020-0000000000a2');
select throws_ok($$select public.decide_claim('00000000-0000-0000-0020-0000000000d1', 'no')$$,
  '23514', 'a denial needs the person''s written reason (at least 10 characters)',
  'a console denial without words is refused');
select is((select count(*) from public.reviews where request_id = '00000000-0000-0000-0020-0000000000b1'),
  0::bigint, 'the refused attempt recorded no review either');
select is((select status from public.claims where partner_ref = 'dr_c1'),
  'recorded'::public.claim_status, 'and the claim is still standing');

select throws_ok($$select public.deny_claim('00000000-0000-0000-0020-0000000000d1', '   ')$$,
  '23514', 'a denial needs the person''s written reason (at least 10 characters)',
  'spaces are no words, and the door runs before the reviewer check');

-- --- a denial with words lands its reason ----------------------------------------

select lives_ok($$select public.decide_claim('00000000-0000-0000-0020-0000000000d1',
  'The photos show parking damage, not a lane change.')$$,
  'a reviewer closes a standing claim in one step');
select is((select reason from public.claims where partner_ref = 'dr_c1'),
  'The photos show parking damage, not a lane change.', 'the denial carries the person''s words');
select is((select count(*) from public.reviews
           where request_id = '00000000-0000-0000-0020-0000000000b1' and decision = 'refuse'),
  1::bigint, 'the refusal is recorded beside it');
reset role;
select is((select count(*) from private.audit_log where action = 'claim.denied'),
  1::bigint, 'the denial is audit-logged');

-- --- the table backstops the door -------------------------------------------------

set local role service_role;
select pg_temp.as_service();

select throws_ok($$insert into public.claims (id, request_id, partner_ref, gross_cents,
  member_share_cents, paid_cents, status, reason)
  values ('00000000-0000-0000-0020-0000000000d3', '00000000-0000-0000-0020-0000000000b2',
          'dr_w1', 30000::bigint, 500::bigint, 29500::bigint, 'denied', 'nope')$$,
  '23514', null, 'a wordless denial cannot be written by any route');
select is((select count(*) from public.claims), 2::bigint, 'and nothing was added');
select lives_ok($$insert into public.claims (id, request_id, partner_ref, gross_cents,
  member_share_cents, paid_cents, status, reason)
  values ('00000000-0000-0000-0020-0000000000d3', '00000000-0000-0000-0020-0000000000b2',
          'dr_w2', 30000::bigint, 500::bigint, 29500::bigint, 'denied', '0123456789')$$,
  'ten characters is accepted exactly');

-- --- a member who is not a reviewer still cannot deny ------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0020-0000000000a1');
select throws_ok($$select public.deny_claim('00000000-0000-0000-0020-0000000000d2',
  'the requester has words but no authority')$$,
  '42501', 'only a reviewer''s recorded decision can deny a claim',
  'a good reason alone does not let a member deny their own claim');

reset role;
rollback;
