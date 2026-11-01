-- record_score: a fund with no fund_settings row now routes on the documented
-- default minimum of 70 (docs/design.md: below 70 means "needs more evidence").
--
-- Before, `select coalesce(min_score, 70) into v_min from fund_settings ...`
-- left v_min NULL when the row was missing (coalesce never runs on zero rows),
-- and `p_score < NULL` is not true, so every score went straight to `open` and
-- skipped the member reviewer. Defaulting fails safe: a low score still goes to
-- a person. Only the minimum lookup changes; grants and ownership are kept by
-- `create or replace`.

create or replace function public.record_score(
  p_request uuid, p_score smallint, p_reasons jsonb,
  p_model text, p_model_version text, p_prompt_version text, p_inputs_sha256 text
) returns public.request_status
language plpgsql security definer set search_path = '' as $$
declare
  r       public.requests;
  v_min   smallint;
  v_next  public.request_status;
begin
  select * into r from public.requests where id = p_request for update;
  if r.id is null then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if r.status <> 'scoring' then
    raise exception 'request is not waiting for a score' using errcode = '23514';
  end if;

  insert into public.scores (request_id, score, reasons, model, model_version, prompt_version, inputs_sha256)
  values (p_request, p_score, p_reasons, p_model, p_model_version, p_prompt_version, p_inputs_sha256);

  v_min := coalesce(
    (select min_score from public.fund_settings where fund = public.fund_for_kind(r.kind)),
    70);

  v_next := case
    when exists (select 1 from private.fraud_signals
                 where request_id = p_request and severity = 'high' and resolved_at is null) then 'in_review'
    when p_score < v_min then 'needs_evidence'
    else 'open'
  end;

  update public.requests set status = v_next, current_score = p_score where id = p_request;
  return v_next;
end $$;
