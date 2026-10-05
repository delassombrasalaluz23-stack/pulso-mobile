import {adminClient,authenticated,checked,paymentConfigured,response,stripe} from '../_shared/runtime.ts';
Deno.serve(async(req:Request)=>{if(req.method!=='POST')return response({error:'Método inválido'},405);try{
 const {client,user}=await authenticated(req);paymentConfigured();const x=await req.json();const admin=adminClient();let id:string;
 if(x.appointment_id){const row=await checked(client.from('payments').select('appointment_id,customer_id').eq('appointment_id',x.appointment_id).single());if(!row||row.customer_id!==user.id)throw Error('Sin acceso');id=row.appointment_id}
 else id=await checked(client.rpc('prepare_checkout',x));
 const p=await checked(admin.from('payments').select('*').eq('appointment_id',id).single());const a=await checked(admin.from('appointments').select('status,payment_mode,payment_expires_at').eq('id',id).single());
 if(!a||!p)throw Error('Reserva no encontrada');
 if(a.payment_mode==='no_charge')return response({confirmed:true,appointment_id:id});
 if(a.status!=='pending_payment'||Date.parse(a.payment_expires_at)<=Date.now())throw Error('Este pago ya no está pendiente. Revisa Mis citas.');
 if(p.checkout_url)return response({url:p.checkout_url,appointment_id:id});
 const account=await checked(admin.rpc('payment_account',{p_shop:p.shop_id}));if(!account?.charges_enabled||!account?.payouts_enabled)throw Error('Cobros no habilitados en esta barbería');
 const live=await stripe('accounts/'+encodeURIComponent(account.stripe_account));if(!live.charges_enabled||!live.payouts_enabled)throw Error('El proveedor todavía no habilitó los cobros de la barbería');
 const back=Deno.env.get('SUPABASE_URL')+'/functions/v1/payment-return';
 const session=await stripe('checkout/sessions',{mode:'payment',locale:'es',success_url:back,cancel_url:back,client_reference_id:id,'metadata[appointment_id]':id,'payment_intent_data[metadata][appointment_id]':id,'payment_method_types[0]':'card','payment_intent_data[transfer_data][destination]':account.stripe_account,'line_items[0][price_data][currency]':'mxn','line_items[0][price_data][unit_amount]':String(p.amount_cents),'line_items[0][price_data][product_data][name]':'Anticipo de reserva Pulso','line_items[0][quantity]':'1',expires_at:String(Math.floor(Date.parse(p.created_at)/1000)+34*60)},'checkout-'+p.request_id);
 await checked(admin.from('payments').update({checkout_id:session.id,checkout_url:session.url,provider_live:!!session.livemode}).eq('appointment_id',id));return response({url:session.url,appointment_id:id});
}catch(e){return response({error:(e as Error).message??'No se pudo iniciar el pago'},400)}});
