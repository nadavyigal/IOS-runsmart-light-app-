revoke execute on function public.claim_garmin_import_jobs(integer, text)
from public, anon, authenticated;

revoke execute on function public.fail_garmin_import_job(uuid, text, boolean)
from public, anon, authenticated;

revoke execute on function public.requeue_garmin_import_job(uuid, timestamp with time zone, text)
from public, anon, authenticated;

revoke execute on function public.invoke_garmin_worker()
from public, anon, authenticated;

grant execute on function public.claim_garmin_import_jobs(integer, text)
to service_role;

grant execute on function public.fail_garmin_import_job(uuid, text, boolean)
to service_role;

grant execute on function public.requeue_garmin_import_job(uuid, timestamp with time zone, text)
to service_role;

grant execute on function public.invoke_garmin_worker()
to service_role;
