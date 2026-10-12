create function pulso_private.admin_statistics(p_days integer default 30) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare first_day date;last_day date;lo timestamptz;hi timestamptz;result jsonb;
begin
 if not pulso_private.is_admin() then raise exception 'Acceso solo para administración';end if;
 if p_days is null or p_days not in (7,30,90) then raise exception 'Periodo inválido';end if;
 last_day:=(now() at time zone 'America/Monterrey')::date;first_day:=last_day-(p_days-1);lo:=first_day::timestamp at time zone 'America/Monterrey';hi:=(last_day+1)::timestamp at time zone 'America/Monterrey';
 if (select count(*) from public.appointments where starts_at>=lo and starts_at<hi)>20000 or (select count(*) from public.shops)>5000 then raise exception 'El reporte supera el límite. Elige un periodo más corto o solicita una exportación ampliada.';end if;
 select jsonb_build_object('start',first_day,'end',last_day,'timezone','America/Monterrey','generated_at',now(),
 'accounts',(select count(*) from public.profiles where deleted_at is null),
 'new_accounts',(select count(*) from auth.users where created_at>=lo and created_at<hi),
 'pending_reports',(select count(*) from public.support_tickets where status<>'resolved'),
 'shops',(select coalesce(jsonb_agg(x order by x.name,x.id),'[]'::jsonb) from(select s.id,s.name,s.municipality,s.state,s.active,pulso_private.shop_visible(s.id) visible,exists(select 1 from public.shop_trust t where t.shop_id=s.id and t.verified_at is not null) verified,exists(select 1 from public.shop_trust t where t.shop_id=s.id and t.suspended) or exists(select 1 from pulso_private.account_suspensions a where a.user_id=s.owner_id) suspended,(select count(*) from public.barbers b where b.shop_id=s.id and b.active) barbers,(select count(*) from public.services v where v.shop_id=s.id and v.active and v.kind='cut') services from public.shops s)x),
 'rows',(select coalesce(jsonb_agg(x order by x.starts_at,x.id),'[]'::jsonb) from(select a.id,a.shop_id,a.shop_name,a.barber_name,a.starts_at,(a.starts_at at time zone 'America/Monterrey')::date as "day",a.status,a.total_cents,a.deposit_cents,a.discount_cents,a.payment_mode,a.outcome,p.state payment_state,coalesce(p.provider_live,false) provider_live,coalesce(p.amount_cents,0) paid_cents from public.appointments a left join public.payments p on p.appointment_id=a.id where a.starts_at>=lo and a.starts_at<hi)x)) into result;
 return result;
end$$;
revoke all on function pulso_private.admin_statistics(integer) from public,anon,authenticated;
grant execute on function pulso_private.admin_statistics(integer) to authenticated;
create function public.admin_statistics(p_days integer default 30) returns jsonb language sql stable security invoker set search_path='' as $$select pulso_private.admin_statistics(p_days)$$;
revoke all on function public.admin_statistics(integer) from public,anon,authenticated;
grant execute on function public.admin_statistics(integer) to authenticated;
