import {PGlite} from '@electric-sql/pglite';
import fs from 'node:fs';
import assert from 'node:assert/strict';
import ts from 'typescript';
import {createHmac} from 'node:crypto';
const pg=new PGlite();
await pg.exec(`create role service_role bypassrls;create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;`);
for(const f of fs.readdirSync('supabase/migrations').filter(x=>x.endsWith('.sql')).sort())await pg.exec(fs.readFileSync('supabase/migrations/'+f,'utf8'));
const uid=n=>`10000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const owner=uid(1),client=uid(2),stranger=uid(3),admin=uid(4),shop=uid(5),barber=uid(6),cut=uid(7);
async function as(user,fn,role='authenticated'){await pg.query("select set_config('request.jwt.claim.sub',$1,false)",[user??'']);await pg.exec('set role '+role);try{return await fn()}finally{await pg.exec('reset role')}}
for(const [id,role] of [[owner,'owner'],[client,'client'],[stranger,'client'],[admin,'client']]){await pg.query('insert into auth.users values($1)',[id]);await as(id,()=>pg.query('insert into public.profiles(id,name,role) values($1,$2,$3)',[id,'User '+id,role]))}
await as(owner,()=>pg.query("insert into public.shops(id,owner_id,name,address,municipality,lat,lng,days,open_hour,close_hour) values($1,$2,'Pulso Test','Calle prueba','Monterrey',25.6,-100.3,'{0,1,2,3,4,5,6}',8,22)",[shop,owner]));
await as(owner,()=>pg.query("insert into public.barbers(id,shop_id,name) values($1,$2,'Barbero')",[barber,shop]));await as(owner,()=>pg.query("insert into public.services(id,shop_id,name,kind,price_cents,duration_minutes) values($1,$2,'Corte','cut',30000,30)",[cut,shop]));
const catalog=(await as(null,()=>pg.query('select public.public_catalog() as c'),'anon')).rows[0].c;assert.equal(catalog.shops.length,1);assert.equal(catalog.shops[0].owner_id,undefined);assert.equal(catalog.shops[0].verified,false);assert.equal(catalog.appointments,undefined);
await assert.rejects(as(null,()=>pg.query('select * from public.appointments'),'anon'));
await assert.rejects(as(client,()=>pg.query('select public.admin_overview()')),/administración/);
await assert.rejects(as(owner,()=>pg.query('insert into pulso_private.admin_members values($1,now())',[owner])));
await pg.query('insert into pulso_private.admin_members(user_id) values($1)',[admin]);
await assert.rejects(as(owner,()=>pg.query("select public.admin_action('verify',$1,'I verified myself')",[shop])));
await as(admin,()=>pg.query("select public.admin_action('verify',$1,'Identidad y local revisados')",[shop]));assert.equal((await as(null,()=>pg.query('select public.public_catalog() as c'),'anon')).rows[0].c.shops[0].verified,true);
const day=new Date(Date.now()+3*86400000).toISOString().slice(0,10);async function next(){return (await as(client,()=>pg.query('select * from public.available_slots($1,$2,$3,array[]::uuid[])',[barber,day,cut]))).rows[0].starts_at}
async function book(){const start=await next();return (await as(client,()=>pg.query('select public.book_appointment($1,$2,array[]::uuid[],$3,30000,30,12,true) id',[barber,cut,start]))).rows[0].id}
const a=await book();const code=(await as(client,()=>pg.query('select public.arrival_code($1) code',[a]))).rows[0].code;assert.match(code,/^\d{6}$/);
await assert.rejects(as(owner,()=>pg.query('select public.arrival_code($1)',[a])));
await assert.rejects(as(owner,()=>pg.query('select * from pulso_private.arrival_codes')));
await pg.query("update public.appointments set starts_at=now()-interval '1 minute',ends_at=now()+interval '29 minutes' where id=$1",[a]);
await assert.rejects(as(owner,()=>pg.query("select public.transition_appointment($1,'complete')",[a])),/código/);
await assert.rejects(as(owner,()=>pg.query("select public.transition_appointment($1,'arrived')",[a])),/código/);
for(let i=0;i<5;i++)assert.equal((await as(owner,()=>pg.query('select public.confirm_arrival($1,$2) ok',[a,code==='000000'?'111111':'000000']))).rows[0].ok,false);
await assert.rejects(as(owner,()=>pg.query('select public.confirm_arrival($1,$2)',[a,code])),/15 minutos/);
await pg.query("update pulso_private.arrival_codes set locked_until=now()-interval '1 second' where appointment_id=$1",[a]);
assert.equal((await as(owner,()=>pg.query('select public.confirm_arrival($1,$2) ok',[a,code]))).rows[0].ok,true);await as(owner,()=>pg.query("select public.transition_appointment($1,'complete')",[a]));
const ticket=(await as(client,()=>pg.query("select public.create_support('appointment',$1,'Ayuda con cita','Necesito revisar esta visita') id",[a]))).rows[0].id;
await assert.rejects(as(stranger,()=>pg.query("select public.create_support('appointment',$1,'Ajena','No puedo ver esta cita')",[a])));
assert.equal((await as(stranger,()=>pg.query('select * from public.support_tickets'))).rows.length,0);
assert.equal((await as(admin,()=>pg.query('select public.admin_overview() d'))).rows[0].d.tickets[0].context.shop,'Pulso Test');
await as(admin,()=>pg.query("select public.admin_action('reply',$1,'Estamos revisando tu solicitud')",[ticket]));assert.match((await as(client,()=>pg.query('select reply from public.support_tickets'))).rows[0].reply,/revisando/);
await as(admin,()=>pg.query("select public.admin_action('suspend_shop',$1,'Suspensión por revisión del negocio')",[shop]));assert.equal((await as(null,()=>pg.query('select public.public_catalog() c'),'anon')).rows[0].c.shops.length,0);await assert.rejects(book());
await as(admin,()=>pg.query("select public.admin_action('restore_shop',$1,'Se completó la revisión del negocio')",[shop]));
await as(admin,()=>pg.query("select public.admin_action('suspend_user',$1,'Cuenta requiere revisión de soporte')",[stranger]));assert.equal((await as(stranger,()=>pg.query('select public.active_uid() id'))).rows[0].id,null);await assert.rejects(as(stranger,()=>pg.query("select public.create_support('general',null,'Hola','Cuenta suspendida intenta escribir')")));
await assert.rejects(as(admin,()=>pg.query("select public.admin_action('suspend_user',$1,'No debería poder suspenderme')",[admin])));
// Payment ownership, held slots, reconciliation and idempotent refund eligibility.
await pg.query("insert into pulso_private.payment_accounts values($1,'acct_test',true,true)",[shop]);
const start=await next(),request=uid(20);const pay=(await as(client,()=>pg.query('select public.prepare_checkout($1,$2,$3,array[]::uuid[],$4,30000,30,12,true) id',[request,barber,cut,start]))).rows[0].id;
assert.equal((await pg.query('select status from public.appointments where id=$1',[pay])).rows[0].status,'pending_payment');
assert.notEqual(Date.parse(await next()),Date.parse(start));await assert.rejects(book(),/pago del anticipo/);
assert.equal((await as(client,()=>pg.query('select public.prepare_checkout($1,$2,$3,array[]::uuid[],$4,30000,30,12,true) id',[request,barber,cut,start]))).rows[0].id,pay);
await assert.rejects(as(stranger,()=>pg.query('select public.prepare_checkout($1,$2,$3,array[]::uuid[],$4,30000,30,12,true)',[request,barber,cut,start])));
await assert.rejects(as(client,()=>pg.query("update public.payments set state='paid' where appointment_id=$1",[pay])));
await pg.query("update public.payments set checkout_id='cs_test' where appointment_id=$1",[pay]);
await assert.rejects(as(client,()=>pg.query("select public.settle_payment('evt','cs_test','pi_test',9000,'mxn',null)")));
await assert.rejects(pg.query("select public.settle_payment('evt','cs_test','pi_test',1,'mxn',null)"));
for(let i=0;i<2;i++)await pg.query("select public.settle_payment('evt','cs_test','pi_test',9000,'mxn',null)");
assert.equal((await pg.query('select status from public.appointments where id=$1',[pay])).rows[0].status,'confirmed');await as(client,()=>pg.query("select public.transition_appointment($1,'cancel')",[pay]));assert.equal((await pg.query('select state from public.payments where appointment_id=$1',[pay])).rows[0].state,'refund_pending');
await as(client,()=>pg.query("insert into public.push_tokens(token,user_id) values('ExponentPushToken[test]',$1)",[client]));
const jobs=(await pg.query('select public.claim_push_jobs() j')).rows[0].j;assert.ok(jobs.length);assert.equal((await pg.query('select public.claim_push_jobs() j')).rows[0].j.length,0);await assert.rejects(as(client,()=>pg.query('select public.claim_push_jobs()')));
await as(owner,()=>pg.query("update public.shops set address='Dirección nueva' where id=$1",[shop]));assert.equal((await as(null,()=>pg.query('select public.public_catalog() c'),'anon')).rows[0].c.shops[0].verified,false);
const photo=uid(44);await pg.query("insert into public.photos(id,shop_id,kind,storage_path) values($1,$2,'shop','owner/shop/photo.jpg')",[photo,shop]);await as(admin,()=>pg.query("select public.admin_action('hide_photo',$1,'Contenido revisado y retirado')",[photo]));assert.equal((await pg.query('select public.cleanup_files() f')).rows[0].f.length,1);await assert.rejects(as(client,()=>pg.query('select public.cleanup_files()')));
// Every exposed table retains row-level protection.
assert.equal((await pg.query("select count(*)::integer n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity")).rows[0].n,0);
const reserved=uid(88);await pg.query("insert into auth.users(id,email) values($1,'delassombrasalaluz23@gmail.com')",[reserved]);await as(reserved,()=>pg.query("insert into public.profiles(id,name,role) values($1,'Titular','client')",[reserved]));assert.equal((await as(reserved,()=>pg.query('select public.is_admin() ok'))).rows[0].ok,false);await pg.query('update auth.users set email_confirmed_at=now() where id=$1',[reserved]);await as(reserved,()=>pg.query("update public.profiles set name='Titular confirmado' where id=$1",[reserved]));assert.equal((await as(reserved,()=>pg.query('select public.is_admin() ok'))).rows[0].ok,true);assert.equal((await pg.query('select count(*)::integer n from pulso_private.admin_reservations')).rows[0].n,0);await assert.rejects(as(client,()=>pg.query("insert into pulso_private.admin_reservations(email) values('otro@example.com')")));
await pg.close();
const source=fs.readFileSync('supabase/functions/_shared/stripe-signature.ts','utf8');const m={exports:{}};new Function('exports',ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText)(m.exports);const {verifyStripeSignature}=m.exports;const now=Date.now(),stamp=Math.floor(now/1000),raw='{"type":"checkout.session.completed"}',secret='webhook-test';const sig=createHmac('sha256',secret).update(stamp+'.'+raw).digest('hex');assert.equal(await verifyStripeSignature(raw,`t=${stamp},v1=${sig}`,secret,now),true);assert.equal(await verifyStripeSignature(raw+'x',`t=${stamp},v1=${sig}`,secret,now),false);assert.equal(await verifyStripeSignature(raw,`t=${stamp},v1=${sig}`,secret,now+301000),false);
console.log('PASS: guest privacy, admin authorization/audit, verified shops, suspensions, private arrival codes/lockout, support isolation, checkout holds, payment ownership/idempotency, refund eligibility, push leases and webhook tampering.');
