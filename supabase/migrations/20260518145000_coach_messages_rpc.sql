-- Stable owner-filtered Coach history RPC for mobile clients.

create or replace function public.coach_messages_for_conversation(
    p_conversation_id uuid,
    p_limit integer default 10,
    p_assistant_only boolean default false
)
returns table (
    id uuid,
    conversation_id uuid,
    role public.conversation_role,
    content text,
    created_at timestamptz
)
language sql
security definer
set search_path = public, auth
stable
as $$
    select
        m.id,
        m.conversation_id,
        m.role,
        m.content,
        m.created_at
    from public.conversation_messages m
    where m.conversation_id = p_conversation_id
      and m.auth_user_id = auth.uid()
      and (not p_assistant_only or m.role = 'assistant')
    order by m.created_at desc
    limit greatest(1, least(coalesce(p_limit, 10), 50));
$$;

grant execute on function public.coach_messages_for_conversation(uuid, integer, boolean)
    to authenticated;

