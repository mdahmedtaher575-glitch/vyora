-- VYORA database foundation (Supabase PostgreSQL)
-- Run this file in Supabase SQL Editor. It is safe to run once on a new project.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  display_name text not null default 'VYORA Creator',
  avatar_url text,
  bio text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint username_format check (username is null or username ~ '^[a-zA-Z0-9_]{3,24}$')
);

create table if not exists public.channels (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references auth.users(id) on delete cascade,
  handle text not null unique,
  name text not null,
  description text not null default '',
  avatar_url text,
  banner_url text,
  created_at timestamptz not null default now(),
  constraint channel_handle_format check (handle ~ '^[a-zA-Z0-9_]{3,30}$')
);

create table if not exists public.videos (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  title text not null,
  description text not null default '',
  video_url text,
  thumbnail_url text,
  category text not null default 'Entertainment',
  visibility text not null default 'public' check (visibility in ('public','unlisted','private','draft')),
  processing_status text not null default 'pending' check (processing_status in ('pending','ready','failed')),
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  views_count bigint not null default 0 check (views_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.subscriptions (
  subscriber_id uuid not null references auth.users(id) on delete cascade,
  channel_id uuid not null references public.channels(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (subscriber_id, channel_id),
  constraint no_self_subscription check (
    subscriber_id <> (select owner_id from public.channels where id = channel_id)
  )
);

create table if not exists public.video_likes (
  user_id uuid not null references auth.users(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  reaction text not null default 'like' check (reaction in ('like','dislike')),
  created_at timestamptz not null default now(),
  primary key (user_id, video_id)
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  video_id uuid not null references public.videos(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  parent_id uuid references public.comments(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 3000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.playlists (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 100),
  description text not null default '',
  is_public boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.playlist_videos (
  playlist_id uuid not null references public.playlists(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  position integer not null default 0,
  added_at timestamptz not null default now(),
  primary key (playlist_id, video_id)
);

create table if not exists public.community_posts (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 5000),
  post_type text not null default 'text' check (post_type in ('text','poll')),
  created_at timestamptz not null default now()
);

create table if not exists public.poll_options (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.community_posts(id) on delete cascade,
  option_text text not null check (char_length(option_text) between 1 and 200),
  position integer not null default 0
);

create table if not exists public.poll_votes (
  option_id uuid not null references public.poll_options(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (option_id, user_id)
);

create index if not exists videos_channel_created_idx on public.videos(channel_id, created_at desc);
create index if not exists videos_public_created_idx on public.videos(created_at desc) where visibility = 'public' and processing_status = 'ready';
create index if not exists comments_video_created_idx on public.comments(video_id, created_at desc);
create index if not exists subscriptions_channel_idx on public.subscriptions(channel_id);
create index if not exists community_posts_channel_created_idx on public.community_posts(channel_id, created_at desc);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  base_name text;
  safe_handle text;
begin
  base_name := coalesce(nullif(split_part(new.email, '@', 1), ''), 'creator');
  safe_handle := lower(regexp_replace(base_name, '[^a-zA-Z0-9_]', '', 'g'));
  if length(safe_handle) < 3 then safe_handle := 'user' || substr(new.id::text, 1, 8); end if;

  insert into public.profiles (id, username, display_name)
  values (new.id, safe_handle || '_' || substr(new.id::text, 1, 6), base_name)
  on conflict (id) do nothing;

  insert into public.channels (owner_id, handle, name)
  values (new.id, safe_handle || '_' || substr(new.id::text, 1, 6), base_name || '''s Channel')
  on conflict (owner_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_vyora on auth.users;
create trigger on_auth_user_created_vyora
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.channels enable row level security;
alter table public.videos enable row level security;
alter table public.subscriptions enable row level security;
alter table public.video_likes enable row level security;
alter table public.comments enable row level security;
alter table public.playlists enable row level security;
alter table public.playlist_videos enable row level security;
alter table public.community_posts enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;

-- Profiles: public read; only the owner can change their profile.
drop policy if exists "Profiles are viewable by everyone" on public.profiles;
create policy "Profiles are viewable by everyone" on public.profiles for select using (true);
drop policy if exists "Users update their own profile" on public.profiles;
create policy "Users update their own profile" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- Channels: public read; owners create/update/delete their own channel.
drop policy if exists "Channels are viewable by everyone" on public.channels;
create policy "Channels are viewable by everyone" on public.channels for select using (true);
drop policy if exists "Owners create their channel" on public.channels;
create policy "Owners create their channel" on public.channels for insert to authenticated with check (auth.uid() = owner_id);
drop policy if exists "Owners update their channel" on public.channels;
create policy "Owners update their channel" on public.channels for update to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
drop policy if exists "Owners delete their channel" on public.channels;
create policy "Owners delete their channel" on public.channels for delete to authenticated using (auth.uid() = owner_id);

-- Videos: everyone can see public, unlisted videos; owners can see/manage all their own videos.
drop policy if exists "Public can view public and unlisted videos" on public.videos;
create policy "Public can view public and unlisted videos" on public.videos for select using (
  (visibility in ('public','unlisted') and processing_status = 'ready')
  or exists (select 1 from public.channels c where c.id = channel_id and c.owner_id = auth.uid())
);
drop policy if exists "Channel owners create videos" on public.videos;
create policy "Channel owners create videos" on public.videos for insert to authenticated with check (
  exists (select 1 from public.channels c where c.id = channel_id and c.owner_id = auth.uid())
);
drop policy if exists "Channel owners update videos" on public.videos;
create policy "Channel owners update videos" on public.videos for update to authenticated using (
  exists (select 1 from public.channels c where c.id = channel_id and c.owner_id = auth.uid())
) with check (
  exists (select 1 from public.channels c where c.id = channel_id and c.owner_id = auth.uid())
);
drop policy if exists "Channel owners delete videos" on public.videos;
create policy "Channel owners delete videos" on public.videos for delete to authenticated using (
  exists (select 1 from public.channels c where c.id = channel_id and c.owner_id = auth.uid())
);

-- Subscriptions: visible to everyone; a user manages only their own subscriptions.
drop policy if exists "Subscriptions are viewable by everyone" on public.subscriptions;
create policy "Subscriptions are viewable by everyone" on public.subscriptions for select using (true);
drop policy if exists "Users subscribe as themselves" on public.subscriptions;
create policy "Users subscribe as themselves" on public.subscriptions for insert to authenticated with check (
  auth.uid() = subscriber_id and not exists (
    select 1 from public.channels c where c.id = channel_id and c.owner_id = auth.uid()
  )
);
drop policy if exists "Users unsubscribe as themselves" on public.subscriptions;
create policy "Users unsubscribe as themselves" on public.subscriptions for delete to authenticated using (auth.uid() = subscriber_id);

-- Likes: counts can be queried publicly; only the signed-in owner manages their reaction.
drop policy if exists "Likes are viewable by everyone" on public.video_likes;
create policy "Likes are viewable by everyone" on public.video_likes for select using (true);
drop policy if exists "Users add their own reaction" on public.video_likes;
create policy "Users add their own reaction" on public.video_likes for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users update their own reaction" on public.video_likes;
create policy "Users update their own reaction" on public.video_likes for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users remove their own reaction" on public.video_likes;
create policy "Users remove their own reaction" on public.video_likes for delete to authenticated using (auth.uid() = user_id);

-- Comments: public read; signed-in users create; only authors delete/update.
drop policy if exists "Comments are viewable by everyone" on public.comments;
create policy "Comments are viewable by everyone" on public.comments for select using (true);
drop policy if exists "Signed-in users create comments" on public.comments;
create policy "Signed-in users create comments" on public.comments for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Authors update comments" on public.comments;
create policy "Authors update comments" on public.comments for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Authors delete comments" on public.comments;
create policy "Authors delete comments" on public.comments for delete to authenticated using (auth.uid() = user_id);

-- Playlists: public playlists readable by all; private playlists by owner only.
drop policy if exists "Public playlists and own playlists are viewable" on public.playlists;
create policy "Public playlists and own playlists are viewable" on public.playlists for select using (is_public or auth.uid() = owner_id);
drop policy if exists "Users create own playlists" on public.playlists;
create policy "Users create own playlists" on public.playlists for insert to authenticated with check (auth.uid() = owner_id);
drop policy if exists "Users update own playlists" on public.playlists;
create policy "Users update own playlists" on public.playlists for update to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
drop policy if exists "Users delete own playlists" on public.playlists;
create policy "Users delete own playlists" on public.playlists for delete to authenticated using (auth.uid() = owner_id);

drop policy if exists "Playlist items visible when playlist is visible" on public.playlist_videos;
create policy "Playlist items visible when playlist is visible" on public.playlist_videos for select using (
  exists (select 1 from public.playlists p where p.id = playlist_id and (p.is_public or p.owner_id = auth.uid()))
);
drop policy if exists "Playlist owners manage items" on public.playlist_videos;
create policy "Playlist owners manage items" on public.playlist_videos for all to authenticated using (
  exists (select 1 from public.playlists p where p.id = playlist_id and p.owner_id = auth.uid())
) with check (
  exists (select 1 from public.playlists p where p.id = playlist_id and p.owner_id = auth.uid())
);

-- Community posts: public read; only channel owners create/update/delete.
drop policy if exists "Community posts are public" on public.community_posts;
create policy "Community posts are public" on public.community_posts for select using (true);
drop policy if exists "Channel owners manage community posts" on public.community_posts;
create policy "Channel owners manage community posts" on public.community_posts for all to authenticated using (
  exists (select 1 from public.channels c where c.id = channel_id and c.owner_id = auth.uid())
) with check (
  exists (select 1 from public.channels c where c.id = channel_id and c.owner_id = auth.uid())
);

drop policy if exists "Poll options are public" on public.poll_options;
create policy "Poll options are public" on public.poll_options for select using (true);
drop policy if exists "Channel owners manage poll options" on public.poll_options;
create policy "Channel owners manage poll options" on public.poll_options for all to authenticated using (
  exists (
    select 1 from public.community_posts p join public.channels c on c.id = p.channel_id
    where p.id = post_id and c.owner_id = auth.uid()
  )
) with check (
  exists (
    select 1 from public.community_posts p join public.channels c on c.id = p.channel_id
    where p.id = post_id and c.owner_id = auth.uid()
  )
);

drop policy if exists "Poll votes are viewable by everyone" on public.poll_votes;
create policy "Poll votes are viewable by everyone" on public.poll_votes for select using (true);
drop policy if exists "Users vote as themselves" on public.poll_votes;
create policy "Users vote as themselves" on public.poll_votes for insert to authenticated with check (
  auth.uid() = user_id and exists (
    select 1 from public.poll_options o
    join public.community_posts p on p.id = o.post_id
    where o.id = option_id and p.post_type = 'poll'
  )
);
drop policy if exists "Users remove their own poll vote" on public.poll_votes;
create policy "Users remove their own poll vote" on public.poll_votes for delete to authenticated using (auth.uid() = user_id);
