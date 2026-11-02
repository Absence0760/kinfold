-- Reviewer and panel access: what the operations console and the appeals panel
-- can read, and what a panel decision must carry.
--
-- Properties this file pins:
--   * a reviewer reads the evidence (and the redacted copy in storage) of the
--     requests they may review, but a same-region reviewer and a plain member
--     read none of it;
--   * a reviewer can ask which queue entries they may review, as booleans only
--     - the requester's region never crosses into the response;
--   * a panel member reads the request and its score behind an open appeal, a
--     plain member reads neither;
--   * a panel decision carries a written reason of at least 10 characters, is
--     stored on the appeal, and is audit-logged with it;
--   * opening an original for review is audit-logged, and a member who may not
--     review gets nothing.
begin;
select plan(25);

-- --- fixtures ------------------------------------------------------------------
-- Temporary helpers, gone at rollback. They run as postgres (the owner), standing
-- in for the service role and the partner webhooks; clients can't do any of this.

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

create function pg_temp.request(p_id uuid, p_member uuid, p_funding public.funding_mode default 'pool',
                                p_amount bigint default 100000, p_kind public.request_kind default 'car_damage')
returns uuid language sql as $$
  insert into public.requests (id, member_id, kind, funding, title, amount_cents, incident_on)
  values (p_id, p_member, p_kind, p_funding, 'Test request', p_amount, current_date - 5)
  returning id;
$$;

create function pg_temp.move(p_request uuid, variadic p_path public.request_status[])
returns void language plpgsql as $$
declare
  s public.request_status;
begin
  foreach s in array p_path loop
    update public.requests set status = s where id = p_request;
  end loop;
end $$;

create function pg_temp.login(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;

select pg_temp.member('00000000-0000-0000-000d-0000000000a1', 'CA');  -- olga, the requester
select pg_temp.member('00000000-0000-0000-000d-0000000000a2', 'NY');  -- rita, reviewer
select pg_temp.member('00000000-0000-0000-000d-0000000000a3', 'CA');  -- carl, reviewer in olga's region
select pg_temp.member('00000000-0000-0000-000d-0000000000a4', 'TX');  -- pia, appeal panel
select pg_temp.member('00000000-0000-0000-000d-0000000000a5', 'WA');  -- xan, plain member
insert into public.member_roles (member_id, role) values
  ('00000000-0000-0000-000d-0000000000a2', 'reviewer'),
  ('00000000-0000-0000-000d-0000000000a3', 'reviewer'),
  ('00000000-0000-0000-000d-0000000000a4', 'panel');

-- q1: olga, waiting for a person, with evidence. q2: rita's own. q3: olga, open.
select pg_temp.request('00000000-0000-0000-000d-0000000000b1', '00000000-0000-0000-000d-0000000000a1');
select pg_temp.move('00000000-0000-0000-000d-0000000000b1', 'scoring', 'in_review');
insert into public.evidence (request_id, kind, original_path, redacted_path, sha256, redaction_status)
  values ('00000000-0000-0000-000d-0000000000b1', 'photo', 'q1/original.jpg', 'q1/redacted.jpg',
          repeat('a', 64), 'confirmed');
insert into storage.objects (bucket_id, name, size, type)
  values ('evidence-redacted', 'q1/redacted.jpg', 1024, 'image/jpeg'),
         ('evidence-original', 'q1/original.jpg', 1024, 'image/jpeg');
insert into public.scores (request_id, score, reasons, model, model_version, prompt_version, inputs_sha256)
  values ('00000000-0000-0000-000d-0000000000b1', 80::smallint, '["estimate matches the photos"]'::jsonb,
          'dev-scorer', '0.0.1', 'score-v1', repeat('a', 64));
select pg_temp.request('00000000-0000-0000-000d-0000000000b2', '00000000-0000-0000-000d-0000000000a2');
select pg_temp.move('00000000-0000-0000-000d-0000000000b2', 'scoring', 'in_review');
select pg_temp.request('00000000-0000-0000-000d-0000000000b3', '00000000-0000-0000-000d-0000000000a1');
select pg_temp.move('00000000-0000-0000-000d-0000000000b3', 'scoring', 'open');

-- --- reviewers read the evidence of what they may review -------------------------
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000d-0000000000a2');
select is((select count(*) from public.evidence
           where request_id = '00000000-0000-0000-000d-0000000000b1'), 1::bigint,
  'a reviewer reads the evidence of a request waiting for a person');
select is((select count(*) from storage.objects
           where bucket_id = 'evidence-redacted' and name = 'q1/redacted.jpg'), 1::bigint,
  'the reviewer reaches the redacted copy');

select pg_temp.login('00000000-0000-0000-000d-0000000000a3');
select is((select count(*) from public.evidence
           where request_id = '00000000-0000-0000-000d-0000000000b1'), 0::bigint,
  'a reviewer in the requester''s region reads none of it');
select is((select count(*) from storage.objects
           where bucket_id = 'evidence-redacted' and name = 'q1/redacted.jpg'), 0::bigint,
  'and reaches no copy of the evidence');

select pg_temp.login('00000000-0000-0000-000d-0000000000a5');
select is((select count(*) from public.evidence
           where request_id = '00000000-0000-0000-000d-0000000000b1'), 0::bigint,
  'a plain member reads none of it');

-- --- the queue asks which entries may be reviewed --------------------------------
reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000d-0000000000a2');
select is((public.review_flags(
  array['00000000-0000-0000-000d-0000000000b1',
        '00000000-0000-0000-000d-0000000000b2',
        '00000000-0000-0000-000d-0000000000b3']::uuid[])
  -> '00000000-0000-0000-000d-0000000000b1')::text, 'true',
  'the reviewer may review the request in front of them');
select is((public.review_flags(
  array['00000000-0000-0000-000d-0000000000b1',
        '00000000-0000-0000-000d-0000000000b2',
        '00000000-0000-0000-000d-0000000000b3']::uuid[])
  -> '00000000-0000-0000-000d-0000000000b2')::text, 'false',
  'not their own request');
select is((public.review_flags(
  array['00000000-0000-0000-000d-0000000000b1',
        '00000000-0000-0000-000d-0000000000b2',
        '00000000-0000-0000-000d-0000000000b3']::uuid[])
  -> '00000000-0000-0000-000d-0000000000b3')::text, 'false',
  'not one that is not waiting for a person');

select pg_temp.login('00000000-0000-0000-000d-0000000000a3');
select is((public.review_flags(
  array['00000000-0000-0000-000d-0000000000b1']::uuid[])
  -> '00000000-0000-0000-000d-0000000000b1')::text, 'false',
  'the same-region reviewer is told they may not, without naming the region');

-- --- refusing opens an appeal for the panel --------------------------------------
select pg_temp.login('00000000-0000-0000-000d-0000000000a2');
select is(public.record_review('00000000-0000-0000-000d-0000000000b1', 'refuse', 'Estimate is for a different car.'),
  'refused'::public.request_status, 'rita refuses q1');
select pg_temp.login('00000000-0000-0000-000d-0000000000a1');
select isnt(public.file_appeal('00000000-0000-0000-000d-0000000000b1', 'The shop quoted the wrong panel.'), null,
  'olga appeals the refusal');

-- --- the panel reads what it decides ---------------------------------------------
reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-000d-0000000000a4');
select is((select count(*) from public.requests where id = '00000000-0000-0000-000d-0000000000b1'), 1::bigint,
  'a panel member reads the refused request behind an open appeal');
select is((select count(*) from public.scores where request_id = '00000000-0000-0000-000d-0000000000b1'), 1::bigint,
  'and the score that sent it to a person');

select pg_temp.login('00000000-0000-0000-000d-0000000000a5');
select is((select count(*) from public.requests where id = '00000000-0000-0000-000d-0000000000b1'), 0::bigint,
  'a plain member still reads none of it');

-- --- a decision carries a reason ---------------------------------------------------
select pg_temp.login('00000000-0000-0000-000d-0000000000a5');
select throws_ok(
  $$select public.decide_appeal((select id from public.appeals
     where request_id = '00000000-0000-0000-000d-0000000000b1'), true, 'Anyone may decide it.')$$,
  '42501', 'appeal panel only', 'a plain member cannot decide an appeal');
select pg_temp.login('00000000-0000-0000-000d-0000000000a2');
select throws_ok(
  $$select public.decide_appeal((select id from public.appeals
     where request_id = '00000000-0000-0000-000d-0000000000b1'), true, 'Anyone may decide it.')$$,
  '42501', 'appeal panel only', 'a reviewer who is not on the panel cannot decide an appeal');
select pg_temp.login('00000000-0000-0000-000d-0000000000a4');
select throws_ok(
  $$select public.decide_appeal((select id from public.appeals
     where request_id = '00000000-0000-0000-000d-0000000000b1'), true, 'not it')$$,
  '23514', 'an appeal decision is written down in at least 10 characters',
  'a panel decision needs a written reason');
select lives_ok(
  $$select public.decide_appeal((select id from public.appeals
     where request_id = '00000000-0000-0000-000d-0000000000b1'), true, 'The quoted panel is not the damage.')$$,
  'the panel upholds the appeal with a reason');
select is((select status from public.appeals
           where request_id = '00000000-0000-0000-000d-0000000000b1'), 'upheld'::public.appeal_status,
  'the appeal is stored as upheld');
select is((select status from public.requests where id = '00000000-0000-0000-000d-0000000000b1'),
  'in_review'::public.request_status, 'an upheld appeal sends the request back to review');
select is((select decision_note from public.appeals
           where request_id = '00000000-0000-0000-000d-0000000000b1'),
  'The quoted panel is not the damage.', 'the reason is stored on the appeal');
select is((select count(*) from private.audit_log
           where actor = '00000000-0000-0000-000d-0000000000a4' and action = 'appeal.upheld'
             and target = 'appeals' and detail ->> 'reason' = 'The quoted panel is not the damage.'), 1::bigint,
  'the decision is audit-logged with its reason');

-- --- opening an original for review is written down --------------------------------
select pg_temp.login('00000000-0000-0000-000d-0000000000a2');
select is_not_null(public.evidence_view(
  (select id from public.evidence where request_id = '00000000-0000-0000-000d-0000000000b1')),
  'the reviewer opens the evidence for viewing');
select pg_temp.login('00000000-0000-0000-000d-0000000000a3');
select throws_ok(
  $$select public.evidence_view((select id from public.evidence
     where request_id = '00000000-0000-0000-000d-0000000000b1'))$$,
  'P0002', 'evidence not found or not reviewable by this member',
  'a same-region reviewer opens nothing');
select is((select count(*) from private.audit_log
           where actor = '00000000-0000-0000-000d-0000000000a2' and action = 'evidence.view'
             and target = 'evidence'), 1::bigint,
  'the read is written to the audit trail');

select * from finish();
rollback;