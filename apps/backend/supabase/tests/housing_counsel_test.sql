-- The Fund's one certified housing counselor (20261102700000_housing_counsel.sql).
--
-- Properties this file pins:
--   * the standing agency and the credential behind it are readable by anon and
--     by members, so a page can name who the Fund partners with and the CFR it
--     is certified under without a signed-in member;
--   * the agency is data: the newest effective version is current, a not-yet-
--     effective row waits, and changing agency is a new row rather than an edit;
--   * the credential is stated on the row, not implied: an approval date that
--     has passed, the CFR named exactly, a real name and a real link;
--   * one agency at a time: a second row sharing an effective date is refused;
--   * the standing row is never edited, so the agency that named an applicant's
--     help stays readable beside that request.
begin;
select plan(15);

-- --- the published agency reads ----------------------------------------------

select is(public.housing_counsel_version(), 1::int, 'the seeded agency is current');
select is((select agency_name from public.housing_counsel where version = public.housing_counsel_version()),
  'Pilot City Housing Counseling', 'a member reads the agency the Fund partners with by name');
select is((select certified_under from public.housing_counsel where version = public.housing_counsel_version()),
  '24 CFR part 214'::text, 'and the credential behind it');

-- --- a change of agency is a data change, and a future one waits ---------------

insert into public.housing_counsel values
  (2, 'Next Certified Agency', 'https://next.example/counsel', '2026-06-01', '24 CFR part 214', current_date);

select is(public.housing_counsel_version(), 2::int, 'the newest effective agency is the current one');
select is((select agency_name from public.housing_counsel where version = public.housing_counsel_version()),
  'Next Certified Agency', 'and the page names it, not the agency before it');

insert into public.housing_counsel values
  (3, 'Not Yet Effective Agency', 'https://later.example/counsel', '2026-09-01', '24 CFR part 214',
   current_date + 30);

select is(public.housing_counsel_version(), 2::int, 'an agency that is not yet effective stays out of the read');

-- --- the credential is stated on the row, not implied -------------------------

select throws_ok($$insert into public.housing_counsel values
  (4, '', 'https://blank.example/counsel', '2026-01-01', '24 CFR part 214', '2026-02-01')$$,
  '23514', null, 'an agency without a name cannot be published');
select throws_ok($$insert into public.housing_counsel values
  (5, 'Wrong Credential', 'https://wrong.example/counsel', '2026-01-01', '24 CFR part 213', '2026-03-01')$$,
  '23514', null, 'the row must name the CFR it is certified under, exactly');
select throws_ok($$insert into public.housing_counsel values
  (6, 'Bad Link', 'next.example/counsel', '2026-01-01', '24 CFR part 214', '2026-04-01')$$,
  '23514', null, 'the contact has to be a link a member can follow');
select throws_ok($$insert into public.housing_counsel values
  (7, 'Later Approval', 'https://later.example/counsel', '2099-01-01', '24 CFR part 214', '2026-05-01')$$,
  '23514', null, 'an approval date that has not happened yet cannot be published');
select throws_ok($$insert into public.housing_counsel values
  (8, 'Same Date Agency', 'https://same.example/counsel', '2026-01-01', '24 CFR part 214', current_date)$$,
  '23505', null, 'one agency at a time: a second row sharing the effective date is refused');

select is((select count(*) from public.housing_counsel), 3::bigint, 'and nothing bad was added');

-- --- the standing row is never edited ----------------------------------------

select throws_ok($$update public.housing_counsel set agency_name = 'Rewritten' where version = 1$$,
  '42501', 'housing_counsel is append-only', 'the agency that named an applicant''s help stays readable beside it');

-- --- positive controls, one per role -----------------------------------------

reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select is_ok((select count(*) from public.housing_counsel) >= 1,
  'a public page can name the agency without a signed-in member');
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
                  json_build_object('sub', '00000000-0000-0000-0000-000000000001',
                                    'role', 'authenticated')::text, true);
select is_ok((select count(*) from public.housing_counsel) >= 1,
  'a member on a loan or a request reads the same agency');
reset role;

rollback;