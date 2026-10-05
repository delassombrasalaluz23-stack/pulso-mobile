-- Explicitly authorized administrator email. Membership requires verified ownership.
create table pulso_private.admin_reservations(email text primary key check(email=lower(btrim(email))),created_at timestamptz not null default now());
alter table pulso_private.admin_reservations enable row level security;
revoke all on pulso_private.admin_reservations from public,anon,authenticated;
insert into pulso_private.admin_reservations(email) values('delassombrasalaluz23@gmail.com');
create function pulso_private.claim_reserved_admin() returns trigger language plpgsql security definer set search_path='' as $$declare reserved text;begin
 select r.email into reserved from pulso_private.admin_reservations r join auth.users u on lower(u.email)=r.email where u.id=new.id and u.email_confirmed_at is not null and new.deleted_at is null for update of r;
 if reserved is not null then
 insert into pulso_private.admin_members(user_id) values(new.id) on conflict do nothing;
 insert into pulso_private.admin_audit(actor,action,target,note) values(new.id,'activate_reserved_admin',new.id,'Acceso reservado por el titular; correo confirmado por Supabase Auth');
 delete from pulso_private.admin_reservations where email=reserved;
 end if;return new;
end$$;
revoke all on function pulso_private.claim_reserved_admin() from public,anon,authenticated;
create trigger claim_reserved_admin after insert or update on public.profiles for each row execute function pulso_private.claim_reserved_admin();
notify pgrst,'reload schema';
