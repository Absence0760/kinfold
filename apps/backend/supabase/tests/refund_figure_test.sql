-- mark_refunded answers with the refund figure (20261102260000_refund_figure.sql).
--
-- Properties this file pins:
--   * the refund call returns the figure the schema computed (`refunds_due`
--     splits captured money across live payouts oldest first), so the webhook
--     journals the schema's number, not the partner's word;
--   * the same refund twice is a no-op that still answers with the stored
--     figure;
--   * money that reached the payee isn't refunded;
--   * members can't run the refund at all.
begin;
select plan(6);

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

-- A withdrawn request whose captured money is split: the older contribution
-- was partly paid out, so only part of it is due back.
create function pg_temp.captured(p_contribution uuid, p_request uuid, p_member uuid,
                                 p_amount bigint, p_seq integer)
returns void language sql as $$
  insert into public.contributions (id, request_id, contributor_id, source, amount_cents,
                                    status, captured_at, created_at)
  values (p_contribution, p_request, p_member, 'gift', p_amount, 'captured',
          now() - interval '3 days', now() - make_interval(days => 10 - p_seq));
$$;

select pg_temp.member('00000000-0000-0000-0010-0000000000a1');
select pg_temp.member('00000000-0000-0000-0010-0000000000a2');

insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on,
                             status, description, public_summary, public_summary_confirmed_at,
                             current_score, submitted_at)
values ('00000000-0000-0000-0010-0000000000b1', '00000000-0000-0000-0010-0000000000a1',
        'car_damage', 'people', 'Old request', 60000, current_date - 20, 'withdrawn',
        'An old request the owner withdrew.', 'Rear bumper after a slow backing-in', now(),
        87::smallint, now() - interval '12 days');

select pg_temp.captured('00000000-0000-0000-0010-0000000000c1', '00000000-0000-0000-0010-0000000000b1',
                        '00000000-0000-0000-0010-0000000000a2', 40000, 1);
select pg_temp.captured('00000000-0000-0000-0010-0000000000c2', '00000000-0000-0000-0010-0000000000b1',
                        '00000000-0000-0000-0010-0000000000a2', 20000, 2);

-- --- the refund answers with the split figure ------------------------------------

set local role service_role;
select pg_temp.as_service();
select is((select public.mark_refunded('00000000-0000-0000-0010-0000000000c1', 'rf_a')),
  40000::bigint, 'the refund call returns the split figure for the contribution');
select is((select refunded_cents from public.contributions
           where id = '00000000-0000-0000-0010-0000000000c1'),
  40000::bigint, 'the row stores the same figure it answered with');
select is((select public.mark_refunded('00000000-0000-0000-0010-0000000000c1', 'rf_a')),
  40000::bigint, 'the same refund replayed is a no-op that answers with the stored figure');
select is((select public.mark_refunded('00000000-0000-0000-0010-0000000000c2', 'rf_b')),
  20000::bigint, 'the second contribution refunds its own figure');

-- --- money that reached the payee is not refunded ------------------------------

insert into public.payees (id, kind, legal_name, region, status, partner_account_ref)
values ('00000000-0000-0000-0010-0000000000c9', 'repair_shop', 'Shop', 'CA', 'verified', 'acct_c9');
insert into public.evidence (id, request_id, kind, original_path, redacted_path, sha256,
                             redaction_status)
values ('00000000-0000-0000-0010-0000000000e1', '00000000-0000-0000-0010-0000000000b1',
        'invoice', 'x/original.pdf', 'x/redacted.pdf', repeat('a', 64), 'confirmed');
-- A live payout on a funded request: refunds_due skips the request entirely.
insert into public.requests (id, member_id, payee_id, kind, funding, title, amount_cents,
                             incident_on, status, description, public_summary,
                             public_summary_confirmed_at, current_score, submitted_at)
values ('00000000-0000-0000-0010-0000000000b2', '00000000-0000-0000-0010-0000000000a1',
        '00000000-0000-0000-0010-0000000000c9', 'car_damage', 'people', 'Funded request', 30000,
        current_date - 20, 'funded', 'A funded request with money out to its payee.',
        'Fender after a shopping-cart denty', now(), 87::smallint, now() - interval '12 days');
insert into public.contributions (id, request_id, contributor_id, source, amount_cents, status,
                                  captured_at)
values ('00000000-0000-0000-0010-0000000000c3', '00000000-0000-0000-0010-0000000000b2',
        '00000000-0000-0000-0010-0000000000a2', 'gift', 30000, 'captured', now() - interval '2 days');
insert into public.payouts (id, request_id, payee_id, amount_cents, invoice_evidence_id,
                            status, partner_ref, sent_at)
values ('00000000-0000-0000-0010-0000000000d1', '00000000-0000-0000-0010-0000000000b2',
        '00000000-0000-0000-0010-0000000000c9', 30000, '00000000-0000-0000-0010-0000000000e1',
        'sent', 'acct_d1', now() - interval '1 day');
select throws_ok($$select public.mark_refunded('00000000-0000-0000-0010-0000000000c3', 'rf_c')$$,
  'P0002', 'contribution not found or not due a refund',
  'money out with the payee is not the cron's to refund');

-- --- a member can't refund anything ------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0010-0000000000a1');
select throws_ok($$select public.mark_refunded('00000000-0000-0000-0010-0000000000c2', 'rf_d')$$,
  '42501', 'permission denied for function mark_refunded', 'a member cannot refund money');
