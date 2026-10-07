-- Cross-account administration is deliberately isolated behind a server-side membership check.
create function pulso_private.admin_dashboard(p_days integer default 30,p_page integer default 0,p_search text default '',p_status text default '',p_customer uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare since timestamptz; until_at timestamptz:=now(); result jsonb;
begin
 if not pulso_private.is_admin() then raise exception 'Acceso solo para administración'; end if;
 if p_days is null or p_days not in (1,7,30) or p_page is null or p_page not between 0 and 10000 then raise exception 'Filtro inválido'; end if;
 if p_status is null or p_status not in ('','pending_payment','confirmed','arrived','completed','cancelled','no_show') then raise exception 'Estado inválido'; end if;
 since:=until_at-make_interval(days=>p_days);
 with filtered as (
 select a.id,a.customer_name,a.shop_name,a.barber_name,a.starts_at,a.created_at,a.status,a.total_cents,a.deposit_cents,a.payment_mode,a.outcome,
 p.state payment_state,p.provider_live
 from public.appointments a left join public.payments p on p.appointment_id=a.id
 where a.created_at>=since and a.created_at<=until_at
 and (p_customer is null or a.customer_id=p_customer)
 and (p_status='' or a.status=p_status)
 and (position(lower(left(coalesce(p_search,''),100)) in lower(a.customer_name||' '||a.shop_name))>0)
 ), accounts as (
 select u.id,coalesce(p.name,'Registro sin completar') name,p.role,u.created_at registered_at,u.email_confirmed_at is not null email_confirmed,
 (select count(*) from public.appointments a where a.customer_id=u.id) visits
 from auth.users u left join public.profiles p on p.id=u.id
 where (p.id is null or p.deleted_at is null) and position(lower(left(coalesce(p_search,''),100)) in lower(coalesce(p.name,'')))>0
 )
 select jsonb_build_object(
 'from',since,'to',until_at,
 'summary',jsonb_build_object(
 'accounts',(select count(*) from auth.users u where u.created_at between since and until_at),
 'owners',(select count(*) from public.profiles p join auth.users u on u.id=p.id where p.role='owner' and p.deleted_at is null and u.created_at between since and until_at),
 'shops',(select count(*) from public.shops),
 'pending_reports',(select count(*) from public.support_tickets where status<>'resolved'),
 'appointments',(select count(*) from public.appointments where created_at between since and until_at),
 'completed',(select count(*) from public.appointments where created_at between since and until_at and status='completed'),
 'cancelled',(select count(*) from public.appointments where created_at between since and until_at and status='cancelled'),
 'no_show',(select count(*) from public.appointments where created_at between since and until_at and status='no_show'),
 'live_collected',(select coalesce(sum(amount_cents),0) from public.payments where provider_live and currency='mxn' and state in ('paid','refund_pending','refund_failed','refunded') and created_at between since and until_at),
 'live_refunded',(select coalesce(sum(amount_cents),0) from public.payments where provider_live and currency='mxn' and state='refunded' and created_at between since and until_at),
 'live_refund_pending',(select coalesce(sum(amount_cents),0) from public.payments where provider_live and currency='mxn' and state in ('refund_pending','refund_failed') and created_at between since and until_at),
 'simulation',(select coalesce(sum(deposit_cents),0) from public.appointments where payment_mode='simulation' and created_at between since and until_at),
 'test_payments',(select count(*) from public.payments where not provider_live and created_at between since and until_at)),
 'appointment_count',(select count(*) from filtered),
 'appointments',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select * from filtered order by created_at desc,id limit 25 offset p_page*25)x),
 'account_count',(select count(*) from accounts),
 'accounts',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select * from accounts order by registered_at desc,id limit 25 offset p_page*25)x),
 'activity',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select a.id,a.action,a.created_at,a.note,coalesce(p.name,'Administración') actor from pulso_private.admin_audit a left join public.profiles p on p.id=a.actor where a.created_at between since and until_at order by a.created_at desc,a.id limit 50)x)
 ) into result;
 return result;
end$$;
revoke all on function pulso_private.admin_dashboard(integer,integer,text,text,uuid) from public,anon,authenticated;
grant execute on function pulso_private.admin_dashboard(integer,integer,text,text,uuid) to authenticated;
create function public.admin_dashboard(p_days integer default 30,p_page integer default 0,p_search text default '',p_status text default '',p_customer uuid default null) returns jsonb language sql stable security invoker set search_path='' as $$select pulso_private.admin_dashboard(p_days,p_page,p_search,p_status,p_customer)$$;
revoke all on function public.admin_dashboard(integer,integer,text,text,uuid) from public,anon,authenticated;
grant execute on function public.admin_dashboard(integer,integer,text,text,uuid) to authenticated;
create index if not exists appointments_admin_created on public.appointments(created_at desc,id);
create index if not exists payments_admin_created on public.payments(created_at);
