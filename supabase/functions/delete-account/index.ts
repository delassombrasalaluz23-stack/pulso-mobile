import {createClient} from 'npm:@supabase/supabase-js@2.117.2';
const headers={'Content-Type':'application/json'};
Deno.serve(async(req:Request)=>{
 const reply=(status:number,error:string)=>new Response(JSON.stringify({error}),{status,headers});
 if(req.method!=='POST')return reply(405,'Método no permitido');
 try{
  const authorization=req.headers.get('Authorization');if(!authorization)return reply(401,'Inicia sesión');
  const url=Deno.env.get('SUPABASE_URL')!;const key=Deno.env.get('SUPABASE_ANON_KEY')!;
  const client=createClient(url,key,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error}=await client.auth.getUser();if(error||!user?.email)return reply(401,'Inicia sesión otra vez');
  const body=await req.json();if(body.confirmation!=='ELIMINAR'||typeof body.password!=='string'||body.password.length>1024)return reply(400,'Confirma la eliminación y tu contraseña');
  // Validate the password server-side for this exact user, not a timestamp from another device.
  const verifier=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  const check=await verifier.auth.signInWithPassword({email:user.email,password:body.password});
  if(check.error||check.data.user?.id!==user.id)return reply(403,'La contraseña no es correcta');
  const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const closed=await admin.rpc('admin_close_account',{p_user:user.id});if(closed.error)throw closed.error;
  // Includes result photos uploaded by the barber for this customer.
  while(true){
   const rows=await admin.from('haircut_records').select('appointment_id,photo_path').or(`customer_id.eq.${user.id},owner_id.eq.${user.id}`).limit(100);if(rows.error)throw rows.error;if(!rows.data?.length)break;
   const paths=rows.data.map(r=>r.photo_path).filter((p):p is string=>!!p);
   if(paths.length){const cleanup=await admin.storage.from('haircut-records').remove(paths);if(cleanup.error)throw cleanup.error}
   const cleanup=await admin.from('haircut_records').delete().in('appointment_id',rows.data.map(r=>r.appointment_id));if(cleanup.error)throw cleanup.error;
  }
  // Remove bytes through Storage API. Deleting storage metadata in SQL would leave orphaned files.
  for(const bucket of ['portfolio','appointment-media','haircut-records']){
   async function removeFolder(prefix:string,depth=0):Promise<void>{
    if(depth>5)throw Error('No se pudo completar la limpieza de fotos');
    const storage=admin.storage.from(bucket);
    while(true){const listing=await storage.list(prefix,{limit:100});if(listing.error)throw listing.error;if(!listing.data?.length)break;
     const files:string[]=[];for(const item of listing.data){const path=prefix+'/'+item.name;if(item.id)files.push(path);else await removeFolder(path,depth+1)}
     if(files.length){const removed=await storage.remove(files);if(removed.error)throw removed.error}
    }
   }
   await removeFolder(user.id);
  }
  const logout=await admin.auth.admin.signOut(check.data.session!.access_token,'global');if(logout.error)throw logout.error;
  const removed=await admin.auth.admin.deleteUser(user.id);if(removed.error)throw removed.error;
  return new Response(JSON.stringify({deleted:true}),{headers});
 }catch{return reply(400,'No se pudo finalizar la eliminación. Tu cuenta puede estar ya cerrada; vuelve a intentar aquí para completar la limpieza.')}
});
