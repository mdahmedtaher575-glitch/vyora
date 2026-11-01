-- VYORA extended platform foundation.
-- Run after schema.sql in the Supabase SQL Editor.

create table if not exists public.watch_history (
  user_id uuid not null references auth.users(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  watched_at timestamptz not null default now(),
  progress_seconds integer not null default 0 check (progress_seconds >= 0),
  primary key (user_id, video_id)
);
create index if not exists watch_history_user_recent_idx on public.watch_history(user_id, watched_at desc);

create table if not exists public.video_bookmarks (
  user_id uuid not null references auth.users(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, video_id)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  kind text not null check (kind in ('new_video','new_subscriber','comment','reply','premiere','system')),
  message text not null,
  target_url text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_recent_idx on public.notifications(user_id, created_at desc);

create table if not exists public.scheduled_premieres (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  video_id uuid references public.videos(id) on delete set null,
  title text not null check (char_length(title) between 1 and 200),
  starts_at timestamptz not null,
  reminder_enabled boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists scheduled_premieres_starts_idx on public.scheduled_premieres(starts_at);

create table if not exists public.video_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  reason text not null check (reason in ('spam','misleading','harassment','copyright','other')),
  details text not null default '',
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now(),
  unique (reporter_id, video_id)
);

alter table public.watch_history enable row level security;
alter table public.video_bookmarks enable row level security;
alter table public.notifications enable row level security;
alter table public.scheduled_premieres enable row level security;
alter table public.video_reports enable row level security;

drop policy if exists "Users manage own watch history" on public.watch_history;
create policy "Users manage own watch history" on public.watch_history
for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users manage own bookmarks" on public.video_bookmarks;
create policy "Users manage own bookmarks" on public.video_bookmarks
for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users read own notifications" on public.notifications;
create policy "Users read own notifications" on public.notifications
for select to authenticated using (auth.uid() = user_id);
drop policy if exists "Users update own notifications" on public.notifications;
create policy "Users update own notifications" on public.notifications
for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Premieres are publicly visible" on public.scheduled_premieres;
create policy "Premieres are publicly visible" on public.scheduled_premieres
for select using (true);
drop policy if exists "Channel owners manage premieres" on public.scheduled_premieres;
create policy "Channel owners manage premieres" on public.scheduled_premieres
for all to authenticated using (
  exists (select 1 from public.channels c where c.id = channel_id and c.owner_id = auth.uid())
) with check (
  exists (select 1 from public.channels c where c.id = channel_id and c.owner_id = auth.uid())
);

drop policy if exists "Users create their own video reports" on public.video_reports;
create policy "Users create their own video reports" on public.video_reports
for insert to authenticated with check (auth.uid() = reporter_id);
drop policy if exists "Users view their own video reports" on public.video_reports;
create policy "Users view their own video reports" on public.video_reports
for select to authenticated using (auth.uid() = reporter_id);
