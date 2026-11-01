-- VYORA public video storage bucket and owner-scoped uploads.
-- Run this file in the Supabase SQL Editor.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('videos', 'videos', true, 209715200, array['video/mp4','video/webm','video/quicktime'])
on conflict (id) do update set public = true, file_size_limit = 209715200, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "VYORA videos are publicly readable" on storage.objects;
create policy "VYORA videos are publicly readable" on storage.objects
for select using (bucket_id = 'videos');

drop policy if exists "VYORA users upload to own folder" on storage.objects;
create policy "VYORA users upload to own folder" on storage.objects
for insert to authenticated
with check (bucket_id = 'videos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "VYORA users delete own files" on storage.objects;
create policy "VYORA users delete own files" on storage.objects
for delete to authenticated
using (bucket_id = 'videos' and (storage.foldername(name))[1] = auth.uid()::text);
