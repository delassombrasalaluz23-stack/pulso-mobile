-- Qualify the outer object path: unqualified name inside the subquery meant shops.name.
alter policy portfolio_upload on storage.objects with check(bucket_id='portfolio' and split_part(storage.objects.name,'/',1)=public.active_uid()::text and exists(select 1 from public.shops sh where sh.id::text=split_part(storage.objects.name,'/',2) and sh.owner_id=public.active_uid()));

create table public.account_details(user_id uuid primary key references public.profiles,phone text not null default '' check(length(phone)<=30),city text not null default '' check(length(city)<=100),bio text not null default '' check(length(bio)<=300),payment_method text not null default 'paypal' check(payment_method in ('paypal','bank')),paypal_email text not null default '' check(length(paypal_email)<=254),bank_name text not null default '' check(length(bank_name)<=80),account_holder text not null default '' check(length(account_holder)<=100),bank_clabe text not null default '' check(bank_clabe='' or bank_clabe ~ '^[0-9]{18}$'));
alter table public.account_details enable row level security;
grant select,insert,update on public.account_details to authenticated;
create policy account_details_own on public.account_details for all to authenticated using(user_id=public.active_uid()) with check(user_id=public.active_uid());
-- These are unverified preferences/details, not connected payment-provider credentials.

create table public.haircut_records(appointment_id uuid primary key references public.appointments,customer_id uuid not null references public.profiles,shop_id uuid not null references public.shops,owner_id uuid not null references public.profiles,notes text not null default '' check(length(notes)<=1000),photo_path text,consent_at timestamptz,updated_at timestamptz not null default now());
alter table public.haircut_records enable row level security;
grant select on public.haircut_records to authenticated;
grant select,delete on public.haircut_records to service_role;
create policy haircut_read on public.haircut_records for select to authenticated using(public.active_uid() is not null and (customer_id=public.active_uid() or public.owns_shop(shop_id)));
create index haircut_customer_shop on public.haircut_records(customer_id,shop_id);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('haircut-records','haircut-records',false,5242880,array['image/jpeg']);
create function pulso_private.haircut_media_access(p_path text,p_write boolean default false) returns boolean language plpgsql stable security definer set search_path='' as $$declare a public.appointments;begin
 if pulso_private.active_uid() is null or p_path !~ '^[0-9a-f-]+/[0-9a-f-]+/[0-9a-f-]+\.jpg$' then return false;end if;
 select * into a from public.appointments where id::text=split_part(p_path,'/',2);
 if a.id is null or not exists(select 1 from public.shops where id=a.shop_id and owner_id::text=split_part(p_path,'/',1)) then return false;end if;
 if p_write then return public.owns_shop(a.shop_id) and a.status in ('arrived','completed') and exists(select 1 from public.profiles where id=a.customer_id and deleted_at is null);end if;
 return public.owns_shop(a.shop_id) or (a.customer_id=pulso_private.active_uid() and exists(select 1 from public.haircut_records where appointment_id=a.id and photo_path=p_path));
end$$;
create function public.haircut_media_access(p_path text,p_write boolean default false) returns boolean language sql stable security invoker set search_path='' as $$select pulso_private.haircut_media_access(p_path,p_write)$$;
revoke all on function public.haircut_media_access(text,boolean),pulso_private.haircut_media_access(text,boolean) from public,anon;grant execute on function public.haircut_media_access(text,boolean),pulso_private.haircut_media_access(text,boolean) to authenticated;
create policy haircut_upload on storage.objects for insert to authenticated with check(bucket_id='haircut-records' and public.haircut_media_access(name,true));
create policy haircut_download on storage.objects for select to authenticated using(bucket_id='haircut-records' and public.haircut_media_access(name,false));
create policy haircut_delete on storage.objects for delete to authenticated using(bucket_id='haircut-records' and split_part(name,'/',1)=public.active_uid()::text);
create function pulso_private.save_haircut(p_id uuid,p_notes text,p_photo text,p_consent boolean) returns void language plpgsql security definer set search_path='' as $$declare a public.appointments;begin
 select * into a from public.appointments where id=p_id for update;
 if a.id is null or not public.owns_shop(a.shop_id) or a.status not in ('arrived','completed') or not exists(select 1 from public.profiles where id=a.customer_id and deleted_at is null) then raise exception 'Solo puedes registrar cortes de tus clientes atendidos';end if;
 if p_photo is not null and (p_consent is distinct from true or not pulso_private.haircut_media_access(p_photo,true) or split_part(p_photo,'/',2)<>p_id::text or not exists(select 1 from storage.objects where bucket_id='haircut-records' and name=p_photo)) then raise exception 'Foto no válida o falta el permiso del cliente';end if;
 insert into public.haircut_records(appointment_id,customer_id,shop_id,owner_id,notes,photo_path,consent_at) values(a.id,a.customer_id,a.shop_id,pulso_private.active_uid(),btrim(p_notes),p_photo,case when p_photo is not null then now() end) on conflict(appointment_id) do update set notes=excluded.notes,photo_path=excluded.photo_path,consent_at=excluded.consent_at,updated_at=now();
end$$;
create function public.save_haircut(p_id uuid,p_notes text,p_photo text,p_consent boolean) returns void language sql security invoker set search_path='' as $$select pulso_private.save_haircut(p_id,p_notes,p_photo,p_consent)$$;
revoke all on function public.save_haircut(uuid,text,text,boolean),pulso_private.save_haircut(uuid,text,text,boolean) from public,anon;grant execute on function public.save_haircut(uuid,text,text,boolean),pulso_private.save_haircut(uuid,text,text,boolean) to authenticated;

create function pulso_private.ranking_regions() returns table(country text,state text,municipality text) language plpgsql stable security definer set search_path='' as $$begin
 if pulso_private.active_uid() is null then raise exception 'Inicia sesión';end if;
 return query select distinct s.country,s.state,s.municipality from public.shops s where s.active and btrim(s.state)<>'' and btrim(s.municipality)<>'' order by 1,2,3;
end$$;
create function public.ranking_regions() returns table(country text,state text,municipality text) language sql stable security invoker set search_path='' as $$select * from pulso_private.ranking_regions()$$;
revoke all on function public.ranking_regions(),pulso_private.ranking_regions() from public,anon;grant execute on function public.ranking_regions(),pulso_private.ranking_regions() to authenticated;
create or replace function pulso_private.shop_rankings(p_scope text,p_country text,p_state text default '',p_municipality text default '')
returns table(shop_id uuid,name text,municipality text,state text,country text,visits bigint,rating numeric,reviews bigint,score numeric,"position" bigint)
language plpgsql stable security definer set search_path='' as $$
begin
 if pulso_private.active_uid() is null or not exists(select 1 from public.profiles where id=pulso_private.active_uid() and role in ('client','owner')) then raise exception 'Inicia sesión para consultar el ranking';end if;
 if p_scope not in ('municipality','state','country') then raise exception 'Zona inválida';end if;
 return query with counts as (
 select a.shop_id,count(*) n from public.appointments a where a.status='completed' group by a.shop_id
 ), ratings as (
 select r.shop_id,count(*) n,avg(r.rating) avg_rating,sum(r.rating) total from public.reviews r join public.appointments a on a.id=r.appointment_id where a.status='completed' group by r.shop_id
 ), scored as (
 select s.id,s.name,s.municipality,s.state,s.country,c.n visits,r.avg_rating rating,coalesce(r.n,0) reviews,
 round(70*((coalesce(r.total,0)+15)::numeric/(coalesce(r.n,0)+5))/5 + 30*c.n::numeric/(c.n+20),2) score
 from public.shops s join counts c on c.shop_id=s.id left join ratings r on r.shop_id=s.id
 where s.active and btrim(s.state)<>'' and btrim(s.municipality)<>''
 and lower(btrim(s.country))=lower(btrim(p_country))
 and (p_scope='country' or lower(btrim(s.state))=lower(btrim(p_state)))
 and (p_scope<>'municipality' or lower(btrim(s.municipality))=lower(btrim(p_municipality)))
 ) , ranked as (select sc.*,dense_rank() over(order by sc.score desc) position,row_number() over(order by sc.score desc,sc.name,sc.id) display_order from scored sc)
 select r.id,r.name,r.municipality,r.state,r.country,r.visits,r.rating,r.reviews,r.score,r.position from ranked r where r.display_order<=100 or exists(select 1 from public.shops own where own.id=r.id and own.owner_id=pulso_private.active_uid()) order by r.display_order;
end$$;

-- Preserve account-closure semantics for the new private personal fields.
do $cleanup$ declare definition text;begin
 select pg_get_functiondef('pulso_private.admin_close_account(uuid)'::regprocedure) into definition;
 definition:=replace(definition,'delete from public.reviews where customer_id=p_user;', 'delete from public.reviews where customer_id=p_user; delete from public.account_details where user_id=p_user; update public.haircut_records set notes='''' where customer_id=p_user or owner_id=p_user;');
 execute definition;
end $cleanup$;
notify pgrst,'reload schema';
