-- Insured cover records what the partner insurer paid (design.md: a covered
-- claim is paid in full, LESS the member's share, to the shop, within the
-- state's deadline; the score decides speed and scrutiny, never the amount;
-- denials only by a person, with appeal). The partner's claims feed writes
-- through `record_claim` (service only, keyed by the partner's reference so
-- a replayed feed is a no-op); the member's share can never exceed the
-- claim, and `paid_cents` is exactly what the shop got.

create type public.claim_status as enum ('recorded', 'paid', 'denied');

create table public.claims (
  id                 uuid primary key default gen_random_uuid(),
  request_id         uuid not null references public.requests (id) on delete cascade,
  partner_ref        text not null unique,
  gross_cents        bigint not null check (gross_cents > 0),
  member_share_cents bigint not null check (member_share_cents >= 0),
  paid_cents         bigint not null check (paid_cents >= 0),
  status             public.claim_status not null default 'recorded',
  deadline           date,
  reason             text,
  decided_by         uuid references public.members (id),
  decided_at         timestamptz,
  recorded_at        timestamptz not null default now(),
  check (member_share_cents <= gross_cents),
  check (paid_cents = gross_cents - member_share_cents)
);

alter table public.claims enable row level security;

create policy "owners read claims on their requests" on public.claims for select to authenticated
  using (exists (select 1 from public.requests r where r.id = request_id and r.member_id = auth.uid()));

create function public.record_claim(
  p_request uuid, p_partner_ref text, p_gross_cents bigint, p_member_share_cents bigint
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not private.is_service() then
    raise exception 'claims are recorded by the partner''s feed, in the service' using errcode = '42501';
  end if;
  if not exists (select 1 from public.requests where id = p_request) then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if p_partner_ref is null or p_partner_ref = '' then
    raise exception 'a claim needs the partner''s reference' using errcode = '23514';
  end if;
  -- A replayed feed entry is a no-op: the reference is unique.
  if exists (select 1 from public.claims where partner_ref = p_partner_ref) then
    return (select id from public.claims where partner_ref = p_partner_ref);
  end if;
  insert into public.claims (request_id, partner_ref, gross_cents, member_share_cents)
  values (p_request, p_partner_ref, p_gross_cents, p_member_share_cents)
  returning id into v_id;
  perform private.audit('claim.recorded', 'claims', v_id,
                        jsonb_build_object('partner_ref', p_partner_ref, 'request_id', p_request));
  return v_id;
end $$;

-- A denial is a person's decision, and it must follow a recorded refuse
-- review — the same all-or-nothing rule the request status guard uses.
create function public.deny_claim(p_claim uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_request uuid;
begin
  update public.claims set status = 'denied', reason = p_reason, decided_by = auth.uid(), decided_at = now()
  where id = p_claim and status = 'recorded'
  returning request_id into v_request;
  if v_request is null then
    raise exception 'claim not found or already decided' using errcode = 'P0002';
  end if;
  if not exists (
    select 1 from public.reviews where request_id = v_request and decision = 'refuse' and created_at = now()
  ) then
    raise exception 'only a reviewer''s recorded decision can deny a claim' using errcode = '42501';
  end if;
  perform private.audit('claim.denied', 'claims', p_claim, jsonb_build_object('reason', p_reason));
end $$;

grant select on public.claims to authenticated;
grant select, insert, update on public.claims to service_role;
grant execute on function public.deny_claim(uuid, text) to authenticated;
grant execute on function
  public.record_claim(uuid, text, bigint, bigint), public.deny_claim(uuid, text)
to service_role;
