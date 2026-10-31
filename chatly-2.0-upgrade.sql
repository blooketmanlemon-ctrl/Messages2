-- Chatly database setup / upgrade
-- Safe to run more than once. Run in Supabase SQL Editor.
-- Keep a backup of your database before making schema changes.

-- The existing Chatly project should already have public.profiles with id and username.
alter table public.profiles
  add column if not exists display_name text,
  add column if not exists avatar_url text;

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_one uuid not null references auth.users(id) on delete cascade,
  user_two uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint conversations_distinct_users check (user_one <> user_two),
  constraint conversations_pair_unique unique (user_one, user_two)
);

create table if not exists public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index if not exists conversations_user_one_idx on public.conversations(user_one);
create index if not exists conversations_user_two_idx on public.conversations(user_two);
create index if not exists direct_messages_conversation_created_idx
  on public.direct_messages(conversation_id, created_at);

alter table public.conversations enable row level security;
alter table public.direct_messages enable row level security;

-- Profiles can be read by signed-in users so username lookup and contact details work.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='profiles'
      and policyname='Chatly profiles readable by authenticated users'
  ) then
    create policy "Chatly profiles readable by authenticated users"
      on public.profiles for select to authenticated using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='conversations'
      and policyname='Chatly members can read conversations'
  ) then
    create policy "Chatly members can read conversations"
      on public.conversations for select to authenticated
      using (auth.uid() = user_one or auth.uid() = user_two);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='direct_messages'
      and policyname='Chatly members can read direct messages'
  ) then
    create policy "Chatly members can read direct messages"
      on public.direct_messages for select to authenticated
      using (
        exists (
          select 1 from public.conversations c
          where c.id = conversation_id
            and (c.user_one = auth.uid() or c.user_two = auth.uid())
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='direct_messages'
      and policyname='Chatly members can send direct messages'
  ) then
    create policy "Chatly members can send direct messages"
      on public.direct_messages for insert to authenticated
      with check (
        sender_id = auth.uid()
        and exists (
          select 1 from public.conversations c
          where c.id = conversation_id
            and (c.user_one = auth.uid() or c.user_two = auth.uid())
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='profiles'
      and policyname='Chatly users can update their own profile'
  ) then
    create policy "Chatly users can update their own profile"
      on public.profiles for update to authenticated
      using (id = auth.uid()) with check (id = auth.uid());
  end if;
end $$;

-- Create/get a one-to-one conversation. The fixed UUID order avoids duplicate pairs.
create or replace function public.chatly_get_or_create_conversation(p_other_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  first_user uuid;
  second_user uuid;
  conversation_id uuid;
begin
  if current_user_id is null then
    raise exception 'You must be signed in.';
  end if;
  if p_other_user is null or p_other_user = current_user_id then
    raise exception 'Choose another Chatly user.';
  end if;

  if not exists (select 1 from public.profiles where id = p_other_user) then
    raise exception 'That Chatly user does not exist.';
  end if;

  first_user := least(current_user_id, p_other_user);
  second_user := greatest(current_user_id, p_other_user);

  insert into public.conversations(user_one, user_two)
  values (first_user, second_user)
  on conflict (user_one, user_two) do nothing;

  select id into conversation_id
  from public.conversations
  where user_one = first_user and user_two = second_user;

  return conversation_id;
end;
$$;

revoke all on function public.chatly_get_or_create_conversation(uuid) from public;
grant execute on function public.chatly_get_or_create_conversation(uuid) to authenticated;

-- Public avatar bucket; files are stored under a folder named with the owner's user ID.
insert into storage.buckets (id, name, public)
values ('chat-avatars', 'chat-avatars', true)
on conflict (id) do update set public = true;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects'
      and policyname='Chatly avatars are publicly viewable'
  ) then
    create policy "Chatly avatars are publicly viewable"
      on storage.objects for select
      using (bucket_id = 'chat-avatars');
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects'
      and policyname='Chatly users can upload their own avatars'
  ) then
    create policy "Chatly users can upload their own avatars"
      on storage.objects for insert to authenticated
      with check (
        bucket_id = 'chat-avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;
end $$;

-- Enable realtime updates for direct messages, if not already enabled.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'direct_messages'
  ) then
    alter publication supabase_realtime add table public.direct_messages;
  end if;
exception
  when undefined_object then
    raise notice 'supabase_realtime publication was not found; realtime can be enabled later in Supabase.';
end $$;
