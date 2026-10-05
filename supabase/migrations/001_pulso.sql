-- Pulso native backend. Run once in a new Supabase project.
create table public.profiles(id uuid primary key references auth.users on delete cascade,name text not null check(length(name) between 1 and 80),role text not null check(role in ('client','owner')));
create table public.shops(id uuid primary key default gen_random_uuid(),owner_id uuid not null references public.profiles, name text not null check(length(name) between 1 and 80),description text not null default '',address text not null,municipality text not null,lat double precision not null check(lat between -85 and 85),lng double precision not null check(lng between -180 and 180),timezone text not null default 'America/Monterrey',open_hour int not null default 10 check(open_hour between 0 and 22),close_hour int not null default 20 check(close_hour between 1 and 23),days int[] not null default '{1,2,3,4,5,6}',deposit_percent int not null default 30 check(deposit_percent between 10 and 50),cancel_hours int not null default 12 check(cancel_hours in (6,12,24,48)),active boolean not null default true,unique(owner_id),check(close_hour>open_hour),check(cardinality(days)>0 and days <@ array[0,1,2,3,4,5,6]));
create table public.barbers(id uuid primary key default gen_random_uuid(),shop_id uuid not null references public.shops on delete cascade,name text not null check(length(name) between 1 and 80),specialty text not null default '',active boolean not null default true);
create table public.services(id uuid primary key default gen_random_uuid(),shop_id uuid not null references public.shops on delete cascade,name text not null check(length(name) between 1 and 80),description text not null default '',kind text not null check(kind in ('cut','addon')),price_cents int not null check(price_cents between 0 and 1000000),duration_minutes int not null check(duration_minutes between 0 and 240 and duration_minutes%15=0),active boolean not null default true,check(kind='addon' or duration_minutes>=15));
create table public.photos(id uuid primary key default gen_random_uuid(),shop_id uuid not null references public.shops on delete cascade,barber_id uuid references public.barbers,service_id uuid references public.services,kind text not null check(kind in ('shop','barber','cut')),caption text not null default '',storage_path text not null unique,created_at timestamptz not null default now());
create table public.favorites(customer_id uuid references public.profiles on delete cascade,shop_id uuid references public.shops on delete cascade,primary key(customer_id,shop_id));
create table public.marketing_consents(customer_id uuid references public.profiles on delete cascade,shop_id uuid references public.shops on delete cascade,enabled boolean not null default false,updated_at timestamptz not null default now(),primary key(customer_id,shop_id));
create table public.appointments(id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.profiles,shop_id uuid not null references public.shops,barber_id uuid not null references public.barbers,customer_name text not null,shop_name text not null,barber_name text not null,starts_at timestamptz not null,ends_at timestamptz not null,lines jsonb not null,total_cents int not null,deposit_cents int not null,cancel_hours int not null,status text not null default 'confirmed' check(status in ('confirmed','arrived','completed','cancelled','no_show')),payment_mode text not null default 'simulation' check(payment_mode='simulation'),outcome text not null default 'deposit_simulated',created_at timestamptz not null default now(),check(ends_at>starts_at));
create index appointment_shop_time on public.appointments(shop_id,starts_at);
create index appointment_customer on public.appointments(customer_id,starts_at);
create index appointment_barber_time on public.appointments(barber_id,starts_at,ends_at) where status in ('confirmed','arrived');
create table public.promotions(id uuid primary key,shop_id uuid not null references public.shops,title text not null check(length(title) between 1 and 80),body text not null check(length(body) between 1 and 500),created_at timestamptz not null default now());
create table public.inbox(id uuid primary key default gen_random_uuid(),promotion_id uuid not null references public.promotions,customer_id uuid not null references public.profiles,read_at timestamptz,created_at timestamptz not null default now(),unique(promotion_id,customer_id));
create table public.push_tokens(token text primary key,user_id uuid not null references public.profiles,updated_at timestamptz not null default now());
create table public.push_deliveries(inbox_id uuid not null references public.inbox,token text not null,ticket_id text,state text not null default 'pending',error text,primary key(inbox_id,token));
create table public.location_sessions(appointment_id uuid primary key references public.appointments,token uuid not null default gen_random_uuid(),expires_at timestamptz not null);
create table public.live_locations(appointment_id uuid primary key references public.appointments,lat double precision not null,lng double precision not null,accuracy double precision not null,updated_at timestamptz not null default now());

create function public.owns_shop(s uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.shops where id=s and owner_id=auth.uid())$$;
create function public.is_customer(s uuid,c uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.appointments where shop_id=s and customer_id=c and status='completed')$$;

alter table public.profiles enable row level security;alter table public.shops enable row level security;alter table public.barbers enable row level security;alter table public.services enable row level security;alter table public.photos enable row level security;alter table public.favorites enable row level security;alter table public.marketing_consents enable row level security;alter table public.appointments enable row level security;alter table public.promotions enable row level security;alter table public.inbox enable row level security;alter table public.push_tokens enable row level security;alter table public.push_deliveries enable row level security;alter table public.location_sessions enable row level security;alter table public.live_locations enable row level security;
create policy profile_own on public.profiles for all to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy shop_read on public.shops for select to authenticated using(active or owner_id=auth.uid());
create policy shop_insert on public.shops for insert to authenticated with check(owner_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='owner'));
create policy shop_update on public.shops for update to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
create policy barber_read on public.barbers for select to authenticated using(public.owns_shop(shop_id) or (active and exists(select 1 from public.shops where id=shop_id and active)));
create policy barber_write on public.barbers for all to authenticated using(public.owns_shop(shop_id)) with check(public.owns_shop(shop_id));
create policy service_read on public.services for select to authenticated using(public.owns_shop(shop_id) or (active and exists(select 1 from public.shops where id=shop_id and active)));
create policy service_write on public.services for all to authenticated using(public.owns_shop(shop_id)) with check(public.owns_shop(shop_id));
create policy photo_read on public.photos for select to authenticated using(exists(select 1 from public.shops where id=shop_id));
create policy photo_insert on public.photos for insert to authenticated with check(public.owns_shop(shop_id) and split_part(storage_path,'/',1)=auth.uid()::text and split_part(storage_path,'/',2)=shop_id::text and (barber_id is null or exists(select 1 from public.barbers b where b.id=barber_id and b.shop_id=photos.shop_id)) and (service_id is null or exists(select 1 from public.services s where s.id=service_id and s.shop_id=photos.shop_id)));
create policy photo_delete on public.photos for delete to authenticated using(public.owns_shop(shop_id));
create policy favorite_own on public.favorites for all to authenticated using(customer_id=auth.uid()) with check(customer_id=auth.uid());
create policy consent_own on public.marketing_consents for all to authenticated using(customer_id=auth.uid()) with check(customer_id=auth.uid());
create policy appointment_read on public.appointments for select to authenticated using(customer_id=auth.uid() or public.owns_shop(shop_id));
create policy promotion_read on public.promotions for select to authenticated using(public.owns_shop(shop_id) or exists(select 1 from public.inbox i where i.promotion_id=promotions.id and i.customer_id=auth.uid()));
create policy inbox_read on public.inbox for select to authenticated using(customer_id=auth.uid());
create policy inbox_update on public.inbox for update to authenticated using(customer_id=auth.uid()) with check(customer_id=auth.uid());
create policy tokens_own on public.push_tokens for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
-- The client cannot write appointments, location, promotions or deliveries directly.
revoke all on public.appointments,public.promotions,public.location_sessions,public.live_locations,public.push_deliveries from anon,authenticated;
grant select on public.appointments,public.promotions to authenticated;
revoke update on public.inbox from authenticated;grant update(read_at) on public.inbox to authenticated;

create function public.available_slots(p_barber uuid,p_day date,p_service uuid,p_addons uuid[] default '{}') returns table(starts_at timestamptz,ends_at timestamptz) language plpgsql stable security definer set search_path='' as $$
declare s public.shops;v public.services;mins int;begin
if auth.uid() is null then raise exception 'Inicia sesión';end if;
select * into v from public.services where id=p_service and active and kind='cut';select sh.* into s from public.shops sh join public.barbers b on b.shop_id=sh.id where b.id=p_barber and b.active and sh.active and sh.id=v.shop_id;
if s.id is null then return;end if;
if (select count(*) from public.services where id=any(p_addons) and shop_id=s.id and kind='addon' and active)<>cardinality(p_addons) then raise exception 'Agregados no válidos';end if;
select v.duration_minutes+coalesce(sum(duration_minutes),0) into mins from public.services where id=any(p_addons);
if not extract(dow from p_day)::int=any(s.days) then return;end if;
return query select t,t+make_interval(mins=>mins) from generate_series((p_day+s.open_hour*interval '1 hour') at time zone s.timezone,(p_day+s.close_hour*interval '1 hour') at time zone s.timezone-make_interval(mins=>mins),interval '15 minutes') t where t>now() and t<now()+interval '30 days' and not exists(select 1 from public.appointments a where a.barber_id=p_barber and a.status in ('confirmed','arrived') and tstzrange(a.starts_at,a.ends_at,'[)')&&tstzrange(t,t+make_interval(mins=>mins),'[)'));
end$$;

create function public.book_appointment(p_barber uuid,p_service uuid,p_addons uuid[],p_start timestamptz,p_expected_total int,p_expected_deposit int,p_expected_cancel int,p_accept boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare s public.shops;v public.services;b public.barbers;total int;mins int;items jsonb;booking uuid;cname text;begin
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

create function public.transition_appointment(p_id uuid,p_action text) returns void language plpgsql security definer set search_path='' as $$declare a public.appointments;is_owner boolean;begin
select * into a from public.appointments where id=p_id for update;if a.id is null then raise exception 'Cita no encontrada';end if;is_owner:=public.owns_shop(a.shop_id);
if auth.uid() is null or (a.customer_id<>auth.uid() and not is_owner) then raise exception 'Sin acceso';end if;
if a.status not in ('confirmed','arrived') then raise exception 'La cita ya está cerrada';end if;
if p_action='cancel' and a.customer_id=auth.uid() and a.status='confirmed' then update public.appointments set status='cancelled',outcome=case when now()<=a.starts_at-make_interval(hours=>a.cancel_hours) then 'refund_simulated' else 'forfeit_simulated' end where id=p_id;
elsif p_action='business_cancel' and is_owner then update public.appointments set status='cancelled',outcome='refund_simulated' where id=p_id;
elsif p_action='arrived' and is_owner and now()>=a.starts_at-interval '20 minutes' and a.status='confirmed' then update public.appointments set status='arrived' where id=p_id;
elsif p_action='complete' and is_owner and now()>=a.starts_at then update public.appointments set status='completed',outcome='applied_simulated' where id=p_id;
elsif p_action='no_show' and is_owner and a.status='confirmed' and now()>=a.starts_at+interval '15 minutes' then update public.appointments set status='no_show',outcome='forfeit_simulated' where id=p_id;
else raise exception 'Acción no permitida en este momento';end if;
delete from public.location_sessions where appointment_id=p_id;delete from public.live_locations where appointment_id=p_id;
end$$;

create function public.my_customers(p_shop uuid) returns table(customer_id uuid,name text,visits bigint,last_visit timestamptz,marketing boolean) language plpgsql stable security definer set search_path='' as $$begin
if not public.owns_shop(p_shop) then raise exception 'Solo puedes ver clientes de tu barbería';end if;
return query select p.id,p.name,count(*),max(a.starts_at),coalesce(c.enabled,false) from public.appointments a join public.profiles p on p.id=a.customer_id left join public.marketing_consents c on c.customer_id=p.id and c.shop_id=p_shop where a.shop_id=p_shop and a.status='completed' group by p.id,p.name,c.enabled order by max(a.starts_at) desc;
end$$;

create function public.send_promotion(p_id uuid,p_shop uuid,p_title text,p_body text,p_customer uuid default null) returns uuid language plpgsql security definer set search_path='' as $$begin
if not public.owns_shop(p_shop) then raise exception 'Sin acceso a esta barbería';end if;
perform pg_advisory_xact_lock(hashtextextended('promotion:'||p_shop::text,0));
if exists(select 1 from public.promotions where id=p_id) then if exists(select 1 from public.promotions where id=p_id and shop_id=p_shop) then return p_id;else raise exception 'Identificador no válido';end if;end if;
insert into public.promotions(id,shop_id,title,body) values(p_id,p_shop,trim(p_title),trim(p_body));
insert into public.inbox(promotion_id,customer_id) select p_id,c.customer_id from public.marketing_consents c where c.shop_id=p_shop and c.enabled and (p_customer is null or c.customer_id=p_customer) and public.is_customer(p_shop,c.customer_id) and (select count(*) from public.inbox i join public.promotions pr on pr.id=i.promotion_id where i.customer_id=c.customer_id and pr.shop_id=p_shop and i.created_at>now()-interval '24 hours')<2;
if not found then raise exception 'No hay clientes elegibles: necesitan una visita completada, permiso activo y menos de dos promociones en 24 horas.';end if;
return p_id;
end$$;

create function public.start_sharing(p_id uuid,p_consent boolean) returns uuid language plpgsql security definer set search_path='' as $$declare a public.appointments;t uuid:=gen_random_uuid();begin
select * into a from public.appointments where id=p_id and customer_id=auth.uid() for update;
if a.id is null or p_consent is distinct from true or a.status<>'confirmed' or now()<a.starts_at-interval '20 minutes' or now()>=a.starts_at then raise exception 'Solo durante los 20 minutos previos y con tu permiso';end if;
insert into public.location_sessions values(p_id,t,a.starts_at) on conflict(appointment_id) do update set token=t,expires_at=a.starts_at;delete from public.live_locations where appointment_id=p_id;return t;end$$;
create function public.update_location(p_id uuid,p_token uuid,p_lat double precision,p_lng double precision,p_accuracy double precision) returns void language plpgsql security definer set search_path='' as $$declare a public.appointments;begin
select * into a from public.appointments where id=p_id and customer_id=auth.uid() for update;
if a.id is null or a.status<>'confirmed' or now()<a.starts_at-interval '20 minutes' or now()>=a.starts_at or not exists(select 1 from public.location_sessions where appointment_id=p_id and token=p_token and expires_at>now()) then raise exception 'El permiso de ubicación terminó';end if;
if p_lat not between -85 and 85 or p_lng not between -180 and 180 or p_accuracy not between 0 and 1000 then raise exception 'Ubicación inválida';end if;
insert into public.live_locations values(p_id,p_lat,p_lng,p_accuracy,now()) on conflict(appointment_id) do update set lat=p_lat,lng=p_lng,accuracy=p_accuracy,updated_at=now();end$$;
create function public.stop_sharing(p_id uuid) returns void language plpgsql security definer set search_path='' as $$begin
perform 1 from public.appointments where id=p_id and customer_id=auth.uid() for update;if not found then raise exception 'Sin acceso';end if;delete from public.location_sessions where appointment_id=p_id;delete from public.live_locations where appointment_id=p_id;end$$;
create function public.arrivals(p_shop uuid) returns table(appointment_id uuid,name text,lat double precision,lng double precision,accuracy double precision,updated_at timestamptz,starts_at timestamptz) language plpgsql security definer set search_path='' as $$begin
if not public.owns_shop(p_shop) then raise exception 'Sin acceso';end if;
delete from public.live_locations l where l.updated_at<now()-interval '2 minutes' or l.appointment_id in(select a.id from public.appointments a where a.status<>'confirmed' or a.starts_at<=now());delete from public.location_sessions where expires_at<=now();
return query select a.id,a.customer_name,l.lat,l.lng,l.accuracy,l.updated_at,a.starts_at from public.live_locations l join public.appointments a on a.id=l.appointment_id join public.location_sessions c on c.appointment_id=a.id where a.shop_id=p_shop and a.status='confirmed' and now()>=a.starts_at-interval '20 minutes' and now()<a.starts_at and l.updated_at>now()-interval '2 minutes' and c.expires_at>now();end$$;

-- Least-privilege function access: no anonymous execution.
revoke execute on function public.owns_shop(uuid),public.is_customer(uuid,uuid),public.available_slots(uuid,date,uuid,uuid[]),public.book_appointment(uuid,uuid,uuid[],timestamptz,int,int,int,boolean),public.transition_appointment(uuid,text),public.my_customers(uuid),public.send_promotion(uuid,uuid,text,text,uuid),public.start_sharing(uuid,boolean),public.update_location(uuid,uuid,double precision,double precision,double precision),public.stop_sharing(uuid),public.arrivals(uuid) from public,anon;
grant execute on function public.owns_shop(uuid),public.is_customer(uuid,uuid),public.available_slots(uuid,date,uuid,uuid[]),public.book_appointment(uuid,uuid,uuid[],timestamptz,int,int,int,boolean),public.transition_appointment(uuid,text),public.my_customers(uuid),public.send_promotion(uuid,uuid,text,text,uuid),public.start_sharing(uuid,boolean),public.update_location(uuid,uuid,double precision,double precision,double precision),public.stop_sharing(uuid),public.arrivals(uuid) to authenticated;
-- Public portfolio photos only. Never put identity documents or location data here.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('portfolio','portfolio',true,5242880,array['image/jpeg','image/png','image/webp']);
create policy portfolio_upload on storage.objects for insert to authenticated with check(bucket_id='portfolio' and split_part(name,'/',1)=auth.uid()::text and exists(select 1 from public.shops where id::text=split_part(name,'/',2) and owner_id=auth.uid()));
create policy portfolio_delete on storage.objects for delete to authenticated using(bucket_id='portfolio' and split_part(name,'/',1)=auth.uid()::text);
-- Explicit grants independent of project-wide default privileges.
grant usage on schema public to authenticated;
grant select,insert,update on public.profiles,public.shops to authenticated;
grant select,insert,update,delete on public.barbers,public.services,public.favorites,public.marketing_consents,public.push_tokens to authenticated;
grant select,insert,delete on public.photos to authenticated;
grant select on public.inbox to authenticated;
revoke execute on function public.is_customer(uuid,uuid) from authenticated;

-- Server-only promotion delivery permissions (Data API defaults may be disabled).
grant usage on schema public to service_role;
grant select on public.inbox,public.marketing_consents,public.promotions to service_role;
grant select,delete on public.push_tokens to service_role;
grant select,insert,update on public.push_deliveries to service_role;
