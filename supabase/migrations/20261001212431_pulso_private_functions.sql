-- Keep privileged implementations outside the exposed REST schema.
create schema pulso_private;
revoke all on schema pulso_private from public,anon;
grant usage on schema pulso_private to authenticated;
do $move$
declare f record; call_args text; stability text;
begin
for f in select p.oid,p.proname,p.provolatile,
pg_get_function_identity_arguments(p.oid) identity_args,
pg_get_function_arguments(p.oid) args,
pg_get_function_result(p.oid) result,
p.proargnames[1:p.pronargs] input_names
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname=any(array['owns_shop','is_customer','available_slots','book_appointment','transition_appointment','my_customers','send_promotion','start_sharing','update_location','stop_sharing','arrivals'])
loop
 select string_agg(format('%I',a),',') into call_args from unnest(f.input_names) a;
 stability:=case when f.provolatile='s' then 'stable' else 'volatile' end;
 execute format('alter function public.%I(%s) set schema pulso_private',f.proname,f.identity_args);
 execute format('revoke all on function pulso_private.%I(%s) from public,anon,authenticated',f.proname,f.identity_args);
 if f.proname<>'is_customer' then
  execute format('grant execute on function pulso_private.%I(%s) to authenticated',f.proname,f.identity_args);
 end if;
 execute format('create function public.%I(%s) returns %s language sql %s security invoker set search_path='''' as %L',
 f.proname,f.args,f.result,stability,format('select * from pulso_private.%I(%s)',f.proname,call_args));
 execute format('revoke all on function public.%I(%s) from public,anon,authenticated',f.proname,f.identity_args);
 if f.proname<>'is_customer' then
  execute format('grant execute on function public.%I(%s) to authenticated',f.proname,f.identity_args);
 end if;
end loop;
if to_regprocedure('public.rls_auto_enable()') is not null then
 execute 'revoke execute on function public.rls_auto_enable() from public,anon,authenticated';
end if;
end $move$;
notify pgrst, 'reload schema';
