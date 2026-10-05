-- Search today's first actual appointment per shop, using its local time zone.
create function pulso_private.available_today(p_shops uuid[])
returns table(shop_id uuid,barber_id uuid,service_id uuid,service_name text,starts_at timestamptz,price_cents integer,timezone text)
language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='client') then raise exception 'Solo clientes';end if;
 if cardinality(p_shops)>100 then raise exception 'Consulta hasta 100 locales por búsqueda';end if;
 return query select s.id,slot.bid,cut.id,cut.name,slot.starts_at,cut.price_cents,s.timezone
 from public.shops s
 cross join lateral(select v.id,v.name,v.duration_minutes,v.price_cents from public.services v where v.shop_id=s.id and v.active and v.kind='cut' order by v.duration_minutes,v.price_cents,v.id limit 1) cut
 cross join lateral(select b.id bid,t.starts_at from public.barbers b cross join lateral pulso_private.available_slots(b.id,(now() at time zone s.timezone)::date,cut.id,'{}'::uuid[]) t where b.shop_id=s.id and b.active order by t.starts_at,b.id limit 1) slot
 where s.id=any(p_shops) and s.active;
end$$;
revoke all on function pulso_private.available_today(uuid[]) from public,anon;
grant execute on function pulso_private.available_today(uuid[]) to authenticated;
create function public.available_today(p_shops uuid[])
returns table(shop_id uuid,barber_id uuid,service_id uuid,service_name text,starts_at timestamptz,price_cents integer,timezone text)
language sql stable security invoker set search_path='' as $$select * from pulso_private.available_today(p_shops)$$;
revoke all on function public.available_today(uuid[]) from public,anon;
grant execute on function public.available_today(uuid[]) to authenticated;

create table public.loyalty_programs(
 shop_id uuid primary key references public.shops(id),
 visits_required integer not null check(visits_required between 2 and 20),
 discount_cents integer not null check(discount_cents between 100 and 100000),
 enabled boolean not null default true,
 created_at timestamptz not null default now()
);
create table public.loyalty_stamps(
 appointment_id uuid primary key references public.appointments(id),
 shop_id uuid not null references public.loyalty_programs(shop_id),
 customer_id uuid not null references public.profiles(id),
 created_at timestamptz not null default now()
);
create index loyalty_stamps_customer_shop on public.loyalty_stamps(customer_id,shop_id);
create table public.loyalty_rewards(
 id uuid primary key default gen_random_uuid(),
 shop_id uuid not null references public.loyalty_programs(shop_id),
 customer_id uuid not null references public.profiles(id),
 discount_cents integer not null check(discount_cents>0),
 earned_appointment_id uuid not null unique references public.appointments(id),
 used_appointment_id uuid unique references public.appointments(id),
 created_at timestamptz not null default now()
);
create index loyalty_rewards_customer on public.loyalty_rewards(customer_id,shop_id);
alter table public.appointments add column loyalty_reward_id uuid references public.loyalty_rewards(id), add column discount_cents integer not null default 0 check(discount_cents>=0);
alter table public.loyalty_programs enable row level security;
alter table public.loyalty_stamps enable row level security;
alter table public.loyalty_rewards enable row level security;
grant select on public.loyalty_programs,public.loyalty_stamps,public.loyalty_rewards to authenticated;
-- Writes go through checked functions only, including program settings.
revoke insert,update,delete on public.loyalty_programs,public.loyalty_stamps,public.loyalty_rewards from anon,authenticated;
create policy loyalty_program_read on public.loyalty_programs for select to authenticated using(public.owns_shop(shop_id) or exists(select 1 from public.profiles where id=(select auth.uid()) and role='client'));
create policy loyalty_stamp_read on public.loyalty_stamps for select to authenticated using(customer_id=(select auth.uid()) or public.owns_shop(shop_id));
create policy loyalty_reward_read on public.loyalty_rewards for select to authenticated using(customer_id=(select auth.uid()) or public.owns_shop(shop_id));
create function pulso_private.save_loyalty(p_shop uuid,p_visits integer,p_discount integer,p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
declare p public.loyalty_programs;begin
 if not public.owns_shop(p_shop) then raise exception 'Solo puedes configurar tu barbería';end if;
 perform pg_advisory_xact_lock(hashtextextended('loyalty:'||p_shop::text,0));
 select * into p from public.loyalty_programs where shop_id=p_shop for update;
 if p.shop_id is not null and (p.visits_required<>p_visits or p.discount_cents<>p_discount) and exists(select 1 from public.loyalty_stamps where shop_id=p_shop) then raise exception 'Ya hay visitas acumuladas. Conserva la meta y el beneficio; puedes activar o pausar el programa.';end if;
 insert into public.loyalty_programs(shop_id,visits_required,discount_cents,enabled) values(p_shop,p_visits,p_discount,p_enabled) on conflict(shop_id) do update set visits_required=excluded.visits_required,discount_cents=excluded.discount_cents,enabled=excluded.enabled;
end$$;
revoke all on function pulso_private.save_loyalty(uuid,integer,integer,boolean) from public,anon;
grant execute on function pulso_private.save_loyalty(uuid,integer,integer,boolean) to authenticated;
create function public.save_loyalty(p_shop uuid,p_visits integer,p_discount integer,p_enabled boolean) returns void language sql security invoker set search_path='' as $$select pulso_private.save_loyalty(p_shop,p_visits,p_discount,p_enabled)$$;
revoke all on function public.save_loyalty(uuid,integer,integer,boolean) from public,anon;
grant execute on function public.save_loyalty(uuid,integer,integer,boolean) to authenticated;

-- One stamp per completed appointment, no historical backfill and no cancelled/no-show stamps.
create function pulso_private.loyalty_transition() returns trigger language plpgsql security definer set search_path='' as $$
declare p public.loyalty_programs;n bigint;begin
 if new.status=old.status then return new;end if;
 if new.status='cancelled' then
  update public.loyalty_rewards set used_appointment_id=null where used_appointment_id=new.id;
 elsif new.status='completed' then
  perform pg_advisory_xact_lock(hashtextextended('loyalty:'||new.shop_id::text,0));
  select * into p from public.loyalty_programs where shop_id=new.shop_id and enabled for update;
  if p.shop_id is not null then
   insert into public.loyalty_stamps(appointment_id,shop_id,customer_id) values(new.id,new.shop_id,new.customer_id) on conflict do nothing;
   if found then
    select count(*) into n from public.loyalty_stamps where shop_id=new.shop_id and customer_id=new.customer_id;
    if n%p.visits_required=0 then insert into public.loyalty_rewards(shop_id,customer_id,discount_cents,earned_appointment_id) values(new.shop_id,new.customer_id,p.discount_cents,new.id);end if;
   end if;
  end if;
 end if;
 return new;
end$$;
revoke all on function pulso_private.loyalty_transition() from public,anon,authenticated;
create trigger loyalty_visit after update of status on public.appointments for each row execute function pulso_private.loyalty_transition();

-- Validate the reward on the server and use the existing booking lock, price and overlap checks.
create function pulso_private.book_with_reward(p_barber uuid,p_service uuid,p_addons uuid[],p_start timestamptz,p_expected_total integer,p_expected_deposit integer,p_expected_cancel integer,p_accept boolean,p_reward uuid,p_expected_discount integer) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.loyalty_rewards;v public.services;booking uuid;discount integer;begin
 if p_expected_total is null or p_expected_total<0 or p_expected_deposit is null or p_expected_cancel is null then raise exception 'Revisa el precio y las condiciones de la reserva';end if;
 if not exists(select 1 from public.profiles where id=auth.uid() and role='client') then raise exception 'Solo clientes';end if;
 select * into r from public.loyalty_rewards where id=p_reward and customer_id=auth.uid() for update;
 select * into v from public.services where id=p_service;
 if r.id is null or r.used_appointment_id is not null or r.shop_id is distinct from v.shop_id then raise exception 'La recompensa no está disponible para esta reserva';end if;
 discount:=least(r.discount_cents,p_expected_total);
 if discount is distinct from p_expected_discount then raise exception 'El descuento cambió. Revisa tu reserva.';end if;
 booking:=pulso_private.book_appointment(p_barber,p_service,p_addons,p_start,p_expected_total,p_expected_deposit,p_expected_cancel,p_accept);
 update public.appointments set loyalty_reward_id=r.id,discount_cents=discount,total_cents=total_cents-discount,deposit_cents=round((total_cents-discount)*p_expected_deposit/100.0)::integer where id=booking;
 update public.loyalty_rewards set used_appointment_id=booking where id=r.id;
 return booking;
end$$;
revoke all on function pulso_private.book_with_reward(uuid,uuid,uuid[],timestamptz,integer,integer,integer,boolean,uuid,integer) from public,anon;
grant execute on function pulso_private.book_with_reward(uuid,uuid,uuid[],timestamptz,integer,integer,integer,boolean,uuid,integer) to authenticated;
create function public.book_with_reward(p_barber uuid,p_service uuid,p_addons uuid[],p_start timestamptz,p_expected_total integer,p_expected_deposit integer,p_expected_cancel integer,p_accept boolean,p_reward uuid,p_expected_discount integer) returns uuid language sql security invoker set search_path='' as $$select pulso_private.book_with_reward(p_barber,p_service,p_addons,p_start,p_expected_total,p_expected_deposit,p_expected_cancel,p_accept,p_reward,p_expected_discount)$$;
revoke all on function public.book_with_reward(uuid,uuid,uuid[],timestamptz,integer,integer,integer,boolean,uuid,integer) from public,anon;
grant execute on function public.book_with_reward(uuid,uuid,uuid[],timestamptz,integer,integer,integer,boolean,uuid,integer) to authenticated;
notify pgrst,'reload schema';
