-- Local PGlite skips unavailable extensions. Hosted Supabase schedules the server worker.
-- Deploy booking-worker before applying this migration. No payment provider secrets here.
do $schedule$ begin
 if exists(select 1 from pg_available_extensions where name='pg_cron') and exists(select 1 from pg_available_extensions where name='pg_net') then
  create extension if not exists pg_cron;
  create extension if not exists pg_net with schema extensions;
  perform cron.schedule('pulso-booking-worker','* * * * *',$job$
   select net.http_post(
    url:='https://zccyxxwpkxjfnixjbuwl.supabase.co/functions/v1/booking-worker',
    headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select token::text from pulso_private.worker_credentials limit 1)),
    body:='{}'::jsonb,timeout_milliseconds:=30000
   );
  $job$);
 end if;
end $schedule$;
