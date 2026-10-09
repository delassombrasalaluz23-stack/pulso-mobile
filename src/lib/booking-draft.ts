import * as SecureStore from 'expo-secure-store';
export type BookingDraft={cut:string;extras:string[];barber:string;day:string;slot:string;request:string;offer:string;reward:string;saved:number};
let writes=Promise.resolve();
function ordered(action:()=>Promise<void>){const result=writes.then(action);writes=result.catch(()=>{});return result}
const key=(user:string,shop:string)=>`pulso.draft.${user}.${shop}`;
export async function readDraft(user:string,shop:string):Promise<BookingDraft|null>{try{const raw=await SecureStore.getItemAsync(key(user,shop));if(!raw)return null;const d=JSON.parse(raw);if(Date.now()-d.saved>86400000||!Array.isArray(d.extras)||typeof d.request!=='string')return null;return d}catch{return null}}
export async function saveDraft(user:string,shop:string,draft:BookingDraft){await ordered(()=>SecureStore.setItemAsync(key(user,shop),JSON.stringify(draft)))}
export async function removeDraft(user:string,shop:string){await ordered(()=>SecureStore.deleteItemAsync(key(user,shop)))}
export type PendingBooking={request:string;args:Record<string,unknown>;paid:boolean};
export async function readPending(user:string,shop:string):Promise<PendingBooking|null>{const raw=await SecureStore.getItemAsync(key(user,shop)+'.pending');return raw?JSON.parse(raw):null}
export async function savePending(user:string,shop:string,value:PendingBooking){await SecureStore.setItemAsync(key(user,shop)+'.pending',JSON.stringify(value))}
export async function removePending(user:string,shop:string){await SecureStore.deleteItemAsync(key(user,shop)+'.pending')}
