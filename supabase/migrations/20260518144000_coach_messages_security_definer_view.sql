-- Make the Coach read view explicitly security-definer so underlying table RLS
-- does not hide rows before the view's owner filter is applied.

create or replace view public.coach_messages
with (security_invoker = false) as
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

