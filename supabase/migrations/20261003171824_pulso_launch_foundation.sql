-- Administrative rights are assigned out of band, never by profile metadata.
create table pulso_private.admin_members(user_id uuid primary key references public.profiles,created_at timestamptz not null default now());
create table pulso_private.account_suspensions(user_id uuid primary key references public.profiles,reason text not null,created_at timestamptz not null default now());
create table public.shop_trust(shop_id uuid primary key references public.shops,verified_at timestamptz,suspended boolean not null default false,review_note text not null default '');
alter table public.shop_trust enable row level security;
grant select(shop_id,verified_at,suspended) on public.shop_trust to authenticated;
create policy trust_read on public.shop_trust for select to authenticated using(public.active_uid() is not null);
create table pulso_private.admin_audit(id uuid primary key default gen_random_uuid(),actor uuid,action text,target uuid,note text,created_at timestamptz default now());
create or replace function pulso_private.active_uid() returns uuid language sql stable security definer set search_path='' as $$select auth.uid() where exists(select 1 from auth.users where id=auth.uid()) and not exists(select 1 from public.profiles where id=auth.uid() and deleted_at is not null) and not exists(select 1 from pulso_private.account_suspensions where user_id=auth.uid())$$;
create function pulso_private.is_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from pulso_private.admin_members where user_id=pulso_private.active_uid())$$;
create function pulso_private.shop_visible(p_shop uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.shops s where s.id=p_shop and s.active and not exists(select 1 from public.shop_trust t where t.shop_id=s.id and t.suspended) and not exists(select 1 from pulso_private.account_suspensions x where x.user_id=s.owner_id))$$;
-- Curated public catalogue: no customer, payment, owner identity or appointment data.
create function pulso_private.public_catalog(p_shop uuid default null) returns jsonb language sql stable security definer set search_path='' as $$
with chosen as(select s.* from public.shops s where (p_shop is null or s.id=p_shop) and pulso_private.shop_visible(s.id) order by s.name,s.id limit 500)
select jsonb_build_object('shops',coalesce((select jsonb_agg((to_jsonb(s)-'owner_id')||jsonb_build_object('verified',exists(select 1 from public.shop_trust t where t.shop_id=s.id and t.verified_at is not null))) from chosen s),'[]'::jsonb),'photos',coalesce((select jsonb_agg(to_jsonb(p)) from public.photos p join chosen s on s.id=p.shop_id),'[]'::jsonb),'services',coalesce((select jsonb_agg(to_jsonb(v)) from public.services v join chosen s on s.id=v.shop_id where v.active),'[]'::jsonb),'barbers',coalesce((select jsonb_agg(to_jsonb(b)) from public.barbers b join chosen s on s.id=b.shop_id where b.active),'[]'::jsonb))$$;


create table public.support_tickets(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles,kind text not null check(kind in ('appointment','shop','review','photo','general')),target_id uuid,shop_id uuid references public.shops,subject text not null check(length(btrim(subject)) between 3 and 120),description text not null check(length(btrim(description)) between 10 and 2000),status text not null default 'open' check(status in ('open','reviewing','resolved')),reply text not null default '',created_at timestamptz not null default now(),updated_at timestamptz not null default now());
alter table public.support_tickets enable row level security;
grant select on public.support_tickets to authenticated;
create policy support_own on public.support_tickets for select to authenticated using(user_id=public.active_uid());
create index support_owner_date on public.support_tickets(user_id,created_at desc);
create function pulso_private.create_support(p_kind text,p_target uuid,p_subject text,p_description text) returns uuid language plpgsql security definer set search_path='' as $$declare sh uuid;tid uuid;begin
 if pulso_private.active_uid() is null then raise exception 'Inicia sesión';end if;
 if (select count(*) from public.support_tickets where user_id=pulso_private.active_uid() and created_at>now()-interval '1 day')>=10 then raise exception 'Ya enviaste diez solicitudes hoy';end if;
 if p_kind='appointment' then select shop_id into sh from public.appointments where id=p_target and (customer_id=pulso_private.active_uid() or public.owns_shop(shop_id));
 elsif p_kind='shop' then select id into sh from public.shops where id=p_target and pulso_private.shop_visible(id);
 elsif p_kind='review' then select shop_id into sh from public.reviews where appointment_id=p_target and pulso_private.shop_visible(shop_id);
 elsif p_kind='photo' then select shop_id into sh from public.photos where id=p_target and pulso_private.shop_visible(shop_id);
 elsif p_kind<>'general' then raise exception 'Tipo de reporte inválido';end if;
 if p_kind<>'general' and sh is null then raise exception 'No puedes reportar este elemento';end if;
 insert into public.support_tickets(user_id,kind,target_id,shop_id,subject,description) values(pulso_private.active_uid(),p_kind,p_target,sh,btrim(p_subject),btrim(p_description)) returning id into tid;return tid;
end$$;
create function pulso_private.admin_overview(p_search text default '',p_page integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not pulso_private.is_admin() then raise exception 'Acceso solo para administración';end if;
 return jsonb_build_object('shops',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select s.id,s.owner_id,s.name,s.address,s.municipality,s.active,t.verified_at,coalesce(t.suspended,false) suspended from public.shops s left join public.shop_trust t on t.shop_id=s.id where s.name ilike '%'||left(p_search,100)||'%' order by s.name,s.id limit 50 offset greatest(p_page,0)*50)x),'tickets',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select t.*,case when t.kind='appointment' then (select jsonb_build_object('customer',a.customer_name,'shop',a.shop_name,'barber',a.barber_name,'starts_at',a.starts_at,'status',a.status,'total_cents',a.total_cents,'deposit_cents',a.deposit_cents,'payment_mode',a.payment_mode,'outcome',a.outcome) from public.appointments a where a.id=t.target_id) when t.kind='photo' then (select jsonb_build_object('photo_path',p.storage_path,'caption',p.caption) from public.photos p where p.id=t.target_id) when t.kind='review' then (select jsonb_build_object('comment',r.comment,'rating',r.rating,'review_photo',r.photo_path) from public.reviews r where r.appointment_id=t.target_id) end context from public.support_tickets t order by (status='resolved'),created_at desc limit 50 offset greatest(p_page,0)*50)x),'users',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select p.id,p.name,p.role,exists(select 1 from pulso_private.account_suspensions x where x.user_id=p.id) suspended from public.profiles p where p.deleted_at is null and p.name ilike '%'||left(p_search,100)||'%' order by p.name,p.id limit 50 offset greatest(p_page,0)*50)x));
end$$;
create function pulso_private.admin_action(p_action text,p_target uuid,p_note text) returns void language plpgsql security definer set search_path='' as $$begin
 if not pulso_private.is_admin() then raise exception 'Acceso solo para administración';end if;
 if length(btrim(p_note)) not between 10 and 2000 then raise exception 'Describe el motivo o la revisión realizada (10–2000 caracteres)';end if;
 if p_action in ('verify','unverify','suspend_shop','restore_shop') then
  if not exists(select 1 from public.shops where id=p_target) then raise exception 'Barbería no encontrada';end if;
  insert into public.shop_trust(shop_id) values(p_target) on conflict do nothing;
  update public.shop_trust set verified_at=case when p_action='verify' then now() when p_action='unverify' then null else verified_at end,suspended=case when p_action='suspend_shop' then true when p_action='restore_shop' then false else suspended end,review_note=p_note where shop_id=p_target;
 elsif p_action in ('suspend_user','restore_user') then
  if p_target=pulso_private.active_uid() or exists(select 1 from pulso_private.admin_members where user_id=p_target) then raise exception 'No puedes suspender una cuenta administrativa';end if;
  if p_action='suspend_user' then insert into pulso_private.account_suspensions(user_id,reason) values(p_target,p_note) on conflict(user_id) do update set reason=excluded.reason;else delete from pulso_private.account_suspensions where user_id=p_target;end if;
 elsif p_action in ('reply','resolve') then update public.support_tickets set reply=p_note,status=case when p_action='resolve' then 'resolved' else 'reviewing' end,updated_at=now() where id=p_target;
 elsif p_action='cancel_appointment' then update public.appointments set status='cancelled',outcome=case when payment_mode='stripe' then 'refund_pending' else 'refund_simulated' end where id=p_target and status in ('confirmed','arrived','pending_payment');
 elsif p_action='hide_photo' then delete from public.photos where id=p_target;
 elsif p_action='hide_review' then delete from public.reviews where appointment_id=p_target;
 else raise exception 'Acción inválida';end if;
 insert into pulso_private.admin_audit(actor,action,target,note) values(pulso_private.active_uid(),p_action,p_target,p_note);
end$$;
-- Arrival secrets are never columns in the appointment row that owners can read.
create table pulso_private.arrival_codes(appointment_id uuid primary key references public.appointments,code text not null,attempts integer not null default 0,locked_until timestamptz,used_at timestamptz);
create function pulso_private.arrival_code(p_id uuid) returns text language plpgsql security definer set search_path='' as $$declare a public.appointments;c text;begin
 select * into a from public.appointments where id=p_id;
 if a.customer_id is distinct from pulso_private.active_uid() or a.status<>'confirmed' then raise exception 'Código disponible solo para el titular de una cita confirmada';end if;
 insert into pulso_private.arrival_codes(appointment_id,code) values(p_id,lpad(((('x'||substr(replace(gen_random_uuid()::text,'-',''),1,8))::bit(32)::bigint)%1000000)::text,6,'0')) on conflict do nothing;
 select code into c from pulso_private.arrival_codes where appointment_id=p_id;return c;
end$$;
create function pulso_private.confirm_arrival(p_id uuid,p_code text) returns boolean language plpgsql security definer set search_path='' as $$declare a public.appointments;c pulso_private.arrival_codes;begin
 select * into a from public.appointments where id=p_id for update;
 if not public.owns_shop(a.shop_id) or a.status<>'confirmed' or now()<a.starts_at-interval '20 minutes' or now()>a.ends_at+interval '2 hours' then raise exception 'No se puede confirmar la llegada en este momento';end if;
 select * into c from pulso_private.arrival_codes where appointment_id=p_id for update;
 if c.appointment_id is null then return false;end if;
 if c.locked_until>now() then raise exception 'Demasiados intentos. Espera 15 minutos';end if;
 if c.code is distinct from p_code then update pulso_private.arrival_codes set attempts=case when attempts>=4 then 0 else attempts+1 end,locked_until=case when attempts>=4 then now()+interval '15 minutes' end where appointment_id=p_id;return false;end if;
 update pulso_private.arrival_codes set used_at=now() where appointment_id=p_id;
 update public.appointments set status='arrived' where id=p_id;
 delete from public.location_sessions where appointment_id=p_id;delete from public.live_locations where appointment_id=p_id;return true;
end$$;
-- Server booking guard prevents suspended shops from accepting any route of booking.
create function pulso_private.guard_shop_booking() returns trigger language plpgsql security definer set search_path='' as $$begin if not pulso_private.shop_visible(new.shop_id) then raise exception 'Barbería no disponible';end if;return new;end$$;
create trigger guard_shop_booking before insert on public.appointments for each row execute function pulso_private.guard_shop_booking();
-- Route all new arrivals through the code, including legacy clients.
do $$declare d text;begin select pg_get_functiondef('pulso_private.transition_appointment(uuid,text)'::regprocedure) into d;
d:=replace(d,'is_owner:=public.owns_shop(a.shop_id);','is_owner:=public.owns_shop(a.shop_id); if p_action=''arrived'' then raise exception ''Confirma la llegada con el código del cliente'';end if; if p_action=''complete'' and a.status<>''arrived'' then raise exception ''Primero confirma la llegada con el código'';end if;');execute d;end$$;

-- Stripe Connect activation is server-side and starts disabled until onboarding is verified.
create table pulso_private.payment_accounts(shop_id uuid primary key references public.shops,stripe_account text unique not null,charges_enabled boolean not null default false,payouts_enabled boolean not null default false);
create table public.payments(appointment_id uuid primary key references public.appointments,request_id uuid unique not null,customer_id uuid not null references public.profiles,shop_id uuid not null references public.shops,amount_cents integer not null check(amount_cents>=0),currency text not null default 'mxn' check(currency='mxn'),state text not null default 'created' check(state in ('created','paid','refund_pending','refunded','refund_failed')),checkout_id text unique,checkout_url text,payment_intent text unique,receipt_url text,refund_id text,created_at timestamptz not null default now());
alter table public.payments enable row level security;
grant select on public.payments to authenticated;
create policy payment_read on public.payments for select to authenticated using(public.active_uid() is not null and (customer_id=public.active_uid() or public.owns_shop(shop_id)));
create table pulso_private.payment_events(event_id text primary key,created_at timestamptz default now());
alter table public.appointments drop constraint appointments_status_check,drop constraint appointments_payment_mode_check;
alter table public.appointments add constraint appointments_status_check check(status in ('pending_payment','confirmed','arrived','completed','cancelled','no_show')),add constraint appointments_payment_mode_check check(payment_mode in ('simulation','stripe','no_charge')),add column payment_expires_at timestamptz;
create function pulso_private.payment_ready(p_shop uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from pulso_private.payment_accounts where shop_id=p_shop and charges_enabled and payouts_enabled)$$;
create function pulso_private.prepare_checkout(p_request uuid,p_barber uuid,p_service uuid,p_addons uuid[],p_start timestamptz,p_expected_total integer,p_expected_deposit integer,p_expected_cancel integer,p_accept boolean,p_offer uuid default null,p_reward uuid default null,p_expected_discount integer default 0) returns uuid language plpgsql security definer set search_path='' as $$declare sh uuid;booking uuid;existing public.payments;begin
 if pulso_private.active_uid() is null then raise exception 'Inicia sesión';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request::text,0));
 select * into existing from public.payments where request_id=p_request;
 if found then if existing.customer_id<>pulso_private.active_uid() then raise exception 'Solicitud no válida';end if;return existing.appointment_id;end if;
 if (select count(*) from public.appointments where customer_id=pulso_private.active_uid() and status='pending_payment' and payment_expires_at>now())>=3 then raise exception 'Completa o deja caducar tus pagos pendientes';end if;
 select shop_id into sh from public.barbers where id=p_barber;
 if not pulso_private.payment_ready(sh) then raise exception 'Esta barbería todavía no tiene cobros activados';end if;
 if p_start<now()+interval '40 minutes' then raise exception 'Elige un horario con al menos 40 minutos de anticipación para pagar';end if;
 if p_offer is not null and p_reward is not null then raise exception 'No se combinan descuentos';end if;
 perform set_config('pulso.checkout','true',true);
 if p_offer is not null then booking:=pulso_private.book_with_offer(p_barber,p_service,p_addons,p_start,p_expected_total,p_expected_deposit,p_expected_cancel,p_accept,p_offer,p_expected_discount);
 elsif p_reward is not null then booking:=pulso_private.book_with_reward(p_barber,p_service,p_addons,p_start,p_expected_total,p_expected_deposit,p_expected_cancel,p_accept,p_reward,p_expected_discount);
 else booking:=pulso_private.book_appointment(p_barber,p_service,p_addons,p_start,p_expected_total,p_expected_deposit,p_expected_cancel,p_accept);end if;
 perform set_config('pulso.checkout','false',true);
 update public.appointments set status='pending_payment',payment_mode='stripe',outcome='awaiting_payment',payment_expires_at=now()+interval '35 minutes' where id=booking;
 insert into public.payments(appointment_id,request_id,customer_id,shop_id,amount_cents) select id,p_request,customer_id,shop_id,deposit_cents from public.appointments where id=booking;
 if (select amount_cents=0 from public.payments where appointment_id=booking) then update public.appointments set status='confirmed',payment_mode='no_charge',outcome='no_deposit_due' where id=booking;update public.payments set state='paid' where appointment_id=booking;end if;
 return booking;
end$$;
create or replace function pulso_private.guard_shop_booking() returns trigger language plpgsql security definer set search_path='' as $$begin
 if not pulso_private.shop_visible(new.shop_id) then raise exception 'Barbería no disponible';end if;
 if pulso_private.payment_ready(new.shop_id) and current_setting('pulso.checkout',true) is distinct from 'true' then raise exception 'Confirma esta reserva mediante el pago del anticipo';end if;return new;end$$;
-- Expired holds don't block availability; the payment webhook checks occupancy again.
do $$declare f record;d text;begin
 for f in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='pulso_private' and p.proname in ('available_slots','reschedule_slots') loop
 d:=pg_get_functiondef(f.oid);d:=replace(d,'a.status in (''confirmed'',''arrived'')','(a.status in (''confirmed'',''arrived'') or (a.status=''pending_payment'' and a.payment_expires_at>now()))');d:=replace(d,'b.status in (''confirmed'',''arrived'')','(b.status in (''confirmed'',''arrived'') or (b.status=''pending_payment'' and b.payment_expires_at>now()))');execute d;end loop;
end$$;
create function pulso_private.settle_payment(p_event text,p_checkout text,p_intent text,p_amount integer,p_currency text,p_receipt text) returns void language plpgsql security definer set search_path='' as $$declare p public.payments;a public.appointments;begin
 select * into p from public.payments where checkout_id=p_checkout for update;if not found then raise exception 'Pago desconocido; reintentar';end if;
 if p.amount_cents<>p_amount or p_currency<>'mxn' then raise exception 'Importe o moneda inesperados';end if;
 insert into pulso_private.payment_events(event_id) values(p_event) on conflict do nothing;if not found then return;end if;
 if p.state<>'created' then return;end if;
 select * into a from public.appointments where id=p.appointment_id for update;
 perform pg_advisory_xact_lock(hashtextextended(a.barber_id::text,0));
 if a.status<>'pending_payment' or a.starts_at<=now() or not pulso_private.shop_visible(a.shop_id) or exists(select 1 from public.appointments x where x.id<>a.id and x.barber_id=a.barber_id and (x.status in ('confirmed','arrived') or (x.status='pending_payment' and x.payment_expires_at>now())) and tstzrange(x.starts_at,x.ends_at,'[)')&&tstzrange(a.starts_at,a.ends_at,'[)')) then
 update public.payments set state='refund_pending',payment_intent=p_intent,receipt_url=p_receipt where appointment_id=a.id;
 update public.appointments set status='cancelled',outcome='refund_pending' where id=a.id;
 else update public.payments set state='paid',payment_intent=p_intent,receipt_url=p_receipt where appointment_id=a.id;
 update public.appointments set status='confirmed',outcome='deposit_paid' where id=a.id;end if;
end$$;
create function pulso_private.real_payment_outcome() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.payment_mode='stripe' and new.status in ('cancelled','completed','no_show') then
 new.outcome:=case when new.outcome in ('refund_simulated','refund_pending') then 'refund_pending' when new.status='completed' then 'deposit_applied' when new.status='no_show' or new.outcome='forfeit_simulated' then 'deposit_retained' else new.outcome end;
 if new.outcome='refund_pending' then update public.payments set state='refund_pending' where appointment_id=new.id and state='paid';end if;
 end if;return new;end$$;
create trigger real_payment_outcome before update of status,outcome on public.appointments for each row execute function pulso_private.real_payment_outcome();

-- Transactional inbox/outbox. Push delivery is separated from booking commits.
create table public.booking_notifications(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles,appointment_id uuid references public.appointments,title text not null,body text not null,dedupe text unique not null,read_at timestamptz,created_at timestamptz not null default now());
alter table public.booking_notifications enable row level security;
grant select,update(read_at) on public.booking_notifications to authenticated;
create policy booking_notice_read on public.booking_notifications for select to authenticated using(user_id=public.active_uid());
create policy booking_notice_update on public.booking_notifications for update to authenticated using(user_id=public.active_uid()) with check(user_id=public.active_uid());
create table pulso_private.push_jobs(id uuid primary key default gen_random_uuid(),notice_id uuid references public.booking_notifications,token text not null,state text not null default 'pending',attempts integer not null default 0,available_at timestamptz default now(),ticket_id text,error text,unique(notice_id,token));
create function pulso_private.queue_booking_notice() returns trigger language plpgsql security definer set search_path='' as $$declare u uuid;v text;begin
 if new.status='pending_payment' or (tg_op='UPDATE' and new.status=old.status and new.starts_at=old.starts_at) then return new;end if;
 for u in select new.customer_id union select owner_id from public.shops where id=new.shop_id loop
 v:=new.id::text||':'||u::text||':'||new.status||':'||new.starts_at::text;
 insert into public.booking_notifications(user_id,appointment_id,title,body,dedupe) values(u,new.id,'Actualización de tu cita','Abre Pulso para revisar la reserva y sus detalles.',v) on conflict do nothing;end loop;return new;
end$$;
create trigger queue_booking_notice after insert or update of status,starts_at on public.appointments for each row execute function pulso_private.queue_booking_notice();
create table pulso_private.worker_credentials(token uuid primary key default gen_random_uuid());
insert into pulso_private.worker_credentials default values;
create function pulso_private.worker_authorized(p_token text) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from pulso_private.worker_credentials where token::text=p_token)$$;
create function pulso_private.claim_push_jobs() returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 update public.appointments set status='cancelled',outcome='payment_expired' where status='pending_payment' and payment_expires_at<now();
 insert into public.booking_notifications(user_id,appointment_id,title,body,dedupe)
 select a.customer_id,a.id,'Tu cita se acerca','Abre Pulso para ver el horario y cómo llegar.',a.id::text||':reminder:'||a.starts_at::text||':'||h.n::text
 from public.appointments a cross join (values(1),(24))h(n) where a.status='confirmed' and a.starts_at between now()+make_interval(hours=>h.n)-interval '5 minutes' and now()+make_interval(hours=>h.n)
 on conflict do nothing;
 insert into pulso_private.push_jobs(notice_id,token) select n.id,t.token from public.booking_notifications n join public.push_tokens t on t.user_id=n.user_id join public.profiles p on p.id=n.user_id and p.deleted_at is null where n.created_at>now()-interval '1 day' and not exists(select 1 from pulso_private.account_suspensions x where x.user_id=n.user_id) and (n.appointment_id is null or exists(select 1 from public.appointments a where a.id=n.appointment_id and a.status<>'pending_payment')) on conflict do nothing;
 update pulso_private.push_jobs j set state='obsolete' from public.booking_notifications n,public.appointments a where j.notice_id=n.id and a.id=n.appointment_id and j.state in ('pending','retry') and n.dedupe like '%:reminder:%' and (a.status<>'confirmed' or n.dedupe not like '%'||a.starts_at::text||'%');
 with picked as(select id from pulso_private.push_jobs where state in ('pending','retry','sending') and available_at<=now() and attempts<5 order by available_at limit 100 for update skip locked), claimed as(update pulso_private.push_jobs j set state='sending',attempts=attempts+1,available_at=now()+interval '5 minutes' from picked p where j.id=p.id returning j.*) select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'token',c.token,'title',n.title,'body',n.body,'appointment_id',n.appointment_id)),'[]'::jsonb) into result from claimed c join public.booking_notifications n on n.id=c.notice_id;return result;
end$$;
create function pulso_private.finish_push_job(p_id uuid,p_ticket text,p_error text,p_dead boolean default false) returns void language plpgsql security definer set search_path='' as $$begin
 update pulso_private.push_jobs set state=case when p_ticket is not null then 'sent' when p_dead then 'failed' else 'retry' end,ticket_id=p_ticket,error=left(p_error,500),available_at=now()+interval '5 minutes' where id=p_id;
 if p_dead then delete from public.push_tokens where token=(select token from pulso_private.push_jobs where id=p_id);end if;
end$$;
-- Expose only explicit wrappers; administrative and worker functions remain server-only.
do $$declare f record;args text;begin
 for f in select p.proname,p.oid,pg_get_function_identity_arguments(p.oid) ident,pg_get_function_arguments(p.oid) fullargs,pg_get_function_result(p.oid) result,p.proargnames,p.provolatile from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='pulso_private' and p.proname=any(array['is_admin','shop_visible','public_catalog','create_support','admin_overview','admin_action','arrival_code','confirm_arrival','payment_ready','prepare_checkout','settle_payment','worker_authorized','claim_push_jobs','finish_push_job']) loop
 select string_agg(quote_ident(x),',') into args from unnest(f.proargnames)x;
 execute format('create function public.%I(%s) returns %s language sql %s security invoker set search_path='''' as %L',f.proname,f.fullargs,f.result,case when f.provolatile='s' then 'stable' else 'volatile' end,'select pulso_private.'||f.proname||'('||coalesce(args,'')||')');
 execute format('revoke all on function public.%I(%s),pulso_private.%I(%s) from public,anon,authenticated',f.proname,f.ident,f.proname,f.ident);
 if f.proname in ('settle_payment','worker_authorized','claim_push_jobs','finish_push_job') then execute format('grant execute on function public.%I(%s),pulso_private.%I(%s) to service_role',f.proname,f.ident,f.proname,f.ident);
 else execute format('grant execute on function public.%I(%s),pulso_private.%I(%s) to authenticated',f.proname,f.ident,f.proname,f.ident);end if;
 end loop;
end$$;
grant usage on schema pulso_private to anon;
grant execute on function public.public_catalog(uuid),pulso_private.public_catalog(uuid) to anon;
revoke all on all tables in schema pulso_private from anon,authenticated;
grant all on public.payments,public.booking_notifications to service_role;
-- Service-only configuration interface; no financial details in public discovery.
create function pulso_private.payment_account(p_shop uuid) returns jsonb language sql security definer set search_path='' as $$select to_jsonb(p) from pulso_private.payment_accounts p where shop_id=p_shop$$;
create function public.payment_account(p_shop uuid) returns jsonb language sql security invoker set search_path='' as $$select pulso_private.payment_account(p_shop)$$;
revoke all on function public.payment_account(uuid) from public,anon,authenticated;grant execute on function public.payment_account(uuid) to service_role;
create function pulso_private.save_payment_account(p_shop uuid,p_account text,p_charges boolean,p_payouts boolean) returns void language sql security definer set search_path='' as $$insert into pulso_private.payment_accounts values(p_shop,p_account,p_charges,p_payouts) on conflict(shop_id) do update set stripe_account=excluded.stripe_account,charges_enabled=excluded.charges_enabled,payouts_enabled=excluded.payouts_enabled$$;
create function public.save_payment_account(p_shop uuid,p_account text,p_charges boolean,p_payouts boolean) returns void language sql security invoker set search_path='' as $$select pulso_private.save_payment_account(p_shop,p_account,p_charges,p_payouts)$$;
revoke all on function public.save_payment_account(uuid,text,boolean,boolean) from public,anon,authenticated;grant execute on function public.save_payment_account(uuid,text,boolean,boolean) to service_role;
notify pgrst,'reload schema';

create policy shop_moderation on public.shops as restrictive for select to authenticated using(owner_id=public.active_uid() or public.shop_visible(id));

revoke all on function pulso_private.payment_account(uuid) from public,anon,authenticated;grant execute on function pulso_private.payment_account(uuid) to service_role;

revoke all on function pulso_private.save_payment_account(uuid,text,boolean,boolean) from public,anon,authenticated;grant execute on function pulso_private.save_payment_account(uuid,text,boolean,boolean) to service_role;

do $$declare f record;d text;begin
for f in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='pulso_private' and p.proname in ('shop_rankings','ranking_regions','available_slots','available_today') loop
 d:=pg_get_functiondef(f.oid);d:=replace(d,'where s.active and','where s.active and pulso_private.shop_visible(s.id) and');d:=replace(d,'and sh.active and','and sh.active and pulso_private.shop_visible(sh.id) and');execute d;
end loop;end$$;
-- Anonymous access cannot use the internal admin, trigger, or code tables/functions.
revoke all on function pulso_private.guard_shop_booking(),pulso_private.real_payment_outcome(),pulso_private.queue_booking_notice() from public,anon,authenticated;

-- Account removal cleans new personal records; financial ledger remains for reconciliation.
do $$declare d text;begin select pg_get_functiondef('pulso_private.admin_close_account(uuid)'::regprocedure) into d;
d:=replace(d,'delete from public.reviews where customer_id=p_user;', 'delete from public.reviews where customer_id=p_user; delete from public.support_tickets where user_id=p_user; delete from pulso_private.push_jobs where notice_id in(select id from public.booking_notifications where user_id=p_user); delete from public.booking_notifications where user_id=p_user; delete from pulso_private.arrival_codes where appointment_id in(select id from public.appointments where customer_id=p_user);');
d:=replace(d,'status in (''confirmed'',''arrived'')','status in (''confirmed'',''arrived'',''pending_payment'')');execute d;end$$;
do $$declare t record;begin for t in select tablename from pg_tables where schemaname='pulso_private' loop execute format('alter table pulso_private.%I enable row level security',t.tablename);end loop;end$$;
create function pulso_private.push_receipts() returns jsonb language sql stable security definer set search_path='' as $$select coalesce(jsonb_agg(x),'[]'::jsonb) from(select id,ticket_id from pulso_private.push_jobs where state='sent' and available_at<now() limit 100)x$$;
create function pulso_private.finish_push_receipt(p_id uuid,p_error text) returns void language plpgsql security definer set search_path='' as $$begin update pulso_private.push_jobs set state=case when p_error is null then 'delivered' else 'failed' end,error=p_error where id=p_id;if p_error='DeviceNotRegistered' then delete from public.push_tokens where token=(select token from pulso_private.push_jobs where id=p_id);end if;end$$;
create function public.push_receipts() returns jsonb language sql stable security invoker set search_path='' as $$select pulso_private.push_receipts()$$;
create function public.finish_push_receipt(p_id uuid,p_error text) returns void language sql security invoker set search_path='' as $$select pulso_private.finish_push_receipt(p_id,p_error)$$;
revoke all on function public.push_receipts(),pulso_private.push_receipts(),public.finish_push_receipt(uuid,text),pulso_private.finish_push_receipt(uuid,text) from public,anon,authenticated;
grant execute on function public.push_receipts(),pulso_private.push_receipts(),public.finish_push_receipt(uuid,text),pulso_private.finish_push_receipt(uuid,text) to service_role;

create index booking_notice_user_created on public.booking_notifications(user_id,created_at desc);
create index push_job_pending on pulso_private.push_jobs(available_at) where state in ('pending','retry','sending');
create index payment_refunds on public.payments(created_at) where state in ('refund_pending','refund_failed');
create function pulso_private.account_status() returns text language sql stable security definer set search_path='' as $$select case when exists(select 1 from pulso_private.account_suspensions where user_id=auth.uid()) then 'suspended' when exists(select 1 from public.profiles where id=auth.uid() and deleted_at is not null) then 'deleted' else 'active' end$$;
create function public.account_status() returns text language sql stable security invoker set search_path='' as $$select pulso_private.account_status()$$;
revoke all on function public.account_status(),pulso_private.account_status() from public,anon;grant execute on function public.account_status(),pulso_private.account_status() to authenticated;
alter table public.payments add column provider_live boolean not null default false;
-- Moderated files are removed via Storage API by the worker, never by SQL metadata deletion.
create table pulso_private.file_cleanup(id uuid primary key default gen_random_uuid(),bucket text not null,path text not null,unique(bucket,path));
alter table pulso_private.file_cleanup enable row level security;
create function pulso_private.queue_file_cleanup() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_table_name='photos' then insert into pulso_private.file_cleanup(bucket,path) values('portfolio',old.storage_path) on conflict do nothing;
 elsif old.photo_path is not null then insert into pulso_private.file_cleanup(bucket,path) values('appointment-media',old.photo_path) on conflict do nothing;end if;return old;end$$;
create trigger photo_cleanup after delete on public.photos for each row execute function pulso_private.queue_file_cleanup();
create trigger review_cleanup after delete on public.reviews for each row execute function pulso_private.queue_file_cleanup();
create function pulso_private.cleanup_files() returns jsonb language sql stable security definer set search_path='' as $$select coalesce(jsonb_agg(x),'[]'::jsonb) from(select * from pulso_private.file_cleanup limit 50)x$$;
create function pulso_private.cleaned_file(p_id uuid) returns void language sql security definer set search_path='' as $$delete from pulso_private.file_cleanup where id=p_id$$;
create function public.cleanup_files() returns jsonb language sql stable security invoker set search_path='' as $$select pulso_private.cleanup_files()$$;
create function public.cleaned_file(p_id uuid) returns void language sql security invoker set search_path='' as $$select pulso_private.cleaned_file(p_id)$$;
revoke all on function pulso_private.queue_file_cleanup(),public.cleanup_files(),pulso_private.cleanup_files(),public.cleaned_file(uuid),pulso_private.cleaned_file(uuid) from public,anon,authenticated;
grant execute on function public.cleanup_files(),pulso_private.cleanup_files(),public.cleaned_file(uuid),pulso_private.cleaned_file(uuid) to service_role;
notify pgrst,'reload schema';
-- A material identity/location edit requires a new review.
create function pulso_private.reset_shop_verification() returns trigger language plpgsql security definer set search_path='' as $$begin
 if row(new.name,new.address,new.lat,new.lng,new.owner_id) is distinct from row(old.name,old.address,old.lat,old.lng,old.owner_id) then update public.shop_trust set verified_at=null where shop_id=new.id;end if;return new;end$$;
create trigger reset_shop_verification after update of name,address,lat,lng,owner_id on public.shops for each row execute function pulso_private.reset_shop_verification();
revoke all on function pulso_private.reset_shop_verification() from public,anon,authenticated;
