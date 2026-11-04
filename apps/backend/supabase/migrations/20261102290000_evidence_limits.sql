-- Evidence uploads are checked by the web app, not the server (followup):
-- a direct API call could put any file type or size in the bucket. Supabase's
-- storage schema enforces these at the bucket: `allowed_mime_types` and
-- `file_size_limit` on `storage.buckets`. The set is what evidence can be:
-- damage photos, short damage clips, invoices/contracts/statements. 20 MB
-- covers a phone video clip; anything bigger is not evidence.

update storage.buckets
  set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp',
                                 'video/quicktime', 'video/mp4', 'application/pdf'],
      file_size_limit = 20971520
  where name = 'evidence-original';

update storage.buckets
  set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp',
                                 'video/quicktime', 'video/mp4', 'application/pdf'],
      file_size_limit = 20971520
  where name = 'evidence-redacted';
