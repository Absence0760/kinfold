-- The daily expire-requests job clears stale open and needs-evidence requests
-- (followups: nothing owned expiry, so a request nobody pledges or evidences
-- sat on the board forever). The transition itself gets a guarded owner:
-- expiry is the service's, it only moves requests that can still be stale,
-- and the payout guard in …120500 keeps money with the payee a person's to
-- handle. Releasing pledges and cancelling unsigned loans is the existing
-- close trigger's job — expiry goes through the same path as withdraw.

create function public.expire_request(p_request uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  r public.requests;
begin
  if not private.is_service() then
    raise exception 'expiry is run by the service' using errcode = '42501';
  end if;
  select * into r from public.requests where id = p_request for update;
  if r.id is null or r.status not in ('open', 'needs_evidence') then
    raise exception 'request not found, or not open or still needing evidence' using errcode = 'P0002';
  end if;
  -- Money with the payee stops the write with the guard's own exception
  -- (…120500): the job skips such requests, a person decides.
  update public.requests set status = 'expired' where id = p_request;
  perform private.audit('request.expired', 'requests', p_request,
                        jsonb_build_object('was', r.status));
end $$;

-- New relations carry Supabase's default grants: take them back, then the
-- service alone may expire a request — a member withdraws their own instead.
revoke all from function public.expire_request(uuid);
revoke all from function public.expire_request(uuid) to public, anon, authenticated;
grant execute on function public.expire_request(uuid) to service_role;
