import {adminClient,authenticated,checked,paymentConfigured,response,stripe} from '../_shared/runtime.ts';
Deno.serve(async(req:Request)=>{if(req.method!=='POST')return response({error:'Método inválido'},405);try{
 const {client,user}=await authenticated(req);paymentConfigured();const admin=adminClient();const shop=await checked(client.from('shops').select('id').eq('owner_id',user.id).single());
 if(!shop)throw Error('Primero registra tu barbería');
 let account=await checked(admin.rpc('payment_account',{p_shop:shop.id}));
 if(!account){const created=await stripe('accounts',{type:'express',country:'MX',email:user.email!,'capabilities[card_payments][requested]':'true','capabilities[transfers][requested]':'true','metadata[pulso_shop]':shop.id},'owner-'+shop.id);await checked(admin.rpc('save_payment_account',{p_shop:shop.id,p_account:created.id,p_charges:false,p_payouts:false}));account={stripe_account:created.id}}
 const live=await stripe('accounts/'+encodeURIComponent(account.stripe_account));await checked(admin.rpc('save_payment_account',{p_shop:shop.id,p_account:live.id,p_charges:!!live.charges_enabled,p_payouts:!!live.payouts_enabled}));
 const back=Deno.env.get('SUPABASE_URL')+'/functions/v1/payment-return';const link=await stripe('account_links',{account:live.id,refresh_url:back,return_url:back,type:'account_onboarding'});return response({url:link.url});
}catch(e){return response({error:(e as Error).message??'No se pudo conectar la cuenta'},400)}});
