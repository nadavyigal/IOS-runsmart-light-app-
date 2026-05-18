revoke all on function public.coach_messages_for_conversation(uuid, integer, boolean)
    from public;

revoke all on function public.coach_messages_for_conversation(uuid, integer, boolean)
    from anon;

grant execute on function public.coach_messages_for_conversation(uuid, integer, boolean)
    to authenticated;
