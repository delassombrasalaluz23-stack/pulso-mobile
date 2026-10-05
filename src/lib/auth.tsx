import {createContext,useCallback,useContext,useEffect,useRef,useState,type ReactNode} from 'react';
import {AppState} from 'react-native';
import type {Session} from '@supabase/supabase-js';
import {supabase,db} from './supabase';
type Profile={id:string;name:string;role:'client'|'owner'};
const Context=createContext<{session:Session|null;profile:Profile|null;ready:boolean;refresh:()=>Promise<void>;error:string}>({session:null,profile:null,ready:false,refresh:async()=>{},error:''});
export function AuthProvider({children}:{children:ReactNode}){
 const [session,setSession]=useState<Session|null>(null);const [profile,setProfile]=useState<Profile|null>(null);const [ready,setReady]=useState(!supabase);const [error,setError]=useState('');const generation=useRef(0);const currentUser=useRef<string|null>(null);
 const hydrate=useCallback(async(s:Session|null)=>{const n=++generation.current;setSession(s);if(currentUser.current!==(s?.user.id??null)){setReady(false);setProfile(null)}currentUser.current=s?.user.id??null;try{if(s&&supabase){const state=await supabase.rpc('account_status');if(state.data==='suspended')throw Error('Tu cuenta está suspendida. Contacta a soporte de Pulso.');const r=await supabase.from('profiles').select('*').eq('id',s.user.id).maybeSingle();if(r.error)throw r.error;if(n===generation.current)setProfile(r.data)}if(n===generation.current)setError('')}catch(e){if(n===generation.current)setError((e as Error).message)}finally{if(n===generation.current)setReady(true)}},[]);
 const refresh=useCallback(async()=>{if(!supabase)return;const r=await supabase.auth.getSession();if(r.error){setError(r.error.message);setReady(true);return}await hydrate(r.data.session)},[hydrate]);
 useEffect(()=>{if(!supabase)return;let mounted=true;const {data:{subscription}}=supabase.auth.onAuthStateChange((event,s)=>{if(event==='TOKEN_REFRESHED'){setSession(s);return}queueMicrotask(()=>{if(mounted)void hydrate(s)})});const listener=AppState.addEventListener('change',state=>{if(state==='active')supabase!.auth.startAutoRefresh();else supabase!.auth.stopAutoRefresh()});return()=>{mounted=false;generation.current++;subscription.unsubscribe();listener.remove()}},[hydrate]);
 return <Context.Provider value={{session,profile,ready,refresh,error}}>{children}</Context.Provider>
}
export const useAuth=()=>useContext(Context);
export async function saveProfile(id:string,name:string,role:string){const {error}=await db().from('profiles').upsert({id,name:name.trim(),role});if(error)throw error}
