-- Some Supabase REST requests can evaluate through the public role before JWT
-- claims are applied. Keep the owner predicate, but attach it to public so
-- authenticated JWT claims can still reveal only the caller's message rows.

drop policy if exists conversation_messages_select_own
    on public.conversation_messages;

create policy conversation_messages_select_own
    on public.conversation_messages
    for select
    to public
    using (
        auth_user_id = auth.uid()
    );

