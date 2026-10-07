import {PGlite} from '@electric-sql/pglite';
import fs from 'node:fs';
import assert from 'node:assert/strict';
import ts from 'typescript';
import {createHmac} from 'node:crypto';
const pg=new PGlite();
await pg.exec(`create role service_role bypassrls;create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,created_at timestamptz default now());create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;`);
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

await assert.rejects(as(client,()=>pg.query('select public.admin_dashboard()')),/administración/);
await assert.rejects(as(owner,()=>pg.query('select public.admin_dashboard()')),/administración/);
await assert.rejects(as(null,()=>pg.query('select public.admin_dashboard()'),'anon'));
await assert.rejects(as(admin,()=>pg.query('select public.admin_dashboard(999)')),/Filtro/);
for(let i=0;i<27;i++)await pg.query(`insert into public.appointments(id,customer_id,shop_id,barber_id,customer_name,shop_name,barber_name,starts_at,ends_at,lines,total_cents,deposit_cents,cancel_hours) values($1,$2,$3,$4,'Cliente','Pulso Test','Barbero',now()+make_interval(days=>$5),now()+make_interval(days=>$5)+interval '30 minutes','[]',30000,9000,12)`,[uid(100+i),client,shop,barber,i+1]);
const dashboard=async(page=0,search='',customer=null)=>(await as(admin,()=>pg.query("select public.admin_dashboard(30,$1,$2,'',$3) d",[page,search,customer]))).rows[0].d;
let d=await dashboard();assert.equal(d.appointment_count,27);assert.equal(d.appointments.length,25);assert.equal(d.summary.simulation,27*9000);assert.equal(d.summary.live_collected,0);assert.equal(d.accounts.length,4);assert.ok(d.accounts[0].registered_at);assert.equal((await dashboard(1)).appointments.length,2);assert.equal((await dashboard(1)).summary.appointments,27);assert.equal((await dashboard(0,'inexistente')).appointment_count,0);assert.equal((await dashboard(0,'',stranger)).appointment_count,0);
// A Stripe test payment must never enter real collections.
await pg.query("insert into public.payments(appointment_id,request_id,customer_id,shop_id,amount_cents,state,provider_live) values($1,$2,$3,$4,9000,'paid',false)",[uid(100),uid(500),client,shop]);
assert.equal((await dashboard()).summary.live_collected,0);assert.equal((await dashboard()).summary.test_payments,1);
await pg.query("update public.payments set provider_live=true where appointment_id=$1",[uid(100)]);assert.equal((await dashboard()).summary.live_collected,9000);
await pg.query("update public.payments set state='refunded' where appointment_id=$1",[uid(100)]);d=await dashboard();assert.equal(d.summary.live_refunded,9000);assert.equal(d.summary.live_collected,9000);
await pg.query("update public.appointments set created_at=now()-interval '31 days' where id=$1",[uid(100)]);assert.equal((await dashboard()).appointment_count,26);
await pg.close();console.log('PASS admin dashboard: authorization, totals, pagination, search, customer isolation, date window, real/test payments and refunds.');
