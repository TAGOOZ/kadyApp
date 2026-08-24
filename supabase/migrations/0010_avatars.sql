-- 0010_avatars.sql — P3 avatar (FEATURES §3.2 profile header).
-- Adds `customers.avatar_url` and public `avatars` bucket for profile photos
-- (image_picker → storage upload, CachedNetworkImage display).

alter table public.customers
  add column if not exists avatar_url text;

comment on column public.customers.avatar_url is
  'Public URL for profile avatar (Supabase Storage avatars/{user_id}/avatar.jpg).';

-- Storage: public bucket `avatars` — authenticated users may manage own avatar.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

do $storage$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'avatars_public_read'
  ) then
    create policy avatars_public_read on storage.objects
    for select to public
    using (bucket_id = 'avatars');
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'avatars_authenticated_write'
  ) then
    create policy avatars_authenticated_write on storage.objects
    for all to authenticated
    using (bucket_id = 'avatars')
    with check (bucket_id = 'avatars');
  end if;
end
$storage$;
