-- Stable Coach history read surface for mobile clients.
-- The view is intentionally owner-filtered and exposes only display fields.

create or replace view public.coach_messages as
select
    id,
    conversation_id,
    role,
    content,
    created_at
from public.conversation_messages
where auth_user_id = auth.uid()
  and auth.uid() is not null;

grant select on public.coach_messages to authenticated;

