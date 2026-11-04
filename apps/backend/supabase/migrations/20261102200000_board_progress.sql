-- The board page used to call `request_raised_cents` once per open card
-- (followup: the board can't tell whether a request is taking pledges, or how
-- much it has raised). Two columns on the view settle both: progress for the
-- open request in front of the reader, and whether a pledge would be accepted
-- at all. Nothing new leaks: `raised_cents` is filled only while `open`, and
-- the payee's verification status is a boolean about the request, not about
-- the payee.
--
-- The view is dropped and re-created, so its grants are given again below.

-- The storage policy on redacted evidence reads the view, so it is dropped and
-- re-created with it: PostgreSQL refuses to drop a view a policy still holds.
drop policy "redacted evidence on the board" on storage.objects;
drop view public.board_requests;

create view public.board_requests with (security_barrier) as
select
  r.id,
  r.kind,
  r.public_summary,
  r.status,
  -- The exact ask only while it is still being funded: givers need it.
  case when r.status = 'open' then r.amount_cents end as amount_cents,
  b.lo as amount_band_min_cents,
  b.hi as amount_band_max_cents,
  ((r.current_score / 10) * 10)::smallint as score_band,
  -- Pledged or captured so far, shared only while the request is still asking
  -- for money: the board's progress line, so the page doesn't have to ask per
  -- card (the same figure `pledge` caps against).
  case when r.status = 'open' then private.raised_cents(r.id) end as raised_cents,
  -- Whether a pledge would be accepted now: open and the payee verified. The
  -- board can say so up front instead of refusing on the first gift.
  r.status = 'open'
    and exists (select 1 from public.payees p where p.id = r.payee_id and p.status = 'verified')
    as taking_pledges,
  public.board_area(m.region) as area,
  date_trunc('month', r.submitted_at)::date as month_of
from public.requests r
join public.members m on m.id = r.member_id
cross join lateral (
  select lo, hi from (values
    (0::bigint, 50000::bigint), (50000, 100000), (100000, 250000), (250000, 500000),
    (500000, 1000000), (1000000, 2500000), (2500000, 5000000), (5000000, 10000000),
    (10000000, null)
  ) bands (lo, hi)
  where r.amount_cents >= lo and (hi is null or r.amount_cents < hi)
) b
where public.on_board(r)
  and public.is_active_member();
-- A dropped view lost its grants: hand back what the last step granted.
grant select on public.board_requests to authenticated;
grant select on public.board_requests to service_role;

-- A dropped policy lost its rules: hand back the one the last step had.
create policy "redacted evidence on the board" on storage.objects for select to authenticated
  using (bucket_id = 'evidence-redacted' and exists (
    select 1 from public.evidence e
    join public.requests r on r.id = e.request_id
    where e.redacted_path = storage.objects.name
      and (r.member_id = auth.uid()
           or (e.redaction_status = 'confirmed' and r.id in (select id from public.board_requests)))
  ));
