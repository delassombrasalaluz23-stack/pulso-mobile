import {createClient} from 'npm:@supabase/supabase-js@2.117.2';
const headers={'Content-Type':'application/json'};
Deno.serve(async(req:Request)=>{
 if(req.method!=='POST')return new Response('{}',{status:405,headers});
 try{
 const authorization=req.headers.get('Authorization');if(!authorization)return new Response('{"error":"Inicia sesión"}',{status:401,headers});
 const url=Deno.env.get('SUPABASE_URL')!;const anon=Deno.env.get('SUPABASE_ANON_KEY')!;
 const client=createClient(url,anon,{global:{headers:{Authorization:authorization}},auth:{persistSession:false}});
 const {data:{user},error:authError}=await client.auth.getUser();if(authError||!user)return new Response('{"error":"Sesión no válida"}',{status:401,headers});
 const x=await req.json();if(typeof x.title!=='string'||typeof x.body!=='string'||x.title.length>80||x.body.length>500)throw Error('Mensaje no válido');
 // RPC authorizes the owner and filters completed visits + current opt-ins atomically.
 const {data:id,error}=await client.rpc('send_promotion',{p_id:x.request_id,p_shop:x.shop_id,p_title:x.title,p_body:x.body,p_customer:x.customer_id??null});if(error)throw error;
 const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
 const {data:inbox,error:inboxError}=await admin.from('inbox').select('id,customer_id').eq('promotion_id',id);if(inboxError)throw inboxError;let accepted=0;
 for(const row of inbox??[]){
  const {data:consent}=await admin.from('marketing_consents').select('enabled').eq('shop_id',x.shop_id).eq('customer_id',row.customer_id).maybeSingle();if(!consent?.enabled)continue;
  const {data:tokens}=await admin.from('push_tokens').select('token').eq('user_id',row.customer_id);
  for(const {token} of tokens??[]){
   await admin.from('push_deliveries').upsert({inbox_id:row.id,token},{onConflict:'inbox_id,token',ignoreDuplicates:true});
   const {data:claimed}=await admin.from('push_deliveries').update({state:'processing'}).eq('inbox_id',row.id).eq('token',token).eq('state','pending').select('inbox_id');if(!claimed?.length)continue;
   try{
    const response=await fetch('https://exp.host/--/api/v2/push/send',{method:'POST',headers:{'Content-Type':'application/json',...(Deno.env.get('EXPO_ACCESS_TOKEN')?{Authorization:'Bearer '+Deno.env.get('EXPO_ACCESS_TOKEN')}: {})},body:JSON.stringify({to:token,title:x.title,body:x.body,sound:'default',channelId:'promotions',data:{inbox_id:row.id,shop_id:x.shop_id}})});
    const result=await response.json();const ticket=Array.isArray(result.data)?result.data[0]:result.data;
    if(response.ok&&ticket?.status==='ok'){accepted++;await admin.from('push_deliveries').update({state:'accepted',ticket_id:ticket.id}).eq('inbox_id',row.id).eq('token',token)}else{await admin.from('push_deliveries').update({state:'failed',error:ticket?.details?.error??'Provider rejected'}).eq('inbox_id',row.id).eq('token',token);if(ticket?.details?.error==='DeviceNotRegistered')await admin.from('push_tokens').delete().eq('token',token)}
   }catch{await admin.from('push_deliveries').update({state:'unknown',error:'Network result unknown; do not automatically retry'}).eq('inbox_id',row.id).eq('token',token)}
  }
 }
 return new Response(JSON.stringify({id,recipients:inbox?.length??0,push_accepted:accepted}),{headers});
 }catch(e){return new Response(JSON.stringify({error:(e as Error).message}),{status:400,headers})}
});
