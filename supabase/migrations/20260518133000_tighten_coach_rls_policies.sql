-- Remove older broad Coach policies so authenticated users only access their own threads.
-- The service role can still write through the Edge Function.

drop policy if exists "Authenticated users can manage conversations"
    on public.conversations;

drop policy if exists "Authenticated users can read messages"
    on public.conversation_messages;

drop policy if exists "Authenticated users can insert messages"
    on public.conversation_messages;

