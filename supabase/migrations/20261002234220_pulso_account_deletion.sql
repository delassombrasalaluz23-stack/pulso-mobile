-- Keep only anonymized appointment history after explicit account deletion.
-- Tombstones prevent still-valid access JWTs from accessing either RLS or RPCs.
alter table public.profiles add column deleted_at timestamptz;
alter table public.profiles drop constraint profiles_id_fkey;
revoke insert,update on public.profiles from authenticated;
grant insert(id,name,role),update(id,name,role) on public.profiles to authenticated;
create function pulso_private.active_uid() returns uuid language sql stable security definer set search_path='' as $$
 select auth.uid() where exists(select 1 from auth.users where id=auth.uid()) and not exists(select 1 from public.profiles where id=auth.uid() and deleted_at is not null)
$$;
create function public.active_uid() returns uuid language sql stable security invoker set search_path='' as $$select pulso_private.active_uid()$$;
revoke all on function pulso_private.active_uid(),public.active_uid() from public,anon;grant execute on function pulso_private.active_uid(),public.active_uid() to authenticated;
do $$declare f record;t record;begin
 for f in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='pulso_private' and p.proname<>'active_uid' and p.prosrc like '%auth.uid()%' loop
  execute replace(pg_get_functiondef(f.oid),'auth.uid()','pulso_private.active_uid()');
 end loop;
 for t in select tablename from pg_tables where schemaname='public' loop
  execute format('create policy active_account on public.%I as restrictive for all to authenticated using ((select public.active_uid()) is not null) with check ((select public.active_uid()) is not null)',t.tablename);
 end loop;
end$$;
create policy active_pulso_storage on storage.objects as restrictive for all to authenticated using(bucket_id not in ('portfolio','appointment-media') or (select public.active_uid()) is not null) with check(bucket_id not in ('portfolio','appointment-media') or (select public.active_uid()) is not null);
create function pulso_private.admin_close_account(p_user uuid) returns void language plpgsql security definer set search_path='' as $$
declare sh uuid;begin
 perform 1 from public.profiles where id=p_user for update;
 if not found then return;end if;
 select id into sh from public.shops where owner_id=p_user;
 -- Remove live sharing before cancelling. Normal cancellation notices go to affected customers.
 delete from public.live_locations where appointment_id in(select id from public.appointments where customer_id=p_user or shop_id=sh);
 delete from public.location_sessions where appointment_id in(select id from public.appointments where customer_id=p_user or shop_id=sh);
 delete from public.waitlist where customer_id=p_user or shop_id=sh;
 if sh is not null then
  update public.shops set active=false,name='Barbería eliminada',description='',address='',municipality='',state='',lat=0,lng=0 where id=sh;
  update public.barbers set active=false,name='Barbero',specialty='' where shop_id=sh;
  update public.services set active=false,name='Servicio',description='' where shop_id=sh;
  update public.offers set active=false,title='Promoción finalizada',conditions='' where shop_id=sh;
  delete from public.photos where shop_id=sh;
  update public.promotions set title='Barbería eliminada',body='Este negocio cerró su cuenta.' where shop_id=sh;
  delete from public.favorites where shop_id=sh;delete from public.marketing_consents where shop_id=sh;
  update public.appointments set shop_name='Barbería eliminada',barber_name='Barbero',offer_title=null where shop_id=sh;
 end if;
 update public.appointments set status='cancelled',outcome='refunded_simulated' where status in ('confirmed','arrived') and (customer_id=p_user or shop_id=sh);
 update public.appointments set customer_name='Cuenta eliminada',reference_path=null where customer_id=p_user;
 delete from public.reviews where customer_id=p_user;
 delete from public.favorites where customer_id=p_user;delete from public.marketing_consents where customer_id=p_user;
 delete from public.push_deliveries where inbox_id in(select id from public.inbox where customer_id=p_user) or token in(select token from public.push_tokens where user_id=p_user);
 delete from public.push_tokens where user_id=p_user;delete from public.inbox where customer_id=p_user;
 delete from public.activity_notifications where customer_id=p_user;
 update public.profiles set name='Cuenta eliminada',deleted_at=coalesce(deleted_at,now()) where id=p_user;
end$$;
create function public.admin_close_account(p_user uuid) returns void language sql security invoker set search_path='' as $$select pulso_private.admin_close_account(p_user)$$;
revoke all on function public.admin_close_account(uuid),pulso_private.admin_close_account(uuid) from public,anon,authenticated;
grant usage on schema pulso_private to service_role;
grant execute on function public.admin_close_account(uuid),pulso_private.admin_close_account(uuid) to service_role;
notify pgrst,'reload schema';
