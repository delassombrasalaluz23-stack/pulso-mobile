import {useEffect} from 'react';
import {AppState} from 'react-native';
import {router} from 'expo-router';
import * as Notifications from 'expo-notifications';
import {useAuth} from '../lib/auth';
import {setReminderUser,syncReminders} from '../lib/reminders';
export default function ReminderSync(){const {profile,ready}=useAuth();const user=profile?.role==='client'?profile.id:null;
useEffect(()=>{if(!ready)return;void setReminderUser(user).catch(()=>{});const refresh=()=>{if(user)void syncReminders(user).catch(()=>{})};const app=AppState.addEventListener('change',s=>{if(s==='active')refresh()});const timer=setInterval(()=>{if(AppState.currentState==='active')refresh()},60000);return()=>{app.remove();clearInterval(timer)}},[ready,user]);
useEffect(()=>{if(!ready||!profile)return;function open(n:Notifications.Notification){if(n.request.content.data?.appointment_id){router.push(profile?.role==='owner'?'/agenda':'/appointments');return}if(n.request.content.data?.kind==='pulso-appointment'&&n.request.content.data.user===user)router.push('/appointments')}
const previous=Notifications.getLastNotificationResponse();if(previous){open(previous.notification);Notifications.clearLastNotificationResponse()}
const sub=Notifications.addNotificationResponseReceivedListener(r=>open(r.notification));return()=>sub.remove()},[ready,user,profile]);return null}
