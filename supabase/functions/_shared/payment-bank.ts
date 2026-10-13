import {stripe} from './runtime.ts';
export async function hasPayoutBank(account:string):Promise<boolean>{
 const banks=await stripe('accounts/'+encodeURIComponent(account)+'/external_accounts?object=bank_account&limit=100');
 return banks.data?.some((b:{object:string;currency:string;default_for_currency:boolean;status:string})=>b.object==='bank_account'&&b.currency==='mxn'&&b.default_for_currency&&!['errored','verification_failed'].includes(b.status))??false;
}
export function livePayments():boolean{return (Deno.env.get('STRIPE_SECRET_KEY')??'').startsWith('sk_live_')&&!!Deno.env.get('STRIPE_WEBHOOK_SECRET')}
