-- Evidence bucket limits (20261102290000_evidence_limits.sql).
--
-- Properties this file pins: both evidence buckets declare their accepted
-- file types and a 20 MB size limit, so the server — not only the web app —
-- refuses anything else. (The columns are Supabase's storage schema; this
-- file fails loudly at CI if a column name is wrong.)
begin;
select plan(4);

select is((select file_size_limit from storage.buckets where name = 'evidence-original'),
  20971520::bigint, 'the originals bucket caps uploads at 20 MB');
select ok((select count(*) from storage.buckets
           where name = 'evidence-original'
             and allowed_mime_types is not null
             and 'image/jpeg' = any (allowed_mime_types)
             and 'application/pdf' = any (allowed_mime_types)) = 1::bigint,
  'the originals bucket accepts only photos, clips and documents');
select is((select file_size_limit from storage.buckets where name = 'evidence-redacted'),
  20971520::bigint, 'the redacted bucket caps uploads at 20 MB too');
select is((select count(*)
           from storage.buckets b
           where b.allowed_mime_types is not null and b.file_size_limit is not null),
  2::bigint, 'both evidence buckets carry limits — no unbounded bucket');
