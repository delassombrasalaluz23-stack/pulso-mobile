-- Public booking offers: one service, transparent terms, no stacking with loyalty.
create table public.offers(id uuid primary key default gen_random_uuid(),shop_id uuid not null references public.shops,service_id uuid not null references public.services,title text not null check(length(btrim(title)) between 1 and 80),kind text not null check(kind in ('percent','amount','price')),value integer not null check(value>0),ends_at timestamptz not null,conditions text not null default '' check(length(conditions)<=500),active boolean not null default true,created_at timestamptz not null default now(),check(kind<>'percent' or value<=100));
alter table public.offers enable row level security;
grant select,insert,update on public.offers to authenticated;
create policy offer_read on public.offers for select to authenticated using(public.owns_shop(shop_id) or (active and ends_at>now() and exists(select 1 from public.shops s where s.id=shop_id and s.active)));
create policy offer_insert on public.offers for insert to authenticated with check(public.owns_shop(shop_id) and exists(select 1 from public.services s where s.id=service_id and s.shop_id=offers.shop_id and s.kind='cut'));
create policy offer_update on public.offers for update to authenticated using(public.owns_shop(shop_id)) with check(public.owns_shop(shop_id) and exists(select 1 from public.services s where s.id=service_id and s.shop_id=offers.shop_id and s.kind='cut'));
alter table public.appointments add column offer_id uuid references public.offers,add column offer_title text,add column reference_path text;
create function pulso_private.book_with_offer(p_barber uuid,p_service uuid,p_addons uuid[],p_start timestamptz,p_expected_total integer,p_expected_deposit integer,p_expected_cancel integer,p_accept boolean,p_offer uuid,p_expected_discount integer) returns uuid language plpgsql security definer set search_path='' as $$
declare o public.offers;v public.services;discount integer;booking uuid;begin
 if auth.uid() is null or p_expected_total is null or p_expected_deposit is null or p_expected_cancel is null then raise exception 'Revisa tu reserva';end if;
 select * into o from public.offers where id=p_offer and active and ends_at>=p_start and ends_at>now() for share;
 select * into v from public.services where id=p_service and active and kind='cut';
 if o.id is null or o.service_id is distinct from v.id or o.shop_id is distinct from v.shop_id then raise exception 'La promoción no aplica a este corte o fecha';end if;
 discount:=case o.kind when 'percent' then round(v.price_cents*o.value/100.0)::integer when 'amount' then least(v.price_cents,o.value) else v.price_cents-o.value end;
 if discount<=0 or discount is distinct from p_expected_discount then raise exception 'El descuento cambió. Revisa los precios.';end if;
 booking:=pulso_private.book_appointment(p_barber,p_service,p_addons,p_start,p_expected_total,p_expected_deposit,p_expected_cancel,p_accept);
 update public.appointments set offer_id=o.id,offer_title=o.title,discount_cents=discount,total_cents=total_cents-discount,deposit_cents=round((total_cents-discount)*p_expected_deposit/100.0)::integer where id=booking;
 return booking;
end$$;

-- Availability for a move uses the booked duration and excludes only the same appointment.
create function pulso_private.reschedule_slots(p_id uuid,p_day date) returns table(starts_at timestamptz,ends_at timestamptz) language plpgsql stable security definer set search_path='' as $$
declare a public.appointments;s public.shops;mins integer;begin
 select * into a from public.appointments where id=p_id;
 if auth.uid() is null or a.id is null or (a.customer_id<>auth.uid() and not public.owns_shop(a.shop_id)) then raise exception 'Sin acceso';end if;
 if a.status<>'confirmed' then return;end if;
 select * into s from public.shops where id=a.shop_id and active;
 if s.id is null or not exists(select 1 from public.barbers where id=a.barber_id and active) or not extract(dow from p_day)::integer=any(s.days) then return;end if;
 mins:=round(extract(epoch from a.ends_at-a.starts_at)/60)::integer;
 return query select t,t+make_interval(mins=>mins) from generate_series((p_day+s.open_hour*interval '1 hour') at time zone s.timezone,(p_day+s.close_hour*interval '1 hour') at time zone s.timezone-make_interval(mins=>mins),interval '15 minutes') t where t>now() and t<now()+interval '30 days' and not exists(select 1 from public.appointments b where b.id<>a.id and b.barber_id=a.barber_id and b.status in ('confirmed','arrived') and tstzrange(b.starts_at,b.ends_at,'[)')&&tstzrange(t,t+make_interval(mins=>mins),'[)'));
end$$;
create function pulso_private.reschedule_appointment(p_id uuid,p_start timestamptz,p_expected_start timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare a public.appointments;s public.shops;begin
 select * into a from public.appointments where id=p_id for update;
 if auth.uid() is null or a.id is null or (a.customer_id<>auth.uid() and not public.owns_shop(a.shop_id)) then raise exception 'Sin acceso';end if;
 if a.status<>'confirmed' or a.starts_at is distinct from p_expected_start then raise exception 'La cita cambió. Actualiza tu agenda.';end if;
 if not public.owns_shop(a.shop_id) and now()>a.starts_at-make_interval(hours=>a.cancel_hours) then raise exception 'El plazo para cambiar la cita terminó. Contacta con la barbería.';end if;
 select * into s from public.shops where id=a.shop_id;
 if a.offer_id is not null and not exists(select 1 from public.offers where id=a.offer_id and ends_at>=p_start) then raise exception 'Elige una fecha dentro de la vigencia de tu promoción';end if;
 perform pg_advisory_xact_lock(hashtextextended(a.barber_id::text,0));
 if not exists(select 1 from pulso_private.reschedule_slots(a.id,(p_start at time zone s.timezone)::date) t where t.starts_at=p_start) then raise exception 'Ese horario ya no está disponible';end if;
 update public.appointments set starts_at=p_start,ends_at=p_start+(a.ends_at-a.starts_at) where id=a.id;
 delete from public.location_sessions where appointment_id=a.id;delete from public.live_locations where appointment_id=a.id;
end$$;

create table public.waitlist(id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.profiles,shop_id uuid not null references public.shops,barber_id uuid not null references public.barbers,service_id uuid not null references public.services,day date not null,created_at timestamptz not null default now(),unique(customer_id,barber_id,service_id,day));
create table public.activity_notifications(id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.profiles,shop_id uuid not null references public.shops,appointment_id uuid references public.appointments,title text not null,body text not null,read_at timestamptz,created_at timestamptz not null default now());
alter table public.waitlist enable row level security;alter table public.activity_notifications enable row level security;
grant select,delete on public.waitlist to authenticated;grant select on public.activity_notifications to authenticated;grant update(read_at) on public.activity_notifications to authenticated;
create policy waitlist_own on public.waitlist for all to authenticated using(customer_id=auth.uid()) with check(customer_id=auth.uid());
create policy activity_read on public.activity_notifications for select to authenticated using(customer_id=auth.uid());
create policy activity_update on public.activity_notifications for update to authenticated using(customer_id=auth.uid()) with check(customer_id=auth.uid());
create function pulso_private.join_waitlist(p_barber uuid,p_service uuid,p_day date) returns void language plpgsql security definer set search_path='' as $$
declare s public.shops;begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='client') then raise exception 'Solo clientes';end if;
 select sh.* into s from public.shops sh join public.barbers b on b.shop_id=sh.id join public.services v on v.shop_id=sh.id where b.id=p_barber and b.active and v.id=p_service and v.active and v.kind='cut' and sh.active;
 if s.id is null or p_day<(now() at time zone s.timezone)::date or p_day>(now() at time zone s.timezone)::date+29 then raise exception 'Fecha o servicio no válido';end if;
 delete from public.waitlist where customer_id=auth.uid() and day<(now() at time zone s.timezone)::date;
 perform pg_advisory_xact_lock(hashtextextended('waitlist:'||auth.uid()::text,0));
 if (select count(*) from public.waitlist where customer_id=auth.uid())>=10 then raise exception 'Puedes tener hasta 10 esperas activas';end if;
 if exists(select 1 from pulso_private.available_slots(p_barber,p_day,p_service,'{}'::uuid[])) then raise exception 'Ya hay horarios disponibles. Actualiza y reserva.';end if;
 insert into public.waitlist(customer_id,shop_id,barber_id,service_id,day) values(auth.uid(),s.id,p_barber,p_service,p_day) on conflict do nothing;
end$$;
create function pulso_private.notify_appointment_change() returns trigger language plpgsql security definer set search_path='' as $$
declare w public.waitlist;s public.shops;begin
 if new.status is not distinct from old.status and new.starts_at is not distinct from old.starts_at then return new;end if;
 select * into s from public.shops where id=new.shop_id;
 if new.status='cancelled' or new.starts_at is distinct from old.starts_at then
  insert into public.activity_notifications(customer_id,shop_id,appointment_id,title,body) values(new.customer_id,new.shop_id,new.id,case when new.status='cancelled' then 'Cita cancelada' else 'Tu cita cambió de horario' end,case when new.status='cancelled' then 'Revisa el estado y las condiciones en Mis citas.' else 'Nuevo horario: '||to_char(new.starts_at at time zone s.timezone,'YYYY-MM-DD HH24:MI')||' · '||s.timezone||'. Conserva su precio y anticipo.' end);
  if auth.uid() is not null then
  for w in select * from public.waitlist where barber_id=old.barber_id and day=(old.starts_at at time zone s.timezone)::date for update loop
   if exists(select 1 from pulso_private.available_slots(w.barber_id,w.day,w.service_id,'{}'::uuid[])) then
    insert into public.activity_notifications(customer_id,shop_id,appointment_id,title,body) values(w.customer_id,w.shop_id,new.id,'Se liberó un horario',s.name||' tiene disponibilidad para el '||w.day::text||'. Entra al perfil y elige tu horario; no está apartado.');
    delete from public.waitlist where id=w.id;
   end if;
  end loop;
  end if;
 end if;return new;
end$$;
revoke all on function pulso_private.notify_appointment_change() from public,anon,authenticated;
create trigger appointment_change after update of status,starts_at on public.appointments for each row execute function pulso_private.notify_appointment_change();

-- Private references; review photos become readable only after a review is submitted.
alter table public.reviews add column comment text not null default '' check(length(comment)<=1000),add column photo_path text;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('appointment-media','appointment-media',false,5242880,array['image/jpeg']);
create function pulso_private.media_access(p_path text,p_write boolean default false) returns boolean language plpgsql stable security definer set search_path='' as $$
declare a public.appointments;k text;begin
 if auth.uid() is null then return false;end if;
 select * into a from public.appointments where id::text=split_part(p_path,'/',2);k:=split_part(p_path,'/',3);
 if a.id is null or split_part(p_path,'/',1)<>a.customer_id::text or k not in ('reference','review') or p_path !~ '^[0-9a-f-]+/[0-9a-f-]+/(reference|review)/[0-9a-f-]+\.jpg$' then return false;end if;
 if p_write then return a.customer_id=auth.uid() and ((k='reference' and a.status in ('confirmed','arrived')) or (k='review' and a.status='completed'));end if;
 return a.customer_id=auth.uid() or public.owns_shop(a.shop_id) or (k='review' and exists(select 1 from public.reviews r join public.shops sh on sh.id=r.shop_id where r.appointment_id=a.id and r.photo_path=p_path and sh.active));
end$$;
create function public.media_access(p_path text,p_write boolean default false) returns boolean language sql stable security invoker set search_path='' as $$select pulso_private.media_access(p_path,p_write)$$;
revoke all on function pulso_private.media_access(text,boolean),public.media_access(text,boolean) from public,anon;grant execute on function pulso_private.media_access(text,boolean),public.media_access(text,boolean) to authenticated;
create policy appointment_media_read on storage.objects for select to authenticated using(bucket_id='appointment-media' and public.media_access(name,false));
create policy appointment_media_insert on storage.objects for insert to authenticated with check(bucket_id='appointment-media' and public.media_access(name,true));
create policy appointment_media_delete on storage.objects for delete to authenticated using(bucket_id='appointment-media' and split_part(name,'/',1)=auth.uid()::text);
create function pulso_private.set_reference(p_id uuid,p_path text) returns void language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from public.appointments where id=p_id and customer_id=auth.uid() and status in ('confirmed','arrived')) then raise exception 'Solo puedes adjuntar referencias a tus citas activas';end if;
 if p_path is not null and (not pulso_private.media_access(p_path,true) or split_part(p_path,'/',2)<>p_id::text or split_part(p_path,'/',3)<>'reference' or not exists(select 1 from storage.objects where bucket_id='appointment-media' and name=p_path)) then raise exception 'Foto no válida';end if;
 update public.appointments set reference_path=p_path where id=p_id;
end$$;
-- Keep review creation atomic; clients cannot attach someone else's file.
revoke insert on public.reviews from authenticated;
-- Preserve star-only reviews from the previous mobile release; media/comments use the validated RPC.
grant insert(appointment_id,shop_id,customer_id,rating) on public.reviews to authenticated;
create function pulso_private.submit_review(p_id uuid,p_rating integer,p_comment text,p_photo text default null) returns void language plpgsql security definer set search_path='' as $$
declare a public.appointments;begin
 select * into a from public.appointments where id=p_id and customer_id=auth.uid() and status='completed';if a.id is null then raise exception 'Solo puedes valorar tus visitas completadas';end if;
 if p_photo is not null and (not pulso_private.media_access(p_photo,true) or split_part(p_photo,'/',2)<>p_id::text or split_part(p_photo,'/',3)<>'review' or not exists(select 1 from storage.objects where bucket_id='appointment-media' and name=p_photo)) then raise exception 'Foto no válida';end if;
 insert into public.reviews(appointment_id,customer_id,shop_id,rating,comment,photo_path) values(a.id,a.customer_id,a.shop_id,p_rating,btrim(p_comment),p_photo);
end$$;
create function pulso_private.shop_reviews(p_shop uuid) returns table(appointment_id uuid,rating integer,comment text,photo_path text,author text,created_at timestamptz) language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null or not exists(select 1 from public.shops where id=p_shop and (active or public.owns_shop(p_shop))) then raise exception 'Sin acceso';end if;
 return query select r.appointment_id,r.rating,r.comment,r.photo_path,split_part(p.name,' ',1),r.created_at from public.reviews r join public.profiles p on p.id=r.customer_id where r.shop_id=p_shop order by r.created_at desc limit 50;
end$$;
create function pulso_private.business_stats(p_shop uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;begin
 if not public.owns_shop(p_shop) then raise exception 'Solo tu barbería';end if;
 select jsonb_build_object('completed',count(*) filter(where status='completed'),'cancelled',count(*) filter(where status='cancelled'),'no_show',count(*) filter(where status='no_show'),'upcoming',count(*) filter(where status in ('confirmed','arrived')),'simulated_total',coalesce(sum(total_cents) filter(where status='completed'),0)) into result from public.appointments where shop_id=p_shop;
 return result||jsonb_build_object('returning_customers',(select count(*) from (select customer_id from public.appointments where shop_id=p_shop and status='completed' group by customer_id having count(*)>1) c),'top_services',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select l->>'name' name,count(*) visits from public.appointments a cross join lateral jsonb_array_elements(a.lines) l where a.shop_id=p_shop and a.status='completed' group by l->>'name' order by count(*) desc limit 5)x));
end$$;
-- Only narrow public invoker wrappers are exposed.
do $wrap$ declare f record;args text;begin
 for f in select p.oid,p.proname,pg_get_function_identity_arguments(p.oid) ident,pg_get_function_arguments(p.oid) fullargs,pg_get_function_result(p.oid) result,p.proargnames[1:p.pronargs] names,p.provolatile from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='pulso_private' and p.proname=any(array['book_with_offer','reschedule_slots','reschedule_appointment','join_waitlist','set_reference','submit_review','shop_reviews','business_stats']) loop
 select string_agg(format('%I',x),',') into args from unnest(f.names)x;
 execute format('revoke all on function pulso_private.%I(%s) from public,anon',f.proname,f.ident);
 execute format('grant execute on function pulso_private.%I(%s) to authenticated',f.proname,f.ident);
 execute format('create function public.%I(%s) returns %s language sql %s security invoker set search_path='''' as %L',f.proname,f.fullargs,f.result,case when f.provolatile='s' then 'stable' else 'volatile' end,'select * from pulso_private.'||f.proname||'('||args||')');
 execute format('revoke all on function public.%I(%s) from public,anon',f.proname,f.ident);execute format('grant execute on function public.%I(%s) to authenticated',f.proname,f.ident);
 end loop;end $wrap$;
notify pgrst,'reload schema';
