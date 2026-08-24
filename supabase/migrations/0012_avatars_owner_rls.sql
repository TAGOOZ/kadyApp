-- 0012_avatars_owner_rls.sql — tighten avatars bucket to owner folder
-- Replaces overly broad avatars_authenticated_write (bucket only) with folder check.
-- Original 0010 policy allowed any authenticated user to write any avatars/* path.
-- Fix: (storage.foldername(name))[1] = auth.uid()::text (or string_to_array fallback).
-- Bucket stays public:true for getPublicUrl.

do $storage$
begin
  -- Drop the broad policy if exists
  if exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='avatars_authenticated_write') then
    drop policy avatars_authenticated_write on storage.objects;
  end if;

  -- Recreate as owner-only: (storage.foldername(name))[1] = auth.uid()::text
  -- Use storage.foldername when available, fallback to string_to_array.
  if exists (select 1 from pg_proc where proname = 'foldername' and pronamespace = (select oid from pg_namespace where nspname='storage')) then
    execute 'create policy avatars_authenticated_write on storage.objects '
      || 'for all to authenticated '
      || 'using (bucket_id = ''avatars'' and (storage.foldername(name))[1] = auth.uid()::text) '
      || 'with check (bucket_id = ''avatars'' and (storage.foldername(name))[1] = auth.uid()::text)';
  else
    execute 'create policy avatars_authenticated_write on storage.objects '
      || 'for all to authenticated '
      || 'using (bucket_id = ''avatars'' and (string_to_array(name, ''/''))[1] = auth.uid()::text) '
      || 'with check (bucket_id = ''avatars'' and (string_to_array(name, ''/''))[1] = auth.uid()::text)';
  end if;
end
$storage$;

-- Optional hardening: bucket limits (best-effort, column may not exist on all Supabase versions)
do $bucket$
begin
  -- file_size_limit (bytes) — 2 MiB
  if exists (select 1 from information_schema.columns where table_schema='storage' and table_name='buckets' and column_name='file_size_limit') then
    update storage.buckets set file_size_limit = 2097152 where id='avatars';
  end if;
  -- allowed_mime_types — restrict to images
  if exists (select 1 from information_schema.columns where table_schema='storage' and table_name='buckets' and column_name='allowed_mime_types') then
    update storage.buckets set allowed_mime_types = array['image/jpeg','image/png','image/webp'] where id='avatars';
  end if;
end
$bucket$;

-- Keep public read as is: avatars_public_read on storage.objects for select to public using (bucket_id='avatars')
