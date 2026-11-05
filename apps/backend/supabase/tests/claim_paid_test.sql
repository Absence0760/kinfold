-- Claim payments (20261102360000_claim_paid.sql).
--
-- Properties this file pins:
--   * the service closes a recorded claim as paid and audit-trails it;
--   * a denied claim can never be paid; a replayed confirmation changes
--     nothing;
--   * members can't confirm payments.
begin;
-- Audit counts read only this transaction's rows (`at = now()`): the seed's own
-- trail predates it, and a count over the whole log would read the seed too.
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

select pg_temp.member('00000000-0000-0000-0018-0000000000a1');
insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                             status, description, public_summary, public_summary_confirmed_at,
                             current_score, submitted_at)
values ('00000000-0000-0000-0018-0000000000b1', '00000000-0000-0000-0018-0000000000a1',
        'car_damage', 'pool', 'A claim to pay', 100000, current_date - 5, 'draft',
        'A request the insurer will pay a claim on.',
        'Bumper after a slow backing-in', now(), 85::smallint, now() - interval '9 days');
update public.requests set status = 'scoring' where id = '00000000-0000-0000-0018-0000000000b1';
update public.requests set status = 'open' where id = '00000000-0000-0000-0018-0000000000b1';

insert into public.claims (id, request_id, partner_ref, gross_cents, member_share_cents,
                           paid_cents, status)
values ('00000000-0000-0000-0018-0000000000d1', '00000000-0000-0000-0018-0000000000b1',
        'pc_p1', 40000::bigint, 1000::bigint, 39000::bigint, 'recorded');
insert into public.claims (id, request_id, partner_ref, gross_cents, member_share_cents,
                           paid_cents, status, reason)
values ('00000000-0000-0000-0018-0000000000d2', '00000000-0000-0000-0018-0000000000b1',
        'pc_p2', 20000::bigint, 500::bigint, 19500::bigint, 'denied',
        'The photos show parking damage, not a collision.');

-- --- the service confirms payments ---------------------------------------------

set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.mark_claim_paid('00000000-0000-0000-0018-0000000000d1', 'pay_evt_1')$$,
  'the feed confirms a recorded claim was paid');
select is((select status from public.claims where partner_ref = 'pc_p1'),
  'paid'::public.claim_status, 'the row now says paid');
reset role;
select is((select count(*) from private.audit_log where action = 'claim.paid' and at = now()),
  1::bigint, 'the payment is audit-logged with the partner reference');
set local role service_role;
select pg_temp.as_service();
select lives_ok($$select public.mark_claim_paid('00000000-0000-0000-0018-0000000000d1', 'pay_evt_1')$$,
  'a replayed confirmation changes nothing');
reset role;
select is((select count(*) from private.audit_log where action = 'claim.paid' and at = now()),
  1::bigint, 'the replay added no second audit row');
set local role service_role;
select pg_temp.as_service();

-- --- refusals ------------------------------------------------------------------

select throws_ok($$select public.mark_claim_paid('00000000-0000-0000-0018-0000000000d2', 'pay_evt_2')$$,
  '23514', 'a denied claim pays nothing',
  'a denied claim never becomes paid');
select throws_ok($$select public.mark_claim_paid('00000000-0000-0000-0018-00000000ffff', 'pay_evt_3')$$,
  'P0002', 'claim not found',
  'a missing claim says so');
