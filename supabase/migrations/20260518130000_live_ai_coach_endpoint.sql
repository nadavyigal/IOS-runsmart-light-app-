-- Live AI Coach endpoint support.
-- Keeps existing iOS compatibility where conversations.profile_id can equal auth.uid().

alter table public.conversations
    add column if not exists auth_user_id uuid references auth.users(id);

update public.conversations
set auth_user_id = profile_id
where auth_user_id is null
  and profile_id is not null;

alter table public.conversation_messages
    add column if not exists client_message_id text,
    add column if not exists source text;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'conversation_messages_source_check'
    ) then
        alter table public.conversation_messages
            add constraint conversation_messages_source_check
            check (
                source is null
                or source in ('client', 'live_ai', 'fallback', 'mock')
            )
            not valid;
    end if;
end $$;

create index if not exists conversations_auth_user_id_idx
    on public.conversations(auth_user_id);

create index if not exists conversations_profile_id_idx
    on public.conversations(profile_id);

create index if not exists conversation_messages_conversation_id_idx
    on public.conversation_messages(conversation_id);

create unique index if not exists conversation_messages_client_message_id_idx
    on public.conversation_messages(conversation_id, client_message_id)
    where client_message_id is not null;

alter table public.conversations enable row level security;
alter table public.conversation_messages enable row level security;

do $$
begin
    if not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'conversations'
          and policyname = 'conversations_select_own'
    ) then
        create policy conversations_select_own
            on public.conversations
            for select
            to authenticated
            using (
                auth_user_id = auth.uid()
                or profile_id = auth.uid()
            );
    end if;

    if not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'conversations'
          and policyname = 'conversations_insert_own'
    ) then
        create policy conversations_insert_own
            on public.conversations
            for insert
            to authenticated
            with check (
                auth_user_id = auth.uid()
                or profile_id = auth.uid()
            );
    end if;

    if not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'conversations'
          and policyname = 'conversations_update_own'
    ) then
        create policy conversations_update_own
            on public.conversations
            for update
            to authenticated
            using (
                auth_user_id = auth.uid()
                or profile_id = auth.uid()
            )
            with check (
                auth_user_id = auth.uid()
                or profile_id = auth.uid()
            );
    end if;

    if not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'conversation_messages'
          and policyname = 'conversation_messages_select_own'
    ) then
        create policy conversation_messages_select_own
            on public.conversation_messages
            for select
            to authenticated
            using (
                exists (
                    select 1
                    from public.conversations c
                    where c.id = conversation_messages.conversation_id
                      and (
                          c.auth_user_id = auth.uid()
                          or c.profile_id = auth.uid()
                      )
                )
            );
    end if;

    if not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'conversation_messages'
          and policyname = 'conversation_messages_insert_own'
    ) then
        create policy conversation_messages_insert_own
            on public.conversation_messages
            for insert
            to authenticated
            with check (
                exists (
                    select 1
                    from public.conversations c
                    where c.id = conversation_messages.conversation_id
                      and (
                          c.auth_user_id = auth.uid()
                          or c.profile_id = auth.uid()
                      )
                )
            );
    end if;
end $$;
