-- In-person inspection (roadmap 2f: large requests get an in-person shop inspection).
-- A big request is money the pool will move, so a person the partner sends visits
-- the shop and reports what they found. The database makes the rule: a request at
-- or above its fund's large-amount line cannot become funded or paid until an
-- inspection reports it clear. Nothing here decides the visit's outcome — the
-- partner's statement does — but nothing large can skip the visit.

create type public.inspection_result as enum ('clear', 'issue_found', 'inconclusive');

create table public.inspections (
  id             uuid primary key default gen_random_uuid(),
  request_id     uuid not null references public.requests (id) on delete cascade,
  result         public.inspection_result not null,
  inspector_ref  text not null unique,
  inspected_at   timestamptz not null default now(),
  note           text check (note is null or length(note) <= 500)
);

create index inspections_request on public.inspections (request_id);

create trigger inspections_append_only before update or delete
  on public.inspections for each row execute function private.forbid_change();

alter table public.inspections enable row level security;

-- The large-amount line per fund: at or above it, an in-person inspection is
-- required before the money moves. Kept in fund_settings so the partner can
-- move it with their fee economics; the lines still need review.
alter table public.fund_settings
  add column inspection_min_cents bigint not null default 5000000 check (inspection_min_cents > 0);

update public.fund_settings set inspection_min_cents = 5000000 where fund = 'protection';
update public.fund_settings set inspection_min_cents = 10000000 where fund = 'home_fund';

-- What the requester and the reviewers they may review read back.
create policy "requesters read inspections of their requests" on public.inspections
  for select to authenticated
  using (exists (select 1 from public.requests r where r.id = request_id and r.member_id = auth.uid()));

create policy "reviewers read inspections of reviewable requests" on public.inspections
  for select to authenticated
  using (private.may_review(request_id, auth.uid()));

grant select on public.inspections to authenticated;

-- Whether this request's amount reaches its fund's large-amount line.
create function public.needs_inspection(p_request uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.fund_settings s
                 where s.fund = public.fund_for_kind(r.kind)
                 and r.amount_cents >= s.inspection_min_cents)
  from public.requests r where r.id = p_request limit 1;
$$;

-- A large request cannot become funded or paid without a clear inspection. Money
-- is never half-held: the request stays short until a person reports what they
-- found, so a replayed status change can't sneak past the visit.
create function private.require_clear_inspection() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status in ('funded', 'paid')
     and public.needs_inspection(new.id)
     and not exists (select 1 from public.inspections
                     where request_id = new.id and result = 'clear') then
    raise exception 'a large request needs a clear in-person inspection before money moves'
      using errcode = '23514';
  end if;
  return new;
end $$;

create trigger require_clear_inspection before update on public.requests
  for each row execute function private.require_clear_inspection();

-- Service only: the partner's inspection statement. The same reference twice is
-- a no-op, so a retried webhook never records the same visit twice.
create function public.record_inspection(
  p_request uuid, p_result public.inspection_result, p_inspector_ref text,
  p_note text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not private.is_service() then
    raise exception 'inspections are recorded by the service' using errcode = '42501';
  end if;
  if p_inspector_ref is null or p_inspector_ref = '' then
    raise exception 'an inspection needs the inspector''s reference' using errcode = '23514';
  end if;
  if exists (select 1 from public.inspections where inspector_ref = p_inspector_ref) then
    return (select id from public.inspections where inspector_ref = p_inspector_ref);
  end if;
  if not exists (select 1 from public.requests where id = p_request) then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  insert into public.inspections
    (request_id, result, inspector_ref, note)
    values (p_request, p_result, p_inspector_ref, p_note)
    returning id into v_id;
  perform private.audit('inspection.recorded', 'inspections', v_id,
    jsonb_build_object('request_id', p_request, 'result', p_result,
                       'inspector_ref', p_inspector_ref));
  return v_id;
end $$;

revoke all from function public.record_inspection(uuid, public.inspection_result, text, text);
revoke all from function public.record_inspection(uuid, public.inspection_result, text, text)
  to public, anon, authenticated;
grant execute on function public.record_inspection(uuid, public.inspection_result, text, text)
  to service_role;
