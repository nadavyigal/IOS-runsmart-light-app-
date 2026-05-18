-- Use the JWT subject claim directly for Coach message SELECT. This keeps the
-- owner-only predicate but avoids helper/context differences in REST policy
-- evaluation for this table.

drop policy if exists conversation_messages_select_own
    on public.conversation_messages;

create policy conversation_messages_select_own
    on public.conversation_messages
    for select
    to public
    using (
        auth_user_id = coalesce(
            nullif(current_setting('request.jwt.claim.sub', true), '')::uuid,
            (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid
        )
    );

