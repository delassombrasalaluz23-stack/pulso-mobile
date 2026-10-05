import {adminClient,checked,response,stripe} from '../_shared/runtime.ts';
import {verifyStripeSignature} from '../_shared/stripe-signature.ts';
Deno.serve(async(req:Request)=>{if(req.method!=='POST')return response({},405);const raw=await req.text();if(!await verifyStripeSignature(raw,req.headers.get('stripe-signature'),Deno.env.get('STRIPE_WEBHOOK_SECRET')??'')&&!await verifyStripeSignature(raw,req.headers.get('stripe-signature'),Deno.env.get('STRIPE_CONNECT_WEBHOOK_SECRET')??''))return response({error:'Firma no válida'},401);try{
 const event=JSON.parse(raw);const admin=adminClient();
 if(event.type==='account.updated'){const x=event.data.object;const shop=x.metadata?.pulso_shop;if(shop){const existing=await checked(admin.rpc('payment_account',{p_shop:shop}));if(existing?.stripe_account===x.id)await checked(admin.rpc('save_payment_account',{p_shop:shop,p_account:x.id,p_charges:!!x.charges_enabled,p_payouts:!!x.payouts_enabled}))}}
 if(event.type==='checkout.session.completed'||event.type==='checkout.session.async_payment_succeeded'){
  const session=await stripe('checkout/sessions/'+encodeURIComponent(event.data.object.id));
  if(session.payment_status==='paid'&&session.mode==='payment'){
   const intent=await stripe('payment_intents/'+encodeURIComponent(session.payment_intent)+'?expand[]=latest_charge');
   if(intent.status!=='succeeded'||intent.amount_received!==session.amount_total)throw Error('Pago todavía no conciliado');
   await checked(admin.rpc('settle_payment',{p_event:event.id,p_checkout:session.id,p_intent:intent.id,p_amount:session.amount_total,p_currency:session.currency,p_receipt:intent.latest_charge?.receipt_url??null}));
  }
 }
 return response({received:true});
}catch{return response({error:'No se pudo conciliar; reintentar'},500)}});
