-- Make Coach message ownership directly readable by PostgREST/RLS.
-- The conversation-level policy remains, but message SELECT no longer depends on
-- a nested RLS lookup through conversations.

alter table public.conversation_messages
    add column if not exists auth_user_id uuid references auth.users(id);

update public.conversation_messages m
set auth_user_id = c.auth_user_id
from public.conversations c
where m.conversation_id = c.id
  and m.auth_user_id is null
  and c.auth_user_id is not null;

create index if not exists conversation_messages_auth_user_id_idx
    on public.conversation_messages(auth_user_id);

drop policy if exists conversation_messages_select_own
    on public.conversation_messages;

drop policy if exists conversation_messages_insert_own
    on public.conversation_messages;

create policy conversation_messages_select_own
    on public.conversation_messages
    for select
    to authenticated
    using (
        auth_user_id = auth.uid()
    );

create policy conversation_messages_insert_own
    on public.conversation_messages
    for insert
    to authenticated
    with check (
        auth_user_id = auth.uid()
        and exists (
            select 1
            from public.conversations c
            where c.id = conversation_messages.conversation_id
              and (
                  c.auth_user_id = auth.uid()
                  or c.profile_id = auth.uid()
              )
        )
    );

