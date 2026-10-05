import * as Notifications from 'expo-notifications';
import * as SecureStore from 'expo-secure-store';
import {Platform} from 'react-native';
import {db} from './supabase';
import {reminderPlan} from './reminder-plan';
let currentUser:string|null=null;
let queue:Promise<unknown>=Promise.resolve();
function serial<T>(fn:()=>Promise<T>):Promise<T>{const result=queue.then(fn,fn);queue=result.catch(()=>{});return result}
const kind='pulso-appointment';
const key=(user:string)=>'pulso.reminders.'+user;
Notifications.setNotificationHandler({handleNotification:async notification=>{const data=notification.request.content.data;const show=data?.kind!==kind||data?.user===currentUser;return {shouldShowBanner:show,shouldShowList:show,shouldPlaySound:show,shouldSetBadge:false}}});
export async function remindersEnabled(user:string){return await SecureStore.getItemAsync(key(user))==='true'}
async function cancelWhere(predicate:(user:unknown)=>boolean){const items=await Notifications.getAllScheduledNotificationsAsync();for(const n of items)if(n.content.data?.kind===kind&&predicate(n.content.data.user))await Notifications.cancelScheduledNotificationAsync(n.identifier)}
export function setReminderUser(user:string|null){currentUser=user;return serial(async()=>{await cancelWhere(u=>u!==currentUser);if(user&&user===currentUser)await reconcile(user)})}
async function reconcile(user:string){
 if(user!==currentUser)return 0;
 if(!await remindersEnabled(user)){await cancelWhere(u=>u===user);return 0}
 const permission=await Notifications.getPermissionsAsync();if(!permission.granted){await cancelWhere(u=>u===user);return 0}
 const {data,error}=await db().from('appointments').select('id,starts_at,status').eq('customer_id',user).eq('status','confirmed').gt('starts_at',new Date().toISOString()).order('starts_at').limit(40);if(error)throw error;
 if(user!==currentUser)return 0;const plan=reminderPlan(data??[]);const desired=new Map(plan.map(r=>['pulso-'+user+'-'+r.appointment+'-'+r.at,r]));
 const existing=await Notifications.getAllScheduledNotificationsAsync();
 for(const n of existing){if(n.content.data?.kind!==kind)continue;if(n.content.data.user!==user||!desired.has(n.identifier))await Notifications.cancelScheduledNotificationAsync(n.identifier)}
 const known=new Set(existing.map(n=>n.identifier));
 for(const [identifier,r] of desired){if(user!==currentUser)return 0;if(known.has(identifier))continue;await Notifications.scheduleNotificationAsync({identifier,content:{title:'Pulso · Recordatorio de cita',body:r.hours===24?'Tienes una cita en aproximadamente 24 horas. Abre Pulso para revisar sus detalles.':'Tu cita es en aproximadamente una hora. Abre Pulso para revisar sus detalles.',sound:'default',data:{kind,user,appointment:r.appointment}},trigger:{type:Notifications.SchedulableTriggerInputTypes.DATE,date:new Date(r.at),channelId:'appointments'}})}
 return plan.length;
}
export function syncReminders(user:string){return serial(()=>reconcile(user))}
export async function changeReminders(user:string,enabled:boolean){
 if(user!==currentUser)throw Error('Inicia sesión como cliente para configurar tus recordatorios.');
 if(enabled){if(Platform.OS==='android')await Notifications.setNotificationChannelAsync('appointments',{name:'Recordatorios de citas',importance:Notifications.AndroidImportance.DEFAULT});const p=await Notifications.requestPermissionsAsync();if(!p.granted)throw Error('Activa las notificaciones en Ajustes del teléfono para recibir recordatorios.')}
 await SecureStore.setItemAsync(key(user),String(enabled));return syncReminders(user);
}
export function clearReminders(){currentUser=null;return serial(()=>cancelWhere(()=>true))}
