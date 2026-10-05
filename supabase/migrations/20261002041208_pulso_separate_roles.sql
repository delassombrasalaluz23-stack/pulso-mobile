-- Roles are chosen once; existing accounts and appointment history are preserved.
create function pulso_private.lock_profile_role() returns trigger language plpgsql set search_path='' as $$
begin
 if new.role is distinct from old.role then raise exception 'El tipo de cuenta no se puede cambiar. Usa una cuenta independiente.'; end if;
 return new;
end$$;
revoke all on function pulso_private.lock_profile_role() from public,anon,authenticated;
create trigger profile_role_immutable before update of role on public.profiles for each row execute function pulso_private.lock_profile_role();

alter policy shop_read on public.shops using(owner_id=auth.uid() or (active and exists(select 1 from public.profiles where id=auth.uid() and role='client')));
alter policy favorite_own on public.favorites using(customer_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='client')) with check(customer_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='client'));
alter policy consent_own on public.marketing_consents using(customer_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='client')) with check(customer_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='client'));
create or replace function pulso_private.book_appointment(p_barber uuid,p_service uuid,p_addons uuid[],p_start timestamptz,p_expected_total int,p_expected_deposit int,p_expected_cancel int,p_accept boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare s public.shops;v public.services;b public.barbers;total int;mins int;items jsonb;booking uuid;cname text;begin
if not exists(select 1 from public.profiles where id=auth.uid() and role='client') then raise exception 'Solo las cuentas de cliente pueden reservar'; end if;
if auth.uid() is null or p_accept is distinct from true then raise exception 'Acepta las condiciones';end if;
select * into b from public.barbers where id=p_barber and active;select * into v from public.services where id=p_service and shop_id=b.shop_id and active and kind='cut';select * into s from public.shops where id=b.shop_id and active;
if s.id is null or v.id is null then raise exception 'Servicio no disponible';end if;
perform pg_advisory_xact_lock(hashtextextended(p_barber::text,0));
if (select count(*) from public.services where id=any(p_addons) and shop_id=s.id and kind='addon' and active)<>cardinality(p_addons) then raise exception 'Agregados no válidos';end if;
select sum(price_cents),sum(duration_minutes),jsonb_agg(jsonb_build_object('id',id,'name',name,'price_cents',price_cents,'minutes',duration_minutes)) into total,mins,items from public.services where id=p_service or id=any(p_addons);
if total<>p_expected_total or s.deposit_percent<>p_expected_deposit or s.cancel_hours<>p_expected_cancel then raise exception 'El precio o las condiciones cambiaron. Actualiza el perfil.';end if;
if not exists(select 1 from public.available_slots(p_barber,(p_start at time zone s.timezone)::date,p_service,p_addons) a where a.starts_at=p_start) then raise exception 'El horario ya no está disponible';end if;
select name into cname from public.profiles where id=auth.uid();if cname is null then raise exception 'Completa tu perfil';end if;
insert into public.appointments(customer_id,shop_id,barber_id,customer_name,shop_name,barber_name,starts_at,ends_at,lines,total_cents,deposit_cents,cancel_hours) values(auth.uid(),s.id,b.id,cname,s.name,b.name,p_start,p_start+make_interval(mins=>mins),items,total,round(total*s.deposit_percent/100.0)::int,s.cancel_hours) returning id into booking;return booking;
end$$;
notify pgrst, 'reload schema';
