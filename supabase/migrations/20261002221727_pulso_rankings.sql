alter table public.shops add column state text not null default '', add column country text not null default 'México';
create table public.reviews(
 appointment_id uuid primary key references public.appointments(id),
 customer_id uuid not null references public.profiles(id),
 shop_id uuid not null references public.shops(id),
 rating integer not null check(rating between 1 and 5),
 created_at timestamptz not null default now()
);
alter table public.reviews enable row level security;
grant select,insert on public.reviews to authenticated;
create policy review_read on public.reviews for select to authenticated using(customer_id=(select auth.uid()));
create policy review_insert on public.reviews for insert to authenticated with check(
 customer_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='client')
 and exists(select 1 from public.appointments a where a.id=appointment_id and a.customer_id=(select auth.uid()) and a.shop_id=reviews.shop_id and a.status='completed')
);
create index reviews_shop on public.reviews(shop_id);
create index completed_shop on public.appointments(shop_id) where status='completed';
-- Only aggregates leave this private implementation; never customer identities or revenue.
create function pulso_private.shop_rankings(p_scope text,p_country text,p_state text default '',p_municipality text default '')
returns table(shop_id uuid,name text,municipality text,state text,country text,visits bigint,rating numeric,reviews bigint,score numeric,"position" bigint)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and role='client') then raise exception 'Solo las cuentas de cliente pueden consultar este ranking';end if;
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
 ) select sc.*,dense_rank() over(order by sc.score desc) from scored sc order by sc.score desc,sc.name,sc.id limit 100;
end$$;
revoke all on function pulso_private.shop_rankings(text,text,text,text) from public,anon;
grant execute on function pulso_private.shop_rankings(text,text,text,text) to authenticated;
create function public.shop_rankings(p_scope text,p_country text,p_state text default '',p_municipality text default '')
returns table(shop_id uuid,name text,municipality text,state text,country text,visits bigint,rating numeric,reviews bigint,score numeric,"position" bigint)
language sql stable security invoker set search_path='' as $$select * from pulso_private.shop_rankings(p_scope,p_country,p_state,p_municipality)$$;
revoke all on function public.shop_rankings(text,text,text,text) from public,anon;
grant execute on function public.shop_rankings(text,text,text,text) to authenticated;
notify pgrst,'reload schema';
