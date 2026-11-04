-- Fraud signals are found by the checks (`fraud-checks`) and stored in the
-- private schema so members never see them. But the operations console
-- (roadmap 1e) is meant to show reviewers what the checks found — and today
-- nothing in the schema lets a reviewer read them. This door answers with
-- what a reviewer needs to decide the request: kind and severity, high-
-- severity findings first. The raw `detail` jsonb (photo hashes, cross-
-- reference ids) never crosses into the response: a reviewer sees THAT a
-- pattern was found, not HOW the checks match, so a reviewer cannot reverse-
-- engineer which photo or shop the checks keyed on. No table policy: the
-- function below re-checks the role and audits every look, and the private
-- table keeps its no-raw-reads default — the console goes through the door.
create function public.review_fraud_signals(p_request uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_found jsonb;
begin
  if not private.is_service() and not (
    exists (select 1 from public.member_roles
            where member_id = auth.uid() and role in ('reviewer', 'admin'))
  ) then
    raise exception 'fraud signals are read by the operations console'
      using errcode = '42501';
  end if;
  select coalesce((
    select jsonb_agg(jsonb_build_object('kind', s.kind, 'severity', s.severity))
    from private.fraud_signals s
    where s.request_id = p_request and s.resolved_at is null
    order by (s.severity = 'high') desc, created_at desc
  ), '[]'::jsonb) into v_found;
  -- A PII-adjacent read: every look at a member's fraud standing is on the
  -- trail, like every other privileged read in the repo.
  perform private.audit('fraud_signals.read', 'fraud_signals', p_request,
    jsonb_build_object('count', jsonb_length(v_found)));
  return v_found;
end $$;

revoke all on function public.review_fraud_signals(uuid) from public, anon;
grant execute on function public.review_fraud_signals(uuid) to authenticated, service_role;
