-- The ops console reads the trail (roadmap 1e): recent decisions and privileged
-- reads, newest first. The door answers action, target, target id and time —
-- never the raw `detail` jsonb (which carries PII-adjacent figures like amounts
-- and vendor references) and never the acting member's id: the console sees
-- THAT decisions happened, the reviews/appeals/claims tables say what they were.
-- Reviewers and admins can read the tail; members and the public cannot.
create function public.review_audit_tail(p_limit integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_found jsonb;
begin
  if not private.is_service() and not (
    exists (select 1 from public.member_roles
            where member_id = auth.uid() and role in ('reviewer', 'admin'))
  ) then
    raise exception 'the audit trail is read by the operations console'
      using errcode = '42501';
  end if;
  select coalesce((
    select jsonb_agg(
      jsonb_build_object('action', a.action, 'target', a.target,
                         'target_id', a.target_id, 'at', a.at)
      order by a.at desc
    )
    from private.audit_log a
    limit least(greatest(p_limit, 1), 100)
  ), '[]'::jsonb) into v_found;
  -- Reading the trail is itself on the trail, like every privileged read.
  perform private.audit('audit_log.read', 'audit_log', NULL,
    jsonb_build_object('limit', least(greatest(p_limit, 1), 100),
                       'count', jsonb_length(v_found)));
  return v_found;
end $$;

revoke all from function public.review_audit_tail(integer);
revoke all from function public.review_audit_tail(integer) to public, anon;
grant execute on function public.review_audit_tail(integer) to authenticated, service_role;
