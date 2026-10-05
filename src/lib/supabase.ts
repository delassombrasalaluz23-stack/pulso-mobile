import 'react-native-url-polyfill/auto';
import {createClient} from '@supabase/supabase-js';
import * as SecureStore from 'expo-secure-store';
import * as Crypto from 'expo-crypto';
const url=process.env.EXPO_PUBLIC_SUPABASE_URL;
const key=process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
export const configured=!!url&&!!key;
const storage={
 async getItem(key:string){const meta=await SecureStore.getItemAsync(key);if(!meta)return null;const keys=JSON.parse(meta) as string[];const chunks=await Promise.all(keys.map(k=>SecureStore.getItemAsync(k)));return chunks.some(x=>x===null)?null:chunks.join('')},
 async setItem(key:string,value:string){const previous=await SecureStore.getItemAsync(key);const prefix=key+'.'+Crypto.randomUUID();const keys:string[]=[];for(let i=0;i<value.length;i+=1000){const k=prefix+'.'+keys.length;await SecureStore.setItemAsync(k,value.slice(i,i+1000));keys.push(k)}await SecureStore.setItemAsync(key,JSON.stringify(keys));if(previous)await Promise.all((JSON.parse(previous) as string[]).map(k=>SecureStore.deleteItemAsync(k)))},
 async removeItem(key:string){const meta=await SecureStore.getItemAsync(key);await SecureStore.deleteItemAsync(key);if(meta)await Promise.all((JSON.parse(meta) as string[]).map(k=>SecureStore.deleteItemAsync(k)))}
};
export const supabase=configured?createClient(url!,key!,{auth:{storage,autoRefreshToken:true,persistSession:true,detectSessionInUrl:false}}):null;
export function db(){if(!supabase)throw Error('Pulso necesita conectar sus servicios antes de usarse.');return supabase}
export async function rpc<T=any>(name:string,args:Record<string,unknown>={}):Promise<T>{const {data,error}=await db().rpc(name,args);if(error)throw error;return data as T}
export function photoURL(path:string){return db().storage.from('portfolio').getPublicUrl(path).data.publicUrl}
