-- Payout opening (20261102320000_payout_creation.sql).
--
-- Properties this file pins:
--   * the service opens a payout against a funded request: named verified
--     payee, final invoice evidence, amount within the captured money, and
--     it starts `pending` (money moves when it's sent);
--   * the same partner payout reference replayed is a no-op answering with
--     the payout it already made;
--   * an empty reference, an over-capture amount, and a member are refused;
--   * the guard audits the opening.
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

create function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

select pg_temp.member('00000000-0000-0000-0014-0000000000a1');

insert into public.payees (id, kind, legal_name, region, status, partner_account_ref, verified_at)
values ('00000000-0000-0000-0014-0000000000c9', 'repair_shop', 'Shop', 'CA', 'verified', 'acct_c9', now() - interval '1 year');
insert into public.requests (id, member_id, payee_id, kind, funding, title, amount_cents,
                             incident_on, status, description, public_summary,
                             public_summary_confirmed_at, current_score, submitted_at)
values ('00000000-0000-0000-0014-0000000000b1', '00000000-0000-0000-0014-0000000000a1',
        '00000000-0000-0000-0014-0000000000c9', 'car_damage', 'people', 'Funded request', 30000,
        current_date - 20, 'draft', 'A funded request waiting for its payout.',
        'Fender after a shopping-cart denty', now(), 87::smallint, now() - interval '12 days');
update public.requests set status = 'scoring' where id = '00000000-0000-0000-0014-0000000000b1';
update public.requests set status = 'open' where id = '00000000-0000-0000-0014-0000000000b1';
update public.requests set status = 'funded' where id = '00000000-0000-0000-0014-0000000000b1';
insert into public.evidence (id, request_id, kind, original_path, redacted_path, sha256,
                             redaction_status)
values ('00000000-0000-0000-0014-0000000000e1', '00000000-0000-0000-0014-0000000000b1',
        'invoice', 'x/original.pdf', 'x/redacted.pdf', repeat('a', 64), 'confirmed');

insert into public.contributions (id, request_id, contributor_id, source, amount_cents, status,
                                  created_at)
values ('00000000-0000-0000-0014-0000000000c3', '00000000-0000-0000-0014-0000000000b1',
        '00000000-0000-0000-0014-0000000000a1', 'gift', 30000, 'captured', now() - interval '2 days');

-- --- the service opens payouts ------------------------------------------

set local role service_role;
select pg_temp.as_service();
select is((select amount_cents from public.payouts where partner_ref = 'pi_pc_1'),
  30000::bigint, 'the payout opens with the partner''s figure');
select is((select status from public.payouts where partner_ref = 'pi_pc_1'),
  'pending'::public.payout_status, 'a payout starts pending: money moves when it is sent');
select is((select public.create_payout('00000000-0000-0000-0014-0000000000b1',
        '00000000-0000-0000-0014-0000000000c9', 30000::bigint,
        '00000000-0000-0000-0014-0000000000e1', 'pi_pc_1')),
  (select id from public.payouts where partner_ref = 'pi_pc_1'),
  'the same payout reference replayed is a no-op answering with the payout it made');
select is((select count(*) from public.payouts where partner_ref = 'pi_pc_1'),
  1::bigint, 'the replay added no second payout');
reset role;
select is((select count(*) from private.audit_log where action = 'payout.pending'),
  1::bigint, 'the opening is audit-logged by the guard');
set local role service_role;
select pg_temp.as_service();

-- --- refusals ------------------------------------------------------------------

select throws_ok($$select public.create_payout('00000000-0000-0000-0014-0000000000b1',
  '00000000-0000-0000-0014-0000000000c9', 40000::bigint, '00000000-0000-0000-0014-0000000000e1',
  'pi_pc_2')$$,
  '23514', 'payouts cannot exceed captured contributions',
  'a payout over the captured money is refused');
select throws_ok($$select public.create_payout('00000000-0000-0000-0014-0000000000b1',
  '00000000-0000-0000-0014-0000000000c9', 100::bigint, '00000000-0000-0000-0014-0000000000e1',
  '')$$,
  '23514', 'a payout needs the partner''s payout reference',
  'an empty payout reference is refused');

-- --- a member can't open payouts ----------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0014-0000000000a1');
select throws_ok($$select public.create_payout('00000000-0000-0000-0014-0000000000b1',
  '00000000-0000-0000-0014-0000000000c9', 100::bigint, '00000000-0000-0000-0014-0000000000e1',
  'pi_pc_3')$$,
  '42501', 'payouts are opened by the service', 'a member cannot open a payout');
