alter table pulso_private.payment_accounts add column bank_connected boolean not null default false;
create or replace function pulso_private.payment_ready(p_shop uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from pulso_private.payment_accounts where shop_id=p_shop and charges_enabled and payouts_enabled and bank_connected)$$;
create function pulso_private.set_payment_bank(p_shop uuid,p_connected boolean) returns void language sql security definer set search_path='' as $$update pulso_private.payment_accounts set bank_connected=p_connected where shop_id=p_shop$$;
create function public.set_payment_bank(p_shop uuid,p_connected boolean) returns void language sql security invoker set search_path='' as $$select pulso_private.set_payment_bank(p_shop,p_connected)$$;
revoke all on function pulso_private.set_payment_bank(uuid,boolean),public.set_payment_bank(uuid,boolean) from public,anon,authenticated;
grant execute on function pulso_private.set_payment_bank(uuid,boolean),public.set_payment_bank(uuid,boolean) to service_role;
-- Preserve the existing RPC signature while avoiding positional inserts after adding a column.
create or replace function pulso_private.save_payment_account(p_shop uuid,p_account text,p_charges boolean,p_payouts boolean) returns void language sql security definer set search_path='' as $$insert into pulso_private.payment_accounts(shop_id,stripe_account,charges_enabled,payouts_enabled) values(p_shop,p_account,p_charges,p_payouts) on conflict(shop_id) do update set stripe_account=excluded.stripe_account,charges_enabled=excluded.charges_enabled,payouts_enabled=excluded.payouts_enabled,bank_connected=case when payment_accounts.stripe_account=excluded.stripe_account then payment_accounts.bank_connected else false end$$;
create or replace function pulso_private.prepare_checkout(p_request uuid,p_barber uuid,p_service uuid,p_addons uuid[],p_start timestamptz,p_expected_total integer,p_expected_deposit integer,p_expected_cancel integer,p_accept boolean,p_offer uuid default null,p_reward uuid default null,p_expected_discount integer default 0) returns uuid language plpgsql security definer set search_path='' as $$declare sh uuid;booking uuid;existing public.payments;begin
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
 if (select amount_cents<=0 from public.payments where appointment_id=booking) then raise exception 'El anticipo debe ser mayor a $0. Ajusta la promoción o recompensa.';end if;
 return booking;
end$$;
create or replace function pulso_private.guard_shop_booking() returns trigger language plpgsql security definer set search_path='' as $$begin
 if not pulso_private.shop_visible(new.shop_id) then raise exception 'Barbería no disponible';end if;
 if not pulso_private.payment_ready(new.shop_id) then raise exception 'La barbería debe conectar y habilitar su cuenta bancaria antes de recibir reservas';end if;
 if current_setting('pulso.checkout',true) is distinct from 'true' then raise exception 'Confirma esta reserva mediante el pago del anticipo';end if;
 if new.deposit_cents<=0 then raise exception 'El anticipo debe ser mayor a $0';end if;
 new.status:='pending_payment';new.payment_mode:='stripe';new.outcome:='awaiting_payment';new.payment_expires_at:=now()+interval '35 minutes';return new;end$$;
-- Confirmation is allowed only after a verified live payment, including calls from older apps.
create function pulso_private.require_paid_confirmation() returns trigger language plpgsql security definer set search_path='' as $$begin
 if old.status='pending_payment' and new.status in ('confirmed','arrived','completed') and not exists(select 1 from public.payments p where p.appointment_id=new.id and p.state='paid' and p.provider_live and p.amount_cents>0 and p.amount_cents=new.deposit_cents) then raise exception 'Primero completa el pago real del anticipo';end if;return new;end$$;
revoke all on function pulso_private.require_paid_confirmation() from public,anon,authenticated;
create trigger require_paid_confirmation before update of status on public.appointments for each row execute function pulso_private.require_paid_confirmation();
