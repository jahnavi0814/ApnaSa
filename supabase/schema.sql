-- ApnaSa initial schema. Run in the Supabase SQL editor for a new project.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 48),
  bio text check (bio is null or char_length(bio) <= 160),
  college text check (college is null or char_length(college) <= 90),
  year text,
  avatar_url text,
  visibility boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.profile_interests (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  interest text not null check (char_length(interest) between 1 and 32),
  primary key (profile_id, interest)
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 100),
  description text check (description is null or char_length(description) <= 240),
  location text check (location is null or char_length(location) <= 100),
  starts_at timestamptz,
  code text not null unique check (code ~ '^[A-Z0-9]{4,12}$'),
  host_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.event_members (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 70),
  description text check (description is null or char_length(description) <= 180),
  interest text,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_user_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (reason in ('Inappropriate behaviour','Harassment or bullying','Impersonation','Something else')),
  details text check (details is null or char_length(details) <= 500),
  status text not null default 'open' check (status in ('open','reviewing','resolved')),
  created_at timestamptz not null default now(),
  check (reporter_id <> reported_user_id)
);

create table if not exists public.game_sessions (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  host_id uuid not null references public.profiles(id) on delete cascade,
  game_type text not null default 'this_or_that' check (game_type in ('this_or_that')),
  invite_code text not null unique default upper(substr(encode(gen_random_bytes(6),'hex'),1,8)),
  state jsonb not null default '{"round":0,"answers":{},"status":"waiting"}'::jsonb,
  status text not null default 'waiting' check (status in ('waiting','playing','finished')),
  created_at timestamptz not null default now()
);

create table if not exists public.game_players (
  session_id uuid not null references public.game_sessions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  answers jsonb not null default '{}'::jsonb,
  joined_at timestamptz not null default now(),
  primary key (session_id, user_id)
);

create index if not exists event_members_user_idx on public.event_members(user_id);
create index if not exists group_event_idx on public.groups(event_id);
create index if not exists game_session_event_idx on public.game_sessions(event_id);

create or replace function public.is_event_member(target_event uuid, target_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.event_members where event_id=target_event and user_id=target_user) $$;

create or replace function public.has_block_between(target_user uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.blocks where (blocker_id=auth.uid() and blocked_id=target_user) or (blocker_id=target_user and blocked_id=auth.uid())) $$;

create or replace function public.join_event_with_code(event_code text)
returns table(event_id uuid) language plpgsql security definer set search_path = public
as $$
declare target_event uuid;
begin
  if auth.uid() is null then raise exception 'Sign in to join an event.'; end if;
  select id into target_event from public.events where code=upper(trim(event_code));
  if target_event is null then raise exception 'That event code was not found.'; end if;
  insert into public.event_members(event_id,user_id) values(target_event,auth.uid()) on conflict do nothing;
  return query select target_event;
end; $$;

create or replace function public.join_game_with_code(room_code text, expected_event uuid)
returns table(session_id uuid) language plpgsql security definer set search_path = public
as $$
declare target_session uuid; target_event uuid;
begin
  if auth.uid() is null then raise exception 'Sign in to join a game.'; end if;
  select id,event_id into target_session,target_event from public.game_sessions where invite_code=upper(trim(room_code)) and status='waiting';
  if target_session is null then raise exception 'That game room is not available.'; end if;
  if target_event <> expected_event then raise exception 'That room belongs to a different event.'; end if;
  if not public.is_event_member(target_event,auth.uid()) then raise exception 'Join the event before entering its game room.'; end if;
  insert into public.game_players(session_id,user_id) values(target_session,auth.uid()) on conflict do nothing;
  return query select target_session;
end; $$;

create or replace function public.create_game_room(p_event_id uuid)
returns table(game_id uuid, invite_code text) language plpgsql security definer set search_path = public
as $$
declare new_id uuid; new_code text;
begin
  if auth.uid() is null then raise exception 'Sign in to start a game.'; end if;
  if not public.is_event_member(p_event_id,auth.uid()) then raise exception 'Join this event before starting a game.'; end if;
  insert into public.game_sessions(event_id,host_id,game_type)
  values(p_event_id,auth.uid(),'this_or_that') returning id,invite_code into new_id,new_code;
  insert into public.game_players(session_id,user_id) values(new_id,auth.uid());
  return query select new_id,new_code;
end; $$;

create or replace function public.save_my_profile(
  p_name text, p_bio text, p_college text, p_year text, p_visibility boolean, p_interests text[]
) returns void language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Sign in to save your profile.'; end if;
  if nullif(trim(p_name),'') is null or char_length(trim(p_name)) > 48 then raise exception 'Enter a name up to 48 characters.'; end if;
  if coalesce(array_length(p_interests,1),0) < 3 then raise exception 'Choose at least three interests.'; end if;
  insert into public.profiles(id,name,bio,college,year,visibility)
  values(auth.uid(),trim(p_name),nullif(trim(p_bio),''),nullif(trim(p_college),''),nullif(trim(p_year),''),coalesce(p_visibility,true))
  on conflict(id) do update set name=excluded.name,bio=excluded.bio,college=excluded.college,year=excluded.year,visibility=excluded.visibility,updated_at=now();
  delete from public.profile_interests where profile_id=auth.uid();
  insert into public.profile_interests(profile_id,interest)
  select auth.uid(),trim(interest) from unnest(p_interests) as t(interest) where nullif(trim(interest),'') is not null group by trim(interest);
end; $$;

create or replace function public.create_event(
  p_name text, p_description text, p_location text, p_starts_at timestamptz, p_requested_code text default null
) returns uuid language plpgsql security definer set search_path = public
as $$
declare new_id uuid; event_code text; requested text := upper(trim(coalesce(p_requested_code,'')));
begin
  if auth.uid() is null then raise exception 'Sign in to host an event.'; end if;
  if not exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'Finish your profile before hosting an event.'; end if;
  if nullif(trim(p_name),'') is null or char_length(trim(p_name)) > 100 then raise exception 'Enter an event name up to 100 characters.'; end if;
  if requested <> '' and requested !~ '^[A-Z0-9]{4,12}$' then raise exception 'Event codes use 4–12 letters or numbers.'; end if;
  if requested <> '' then event_code := requested;
  else
    loop
      event_code := upper(substr(encode(gen_random_bytes(4),'hex'),1,8));
      exit when not exists(select 1 from public.events where code=event_code);
    end loop;
  end if;
  insert into public.events(name,description,location,starts_at,code,host_id)
  values(trim(p_name),nullif(trim(p_description),''),nullif(trim(p_location),''),p_starts_at,event_code,auth.uid()) returning id into new_id;
  insert into public.event_members(event_id,user_id) values(new_id,auth.uid());
  return new_id;
end; $$;

create or replace function public.create_group(
  p_event_id uuid, p_name text, p_interest text, p_description text
) returns uuid language plpgsql security definer set search_path = public
as $$
declare new_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in to start a group.'; end if;
  if not public.is_event_member(p_event_id,auth.uid()) then raise exception 'Join this event before starting a group.'; end if;
  if nullif(trim(p_name),'') is null or char_length(trim(p_name)) > 70 then raise exception 'Enter a group name up to 70 characters.'; end if;
  insert into public.groups(event_id,name,interest,description,created_by)
  values(p_event_id,trim(p_name),nullif(trim(p_interest),''),nullif(trim(p_description),''),auth.uid()) returning id into new_id;
  insert into public.group_members(group_id,user_id) values(new_id,auth.uid());
  return new_id;
end; $$;

create or replace function public.cleanup_event_departure()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  delete from public.group_members gm using public.groups g
    where gm.group_id=g.id and g.event_id=old.event_id and gm.user_id=old.user_id;
  delete from public.game_players gp using public.game_sessions s
    where gp.session_id=s.id and s.event_id=old.event_id and gp.user_id=old.user_id;
  update public.game_sessions set status='finished'
    where event_id=old.event_id and host_id=old.user_id and status <> 'finished';
  return old;
end; $$;
drop trigger if exists event_departure_cleanup on public.event_members;
create trigger event_departure_cleanup after delete on public.event_members
for each row execute function public.cleanup_event_departure();

alter table public.profiles enable row level security;
alter table public.profile_interests enable row level security;
alter table public.events enable row level security;
alter table public.event_members enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
alter table public.game_sessions enable row level security;
alter table public.game_players enable row level security;

drop policy if exists "profiles self or shared event" on public.profiles;
create policy "profiles self or shared event" on public.profiles for select to authenticated using (
  id=auth.uid() or (visibility and exists(select 1 from public.event_members mine join public.event_members theirs on theirs.event_id=mine.event_id where mine.user_id=auth.uid() and theirs.user_id=profiles.id) and not public.has_block_between(id))
);
drop policy if exists "profiles owner updates" on public.profiles;
create policy "profiles owner updates" on public.profiles for all to authenticated using(id=auth.uid()) with check(id=auth.uid());
drop policy if exists "interest owner or shared event" on public.profile_interests;
create policy "interest owner or shared event" on public.profile_interests for select to authenticated using(profile_id=auth.uid() or (exists(select 1 from public.profiles p where p.id=profile_id and p.visibility) and exists(select 1 from public.event_members mine join public.event_members theirs on theirs.event_id=mine.event_id where mine.user_id=auth.uid() and theirs.user_id=profile_interests.profile_id) and not public.has_block_between(profile_id)));
drop policy if exists "interest owner manages" on public.profile_interests;
create policy "interest owner manages" on public.profile_interests for all to authenticated using(profile_id=auth.uid()) with check(profile_id=auth.uid());

drop policy if exists "event members can view event" on public.events;
create policy "event members can view event" on public.events for select to authenticated using(public.is_event_member(id) or host_id=auth.uid());
drop policy if exists "host creates event" on public.events;
create policy "host creates event" on public.events for insert to authenticated with check(host_id=auth.uid());
drop policy if exists "host updates event" on public.events;
create policy "host updates event" on public.events for update to authenticated using(host_id=auth.uid()) with check(host_id=auth.uid());
drop policy if exists "host deletes event" on public.events;
create policy "host deletes event" on public.events for delete to authenticated using(host_id=auth.uid());
drop policy if exists "event participants can see membership" on public.event_members;
create policy "event participants can see membership" on public.event_members for select to authenticated using(public.is_event_member(event_id));
drop policy if exists "host can add own membership" on public.event_members;
create policy "host can add own membership" on public.event_members for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.events where id=event_id and host_id=auth.uid()));
drop policy if exists "member can leave event" on public.event_members;
create policy "member can leave event" on public.event_members for delete to authenticated using(user_id=auth.uid());

drop policy if exists "event members view groups" on public.groups;
create policy "event members view groups" on public.groups for select to authenticated using(public.is_event_member(event_id));
drop policy if exists "event members create groups" on public.groups;
create policy "event members create groups" on public.groups for insert to authenticated with check(created_by=auth.uid() and public.is_event_member(event_id));
drop policy if exists "group creator manages group" on public.groups;
create policy "group creator manages group" on public.groups for update to authenticated using(created_by=auth.uid()) with check(created_by=auth.uid());
drop policy if exists "group members view membership" on public.group_members;
create policy "group members view membership" on public.group_members for select to authenticated using(exists(select 1 from public.groups g where g.id=group_id and public.is_event_member(g.event_id)));
drop policy if exists "event member joins group" on public.group_members;
create policy "event member joins group" on public.group_members for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.groups g where g.id=group_id and public.is_event_member(g.event_id)));
drop policy if exists "member leaves group" on public.group_members;
create policy "member leaves group" on public.group_members for delete to authenticated using(user_id=auth.uid());

drop policy if exists "user manages own block list" on public.blocks;
create policy "user manages own block list" on public.blocks for all to authenticated using(blocker_id=auth.uid()) with check(blocker_id=auth.uid());
drop policy if exists "reporter creates report" on public.reports;
create policy "reporter creates report" on public.reports for insert to authenticated with check(reporter_id=auth.uid());
drop policy if exists "reporter reads own reports" on public.reports;
create policy "reporter reads own reports" on public.reports for select to authenticated using(reporter_id=auth.uid());

drop policy if exists "event members view game sessions" on public.game_sessions;
create policy "event members view game sessions" on public.game_sessions for select to authenticated using(public.is_event_member(event_id));
drop policy if exists "event member creates game" on public.game_sessions;
create policy "event member creates game" on public.game_sessions for insert to authenticated with check(host_id=auth.uid() and public.is_event_member(event_id));
drop policy if exists "host or game player updates session" on public.game_sessions;
create policy "host or game player updates session" on public.game_sessions for update to authenticated using(host_id=auth.uid() or exists(select 1 from public.game_players where session_id=id and user_id=auth.uid())) with check(host_id=auth.uid() or exists(select 1 from public.game_players where session_id=id and user_id=auth.uid()));
drop policy if exists "participants see game players" on public.game_players;
create policy "participants see game players" on public.game_players for select to authenticated using(exists(select 1 from public.game_sessions s where s.id=session_id and public.is_event_member(s.event_id)));
drop policy if exists "event member joins game" on public.game_players;
create policy "event member joins game" on public.game_players for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.game_sessions s where s.id=session_id and public.is_event_member(s.event_id)));
drop policy if exists "player updates own game answers" on public.game_players;
create policy "player updates own game answers" on public.game_players for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

grant execute on function public.join_event_with_code(text) to authenticated;
grant execute on function public.join_game_with_code(text,uuid) to authenticated;
grant execute on function public.create_game_room(uuid) to authenticated;
grant execute on function public.save_my_profile(text,text,text,text,boolean,text[]) to authenticated;
grant execute on function public.create_event(text,text,text,timestamptz,text) to authenticated;
grant execute on function public.create_group(uuid,text,text,text) to authenticated;
revoke all on function public.save_my_profile(text,text,text,text,boolean,text[]) from public, anon;
revoke all on function public.create_event(text,text,text,timestamptz,text) from public, anon;
revoke all on function public.create_group(uuid,text,text,text) from public, anon;
revoke all on function public.create_game_room(uuid) from public, anon;
revoke all on function public.cleanup_event_departure() from public, anon;
revoke all on function public.is_event_member(uuid,uuid) from public, anon;
revoke all on function public.has_block_between(uuid) from public, anon;
grant execute on function public.is_event_member(uuid,uuid) to authenticated;
grant execute on function public.has_block_between(uuid) to authenticated;

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.profiles, public.profile_interests, public.events, public.event_members,
  public.groups, public.group_members, public.blocks, public.reports, public.game_sessions, public.game_players to authenticated;
revoke all on public.profiles, public.profile_interests, public.events, public.event_members,
  public.groups, public.group_members, public.blocks, public.reports, public.game_sessions, public.game_players from anon;
revoke all on function public.join_event_with_code(text) from public, anon;
revoke all on function public.join_game_with_code(text,uuid) from public, anon;
grant execute on function public.join_event_with_code(text) to authenticated;
grant execute on function public.join_game_with_code(text,uuid) to authenticated;

-- Enable change feeds for the multiplayer game client.
do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='game_players') then alter publication supabase_realtime add table public.game_players; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='game_sessions') then alter publication supabase_realtime add table public.game_sessions; end if;
end $$;
