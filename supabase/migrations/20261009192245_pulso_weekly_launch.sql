-- Owner-only weekly snapshot, using the business timezone and appointment date.
create function pulso_private.weekly_report(p_shop uuid,p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s public.shops;d date;result jsonb;begin
 if public.active_uid() is null or not public.owns_shop(p_shop) then raise exception 'Sin acceso a las estadísticas';end if;
 if p_offset not between -104 and 0 then raise exception 'Semana no válida';end if;
 select * into s from public.shops where id=p_shop;
 d:=date_trunc('week',now() at time zone s.timezone)::date+p_offset*7;
 if (select count(*) from public.appointments where shop_id=p_shop and starts_at>=d::timestamp at time zone s.timezone and starts_at<(d+7)::timestamp at time zone s.timezone)>20000 then raise exception 'La semana supera el límite del reporte. Contacta a soporte.';end if;
 select jsonb_build_object('shop',s.name,'timezone',s.timezone,'start',d,'end',d+6,'generated_at',now(),'rows',coalesce(jsonb_agg(jsonb_build_object(
 'id',a.id,'day',(a.starts_at at time zone s.timezone)::date,'starts_at',a.starts_at,'customer_id',a.customer_id,'customer_name',a.customer_name,'barber_id',a.barber_id,'barber_name',a.barber_name,'status',a.status,'total_cents',a.total_cents,'deposit_cents',a.deposit_cents,'discount_cents',a.discount_cents,'minutes',extract(epoch from a.ends_at-a.starts_at)/60,'lines',a.lines,'payment_mode',a.payment_mode,'payment_state',p.state,'provider_live',coalesce(p.provider_live,false),'paid_cents',coalesce(p.amount_cents,0),'returning',exists(select 1 from public.appointments old where old.shop_id=p_shop and old.customer_id=a.customer_id and old.status='completed' and old.starts_at<d::timestamp at time zone s.timezone)
 ) order by a.starts_at,a.id) filter(where a.id is not null),'[]'::jsonb)) into result from public.appointments a left join public.payments p on p.appointment_id=a.id where a.shop_id=p_shop and a.starts_at>=d::timestamp at time zone s.timezone and a.starts_at<(d+7)::timestamp at time zone s.timezone;
 return result;end$$;

alter table public.appointments add column late_minutes integer check(late_minutes between 5 and 30),add column late_notified_at timestamptz;
create function pulso_private.notify_late(p_id uuid,p_minutes integer) returns void language plpgsql security definer set search_path='' as $$declare a public.appointments;u uuid;begin
 select * into a from public.appointments where id=p_id for update;
 if public.active_uid() is null or a.customer_id is distinct from public.active_uid() then raise exception 'Sin acceso';end if;
 if p_minutes not in (5,10,15,20,30) or a.status<>'confirmed' or now()<a.starts_at-interval '1 hour' or now()>a.starts_at+interval '30 minutes' then raise exception 'Puedes avisar desde una hora antes y hasta 30 minutos después de la cita';end if;
 if a.late_notified_at>now()-interval '2 minutes' then raise exception 'Tu aviso ya fue enviado. Espera dos minutos para actualizarlo.';end if;
 update public.appointments set late_minutes=p_minutes,late_notified_at=now() where id=p_id;
 select owner_id into u from public.shops where id=a.shop_id;
 insert into public.booking_notifications(user_id,appointment_id,title,body,dedupe) values(u,a.id,'Aviso de retraso',a.customer_name||' prevé llegar '||p_minutes||' minutos tarde. El horario y las condiciones de la reserva se conservan.',gen_random_uuid()::text);
end$$;

create table public.reschedule_requests(id uuid primary key default gen_random_uuid(),appointment_id uuid not null references public.appointments,requester uuid not null references public.profiles,recipient uuid not null references public.profiles,original_start timestamptz not null,proposed_start timestamptz not null,status text not null default 'pending' check(status in ('pending','accepted','declined','cancelled','expired')),created_at timestamptz not null default now(),expires_at timestamptz not null);
alter table public.reschedule_requests enable row level security;
grant select on public.reschedule_requests to authenticated;
create policy reschedule_read on public.reschedule_requests for select to authenticated using(public.active_uid() in (requester,recipient));
create unique index reschedule_one_pending on public.reschedule_requests(appointment_id) where status='pending';
create index reschedule_recipient on public.reschedule_requests(recipient,status);
-- Keep the existing validated move implementation private. Old app clients must update.
alter function pulso_private.reschedule_appointment(uuid,timestamptz,timestamptz) rename to apply_accepted_reschedule;
revoke all on function pulso_private.apply_accepted_reschedule(uuid,timestamptz,timestamptz) from public,anon,authenticated;
create function pulso_private.reschedule_appointment(p_id uuid,p_start timestamptz,p_expected_start timestamptz) returns void language plpgsql security definer set search_path='' as $$begin raise exception 'Actualiza Pulso para proponer un cambio que la otra persona pueda aceptar';end$$;
revoke all on function pulso_private.reschedule_appointment(uuid,timestamptz,timestamptz) from public,anon;
grant execute on function pulso_private.reschedule_appointment(uuid,timestamptz,timestamptz) to authenticated;
create function pulso_private.propose_reschedule(p_id uuid,p_start timestamptz,p_expected_start timestamptz) returns void language plpgsql security definer set search_path='' as $$declare a public.appointments;s public.shops;u uuid:=public.active_uid();target uuid;deadline timestamptz;begin
 select * into a from public.appointments where id=p_id for update;
 if u is null or a.id is null or (a.customer_id<>u and not public.owns_shop(a.shop_id)) then raise exception 'Sin acceso';end if;
 if a.status<>'confirmed' or a.starts_at is distinct from p_expected_start or p_start=a.starts_at then raise exception 'La cita cambió. Actualiza tu agenda.';end if;
 deadline:=least(now()+interval '24 hours',a.starts_at-make_interval(hours=>a.cancel_hours),p_start);
 if deadline<=now() then raise exception 'El plazo de cambio terminó. Contacta a la otra persona.';end if;
 select * into s from public.shops where id=a.shop_id;
 if not exists(select 1 from pulso_private.reschedule_slots(p_id,(p_start at time zone s.timezone)::date) t where t.starts_at=p_start) then raise exception 'Horario no disponible';end if;
 update public.reschedule_requests set status='expired' where appointment_id=p_id and status='pending' and expires_at<=now();
 if exists(select 1 from public.reschedule_requests where appointment_id=p_id and status='pending') then raise exception 'Ya hay una propuesta pendiente. Responde o retírala primero.';end if;
 target:=case when a.customer_id=u then s.owner_id else a.customer_id end;
 insert into public.reschedule_requests(appointment_id,requester,recipient,original_start,proposed_start,expires_at) values(p_id,u,target,a.starts_at,p_start,deadline);
 insert into public.booking_notifications(user_id,appointment_id,title,body,dedupe) values(target,p_id,'Propuesta de cambio de cita','Revisa la propuesta en tu agenda. El horario original sigue vigente hasta que aceptes.',gen_random_uuid()::text);
end$$;
create function pulso_private.respond_reschedule(p_request uuid,p_action text) returns void language plpgsql security definer set search_path='' as $$declare r public.reschedule_requests;a public.appointments;u uuid:=public.active_uid();aid uuid;begin
 select appointment_id into aid from public.reschedule_requests where id=p_request;
 select * into a from public.appointments where id=aid for update;
 select * into r from public.reschedule_requests where id=p_request for update;
 if u is null or r.id is null or u not in(r.requester,r.recipient) then raise exception 'Sin acceso';end if;
 if r.status<>'pending' then raise exception 'La propuesta ya fue respondida';end if;
 if p_action='cancelled' and u=r.requester then update public.reschedule_requests set status='cancelled' where id=r.id;
 elsif p_action in ('accepted','declined') and u=r.recipient then
 if r.expires_at<=now() or a.status<>'confirmed' or a.starts_at<>r.original_start then raise exception 'La propuesta venció o la cita cambió';end if;
 if p_action='accepted' then perform pulso_private.apply_accepted_reschedule(a.id,r.proposed_start,r.original_start);update public.appointments set late_minutes=null,late_notified_at=null where id=a.id;end if;
 update public.reschedule_requests set status=p_action where id=r.id;
 else raise exception 'Acción no permitida';end if;
 insert into public.booking_notifications(user_id,appointment_id,title,body,dedupe) values(case when u=r.requester then r.recipient else r.requester end,a.id,'Respuesta al cambio de cita',case when p_action='accepted' then 'Cambio aceptado. Consulta el nuevo horario.' else 'Se mantiene el horario original. Consulta tu agenda.' end,gen_random_uuid()::text);
end$$;

create table pulso_private.booking_requests(request_id uuid primary key,user_id uuid not null,arguments jsonb not null,appointment_id uuid not null references public.appointments);
alter table pulso_private.booking_requests enable row level security;
create function pulso_private.book_once(p_request uuid,p_args jsonb) returns uuid language plpgsql security definer set search_path='' as $$declare old pulso_private.booking_requests;b uuid;addons uuid[];begin
 if public.active_uid() is null or p_request is null then raise exception 'Inicia sesión';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request::text,0));
 select * into old from pulso_private.booking_requests where request_id=p_request;
 if found then if old.user_id<>public.active_uid() or old.arguments<>p_args then raise exception 'La solicitud no coincide';end if;return old.appointment_id;end if;
 select coalesce(array_agg(v::uuid),'{}') into addons from jsonb_array_elements_text(p_args->'p_addons')v;
 if p_args->>'p_reward' is not null and p_args->>'p_offer' is not null then raise exception 'No se combinan descuentos';end if;
 if p_args->>'p_reward' is not null then b:=pulso_private.book_with_reward((p_args->>'p_barber')::uuid,(p_args->>'p_service')::uuid,addons,(p_args->>'p_start')::timestamptz,(p_args->>'p_expected_total')::int,(p_args->>'p_expected_deposit')::int,(p_args->>'p_expected_cancel')::int,(p_args->>'p_accept')::boolean,(p_args->>'p_reward')::uuid,(p_args->>'p_expected_discount')::int);
 elsif p_args->>'p_offer' is not null then b:=pulso_private.book_with_offer((p_args->>'p_barber')::uuid,(p_args->>'p_service')::uuid,addons,(p_args->>'p_start')::timestamptz,(p_args->>'p_expected_total')::int,(p_args->>'p_expected_deposit')::int,(p_args->>'p_expected_cancel')::int,(p_args->>'p_accept')::boolean,(p_args->>'p_offer')::uuid,(p_args->>'p_expected_discount')::int);
 else b:=pulso_private.book_appointment((p_args->>'p_barber')::uuid,(p_args->>'p_service')::uuid,addons,(p_args->>'p_start')::timestamptz,(p_args->>'p_expected_total')::int,(p_args->>'p_expected_deposit')::int,(p_args->>'p_expected_cancel')::int,(p_args->>'p_accept')::boolean);end if;
 insert into pulso_private.booking_requests values(p_request,public.active_uid(),p_args,b);return b;end$$;


create function pulso_private.find_booking_attempt(p_request uuid) returns uuid language plpgsql stable security definer set search_path='' as $$declare found_id uuid;begin
 if public.active_uid() is null then raise exception 'Inicia sesión';end if;
 select appointment_id into found_id from pulso_private.booking_requests where request_id=p_request and user_id=public.active_uid();
 if found_id is null then select appointment_id into found_id from public.payments where request_id=p_request and customer_id=public.active_uid();end if;return found_id;
end$$;

create function pulso_private.admin_operations() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not pulso_private.is_admin() then raise exception 'Solo administración';end if;
 return jsonb_build_object('refund_failed',(select count(*) from public.payments where state='refund_failed'),'refund_pending',(select count(*) from public.payments where state='refund_pending'),'push_failed',(select count(*) from pulso_private.push_jobs where state='failed' or (state in ('retry','sending') and attempts>=5)),'push_delayed',(select count(*) from pulso_private.push_jobs where state in ('pending','retry','sending') and available_at<now()-interval '15 minutes'),'expired_payments',(select count(*) from public.appointments where status='pending_payment' and payment_expires_at<now()),'ready_shops',(select count(*) from pulso_private.payment_accounts where charges_enabled and payouts_enabled),'push_devices',(select count(*) from public.push_tokens),'pending_changes',(select count(*) from public.reschedule_requests r join public.appointments a on a.id=r.appointment_id where r.status='pending' and r.expires_at>now() and a.status='confirmed' and a.starts_at=r.original_start));end$$;
create function pulso_private.test_push() returns void language plpgsql security definer set search_path='' as $$begin
 if public.active_uid() is null then raise exception 'Inicia sesión';end if;
 if not exists(select 1 from public.push_tokens where user_id=public.active_uid()) then raise exception 'Activa primero las notificaciones';end if;
 insert into public.booking_notifications(user_id,title,body,dedupe) values(public.active_uid(),'Prueba de avisos Pulso','Si ves este aviso con la app cerrada, los avisos llegan a este dispositivo.',public.active_uid()::text||':test:'||date_trunc('minute',now())::text) on conflict do nothing;end$$;

do $$declare f record;args text;begin
 for f in select p.proname,pg_get_function_identity_arguments(p.oid) ident,pg_get_function_arguments(p.oid) fullargs,pg_get_function_result(p.oid) result,p.proargnames,p.provolatile from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='pulso_private' and p.proname=any(array['find_booking_attempt','weekly_report','notify_late','propose_reschedule','respond_reschedule','book_once','admin_operations','test_push']) loop
 select string_agg(quote_ident(x),',') into args from unnest(f.proargnames)x;
 execute format('create function public.%I(%s) returns %s language sql %s security invoker set search_path='''' as %L',f.proname,f.fullargs,f.result,case when f.provolatile='s' then 'stable' else 'volatile' end,'select pulso_private.'||f.proname||'('||coalesce(args,'')||')');
 execute format('revoke all on function public.%I(%s),pulso_private.%I(%s) from public,anon',f.proname,f.ident,f.proname,f.ident);
 execute format('grant execute on function public.%I(%s),pulso_private.%I(%s) to authenticated',f.proname,f.ident,f.proname,f.ident);
 end loop;end$$;
notify pgrst,'reload schema';
