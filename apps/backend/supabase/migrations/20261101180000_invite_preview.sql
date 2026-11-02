-- Invites: what the invite page needs before and after the click (roadmap step
-- 1f).
--
--   * an invitee who hasn't opened the link yet can see what they are being
--     invited to — the owner's name, the title, kind, amount and status — so
--     accepting isn't a leap of faith. The token is the secret: it's looked up
--     by hash, and nothing about the invite is readable without it;
--   * an owner can cancel a link they handed out, which is the difference
--     between "one more person can join" and "this one is done with";
--   * accepting with a token whose link was cancelled, used or expired says so,
--     and accepting with an account that was never finished says "finish
--     setting up your account" instead of failing on a foreign key;
--   * the owner and each supporter learn the names of the people they are
--     connected to. Names stay inside that pair: a supporter doesn't collect
--     the other supporters' identities, and nobody reads the `members` row.

-- --- 1. a link can be handed back ---------------------------------------------------

alter table public.request_invites
  add column revoked_at timestamptz;

create function public.revoke_invite(p_invite uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  r public.request_invites;
begin
  select * into r from public.request_invites where id = p_invite for update;
  if r.id is null or not exists (select 1 from public.requests where id = r.request_id
                                 and member_id = auth.uid()) then
    raise exception 'invite not found' using errcode = 'P0002';
  end if;
  -- An accepted link already did what it was for: it stays in the record,
  -- and the supporter's own exit is their own choice.
  if r.accepted_at is not null or r.revoked_at is not null then
    raise exception 'the link was already used or cancelled' using errcode = '23514';
  end if;
  update public.request_invites set revoked_at = now() where id = p_invite;
  perform private.audit('invite.revoked', 'request_invites', p_invite);
end $$;

-- --- 2. accepting: the readable answers, and no link reuse -------------------------

-- Rewritten from the funding migration's version with two changes: a cancelled
-- link no longer accepts, and a caller without a member row is told what to do
-- rather than failing on the foreign key into `members`.
create or replace function public.accept_invite(p_token text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  i public.request_invites;
begin
  select * into i from public.request_invites
  where token_sha256 = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and accepted_at is null and revoked_at is null and expires_at > now()
  for update;
  if i.id is null then
    raise exception 'invite not found, used or expired' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.members where id = auth.uid()) then
    raise exception 'finish setting up your account' using errcode = '42501';
  end if;
  if exists (select 1 from public.requests where id = i.request_id and member_id = auth.uid()) then
    raise exception 'you cannot accept an invite to your own request' using errcode = '42501';
  end if;
  update public.request_invites set accepted_by = auth.uid(), accepted_at = now() where id = i.id;
  insert into public.request_supporters (request_id, member_id, relationship)
  values (i.request_id, auth.uid(), i.relationship)
  on conflict do nothing;
  return i.request_id;
end $$;

-- --- 3. the invite page before the click -------------------------------------------

-- One lookup, one answer. `accept_invite` still checks everything; this only
-- says what the member is about to join, and the token never leaves the
-- request: the owner behind it is named because the invitee needs to know
-- who they are helping. The read is written down like other PII reads.
create function public.invite_preview(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r public.request_invites;
  q public.requests;
  v_owner text;
begin
  select * into r from public.request_invites
  where token_sha256 = encode(extensions.digest(p_token, 'sha256'), 'hex');
  if r.id is null or r.accepted_at is not null or r.revoked_at is not null then
    raise exception 'invite not found' using errcode = 'P0002';
  end if;
  select * into q from public.requests where id = r.request_id;
  if q.id is null then
    raise exception 'invite not found' using errcode = 'P0002';
  end if;
  v_owner := (select display_name from public.members where id = q.member_id);
  if v_owner is null then
    raise exception 'invite not found' using errcode = 'P0002';
  end if;
  perform private.audit('invite.preview', 'request_invites', r.id);
  return jsonb_build_object(
    'request_id', q.id,
    'owner_name', v_owner,
    'title', q.title,
    'kind', q.kind::text,
    'funding', q.funding::text,
    'amount_cents', q.amount_cents,
    'status', q.status::text,
    'relationship', r.relationship,
    'expires_at', r.expires_at
  );
end $$;

-- --- 4. the names on both sides of an invite ---------------------------------------

-- The pair sees each other, and nothing else. `is_supporter` is the existing
-- rule for "this member backs that request".
create function public.request_names(p_request uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  q public.requests;
  v_owner text;
  v_me boolean;
  v_them boolean;
  v_rows jsonb = '[]';
begin
  select * into q from public.requests where id = p_request;
  if q.id is null then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  v_me := exists (select 1 from public.request_supporters
                  where request_id = p_request and member_id = auth.uid());
  v_them := q.member_id = auth.uid();
  if not (v_me or v_them) then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  v_owner := (select display_name from public.members where id = q.member_id);
  -- The owner sees the people they invited, and what each said they are. A
  -- supporter sees only the owner, so their own entry stays out of the list.
  if v_them then
    select coalesce(
      (select jsonb_agg(o) from (
         select jsonb_build_object(
           'member_id', sup.member_id,
           'name', coalesce((select display_name from public.members m where m.id = sup.member_id), 'Member'),
           'relationship', sup.relationship,
           'joined_at', sup.joined_at
         ) as o
         from public.request_supporters sup
         where sup.request_id = p_request
         order by sup.joined_at
       ) lines),
      '[]'::jsonb
    ) into v_rows;
  end if;
  return jsonb_build_object(
    'owner_name', v_owner,
    'me_name', case when v_me then (select display_name from public.members where id = auth.uid()) end,
    'supporters', v_rows
  );
end $$;

-- --- grants ---------------------------------------------------------------------

grant execute on function
  public.revoke_invite(uuid), public.invite_preview(text), public.request_names(uuid)
to authenticated;
-- The cancelled state has to be readable by the owner, or the panel couldn't
-- tell its own links apart. Everything else about an invite stays as granted.
grant select (revoked_at) on public.request_invites to authenticated;
