-- A supporter used to get the whole request row (followup: that handed them
-- `current_score`, which only the console and the board's band need, plus
-- fields the supporter's page never shows). The whole-row read is dropped;
-- a supporter now reads a view with only what their own page uses: the ask,
-- the story, the status, the incident date, and payee TRUTH as a conditional
-- id — the name still comes from the payees read policy, so an unverified
-- payee stays unnamed to a supporter.

drop policy "supporters read requests they back" on public.requests for select to authenticated;

create view public.support_requests with (security_barrier) as
select
  r.id,
  r.kind,
  r.funding,
  r.title,
  r.description,
  -- The exact ask: a supporter is funding it, so the number is their view.
  r.amount_cents,
  r.status,
  r.incident_on,
  -- The payee's id only once they're verified; the supporter's page then
  -- reads the name under the payees policy, and an unverified payee is
  -- unnamed and unlinked — a boolean about the request, not about the payee.
  case exists (select 1 from public.payees p where p.id = r.payee_id and p.status = 'verified')
    then r.payee_id end as payee_id
from public.requests r
where public.is_supporter(r.id);

-- New relations carry no grants: authenticated only (the service bypasses
-- RLS on the tables themselves; nothing reads this view from the server).
grant select on public.support_requests to authenticated;
