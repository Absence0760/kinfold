-- Cover terms (roadmap 2a/2b, followups: "Cover terms the design needs aren't
-- in the schema"). The partner insurer files one broad group rate per vehicle
-- class and plan — a rate set by risk, never by earnings (state rating laws) —
-- and the difference between members is the PLAN, not a cap tied to income
-- (design.md: a lower cap tied to income would be unfair discrimination in
-- benefits). Numbers here are local stand-ins for the partner's filed rates and
-- need actuarial review before launch.

create type public.cover_plan as enum ('basic', 'standard');
create type public.vehicle_class as enum
  ('micro_car', 'sedan', 'suv', 'pickup', 'van');

-- Filed rates. A row change is a data change with a history row, like fund
-- settings; the plan order inside a class is checked below.
create table public.cover_plans (
  vehicle_class  public.vehicle_class not null,
  plan           public.cover_plan not null,
  premium_cents  bigint not null check (premium_cents > 0),
  cap_cents      bigint not null check (cap_cents > 0),
  filed_by       text not null check (filed_by ~ '^[a-z][a-z0-9_]{0,39}$'),
  filed_on       date not null,
  primary key (vehicle_class, plan)
);

create table private.cover_plans_history (
  id         bigint generated always as identity primary key,
  old_row    jsonb not null,
  changed_at timestamptz not null default now(),
  changed_by uuid
);

create function private.log_cover_plans_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into private.cover_plans_history (old_row, changed_by)
  values (to_jsonb(old), auth.uid());
  return new;
end $$;

create trigger cover_plans_history before update on public.cover_plans
  for each row execute function private.log_cover_plans_change();

-- The member's own plan. Any member may choose Basic or Standard.
create table public.cover_choices (
  member_id  uuid primary key references public.members (id) on delete cascade,
  plan       public.cover_plan not null,
  chosen_at  timestamptz not null default now()
);

alter table public.cover_plans enable row level security;
alter table public.cover_choices enable row level security;

create policy "read filed cover rates" on public.cover_plans
  for select to authenticated, anon using (true);

-- A member reads only their own plan row.
create policy "members read their plan" on public.cover_choices
  for select to authenticated
  using (member_id = auth.uid());

-- One row per member: the member may create their own plan row and change only
-- their own row (freshness rule like the repo's other owner writes).
create policy "members create their plan row" on public.cover_choices
  for insert to authenticated
  with check (member_id = auth.uid() and chosen_at = now());

create policy "members change their own plan" on public.cover_choices
  for update to authenticated
  using (member_id = auth.uid() and chosen_at = now())
  with check (member_id = auth.uid() and chosen_at = now());

-- The premium the cooperative pays for one covered vehicle of a class and plan.
create function public.premium_cents(p_class public.vehicle_class,
  p_plan public.cover_plan) returns bigint
language sql stable security definer set search_path = '' as $$
  select premium_cents from public.cover_plans
  where vehicle_class = p_class and plan = p_plan;
$$;

-- The plan a member runs: their own choice, else Basic (members below the dues
-- floor get Basic, fully paid by the cooperative).
create function public.member_plan(p_member uuid) returns public.cover_plan
language sql stable security definer set search_path = '' as $$
  select coalesce((select plan from public.cover_choices where member_id = p_member),
                  'basic'::public.cover_plan);
$$;

-- The cooperative's paid-in-full premium for one member's covered vehicle, read
-- as their plan and class. The dues side never calls this figure premium.
create function public.premium_for(p_member uuid, p_class public.vehicle_class)
returns bigint language sql stable security definer set search_path = '' as $$
  select premium_cents from public.cover_plans
  where vehicle_class = p_class and plan = public.member_plan(p_member);
$$;

-- Service only: a filed-rate change is the partner's, and it re-checks the plan
-- order so a rate change can't sell less cover for more premium.
create function public.set_cover_plan(p_class public.vehicle_class,
  p_plan public.cover_plan, p_premium bigint, p_cap bigint,
  p_filed_by text, p_filed_on date) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_other       public.cover_plans;
  v_has_other   boolean;
begin
  if not private.is_service() then
    raise exception 'filed rates are written by the service' using errcode = '42501';
  end if;
  if p_premium <= 0 or p_cap <= 0 then
    raise exception 'a filed rate and its cap must be positive' using errcode = '23514';
  end if;
  select * from public.cover_plans
  where vehicle_class = p_class and plan <> p_plan into v_other;
  v_has_other := v_other.premium_cents <> 0;
  if v_has_other
     and ((p_plan = 'standard'
           and (p_premium <= v_other.premium_cents or p_cap < v_other.cap_cents))
         or (p_plan = 'basic'
             and (p_premium >= v_other.premium_cents or p_cap > v_other.cap_cents))) then
    raise exception 'within a class the standard plan must pay more premium for at least as much cap'
      using errcode = '23514';
  end if;
  if exists (select 1 from public.cover_plans where vehicle_class = p_class and plan = p_plan) then
    update public.cover_plans
      set premium_cents = p_premium, cap_cents = p_cap,
          filed_by = p_filed_by, filed_on = p_filed_on
      where vehicle_class = p_class and plan = p_plan;
  else
    insert into public.cover_plans
      (vehicle_class, plan, premium_cents, cap_cents, filed_by, filed_on)
      values (p_class, p_plan, p_premium, p_cap, p_filed_by, p_filed_on);
  end if;
  perform private.audit('cover_plans.filed', 'cover_plans', NULL,
    jsonb_build_object('vehicle_class', p_class, 'plan', p_plan,
                       'premium_cents', p_premium, 'cap_cents', p_cap));
end $$;

-- Members may choose their plan, not the insurer's rates.
create function public.set_my_plan(p_plan public.cover_plan) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'the member''s plan is chosen by a signed-in member' using errcode = '42501';
  end if;
  if exists (select 1 from public.cover_choices where member_id = auth.uid()) then
    update public.cover_choices set plan = p_plan, chosen_at = now()
    where member_id = auth.uid();
  else
    insert into public.cover_choices (member_id, plan) values (auth.uid(), p_plan);
  end if;
  perform private.audit('cover_choices.set', 'cover_choices', auth.uid(),
    jsonb_build_object('plan', p_plan));
end $$;

-- Seeded filed rates (stand-ins pending actuarial review): Basic and Standard
-- per class, Standard always the pricier plan.
insert into public.cover_plans values
  ('micro_car', 'basic',    9900,  50000, 'partner_insurer', '2026-01-01'::date),
  ('micro_car', 'standard', 14900, 100000, 'partner_insurer', '2026-01-01'::date),
  ('sedan',     'basic',   12900,  50000, 'partner_insurer', '2026-01-01'::date),
  ('sedan',     'standard', 18900, 100000, 'partner_insurer', '2026-01-01'::date),
  ('suv',       'basic',   15900,  50000, 'partner_insurer', '2026-01-01'::date),
  ('suv',       'standard', 22900, 100000, 'partner_insurer', '2026-01-01'::date),
  ('pickup',    'basic',   16900,  50000, 'partner_insurer', '2026-01-01'::date),
  ('pickup',    'standard', 24900, 100000, 'partner_insurer', '2026-01-01'::date),
  ('van',       'basic',   18900,  50000, 'partner_insurer', '2026-01-01'::date),
  ('van',       'standard', 26900, 100000, 'partner_insurer', '2026-01-01'::date);

revoke all from function public.premium_cents(public.vehicle_class, public.cover_plan);
revoke all from function public.premium_cents(public.vehicle_class, public.cover_plan)
  to public, anon, authenticated;
grant execute on function public.premium_cents(public.vehicle_class, public.cover_plan)
  to authenticated, anon;

revoke all from function public.member_plan(uuid);
revoke all from function public.member_plan(uuid) to public, anon, authenticated;
grant execute on function public.member_plan(uuid) to authenticated, anon;

revoke all from function public.premium_for(uuid, public.vehicle_class);
revoke all from function public.premium_for(uuid, public.vehicle_class)
  to public, anon, authenticated;
grant execute on function public.premium_for(uuid, public.vehicle_class)
  to authenticated, anon;

revoke all from function public.set_cover_plan(public.vehicle_class, public.cover_plan, bigint, bigint, text, date);
revoke all from function public.set_cover_plan(public.vehicle_class, public.cover_plan, bigint, bigint, text, date)
  to public, anon, authenticated;
grant execute on function public.set_cover_plan(public.vehicle_class, public.cover_plan, bigint, bigint, text, date)
  to service_role;

revoke all from function public.set_my_plan(public.cover_plan);
revoke all from function public.set_my_plan(public.cover_plan) to public, anon, authenticated;
grant execute on function public.set_my_plan(public.cover_plan) to authenticated;
