import {useCallback,useState} from 'react';
import {Text} from 'react-native';
import {useFocusEffect} from 'expo-router';
import {useAuth} from '../lib/auth';
import {changeReminders,remindersEnabled,syncReminders} from '../lib/reminders';
import {Button,Card,Copy,report,s} from './ui';
export default function ReminderSettings(){const {session}=useAuth();const [enabled,setEnabled]=useState(false);const [busy,setBusy]=useState(false);const [note,setNote]=useState('');
useFocusEffect(useCallback(()=>{let active=true;if(session)void remindersEnabled(session.user.id).then(v=>{if(active)setEnabled(v)});return()=>{active=false}},[session?.user.id]));
async function toggle(){if(!session)return;setBusy(true);try{const count=await changeReminders(session.user.id,!enabled);setEnabled(!enabled);setNote(!enabled?count+' avisos programados en este teléfono.':'Recordatorios desactivados.')}catch(e){report(e)}finally{setBusy(false)}}
return <Card><Text style={s.heading}>Que no se te pase tu corte</Text><Copy>Recordatorios 24 horas y 1 hora antes, cuando todavía falte ese tiempo. Son opcionales y se programan en este teléfono.</Copy><Button secondary title={busy?'Actualizando…':enabled?'Desactivar recordatorios':'Activar recordatorios'} disabled={busy} onPress={toggle}/>{enabled&&<Button secondary title="Actualizar recordatorios" disabled={busy} onPress={async()=>{if(!session)return;setBusy(true);try{setNote((await syncReminders(session.user.id))+' avisos programados. Si no aparecen, revisa el permiso de notificaciones en Ajustes.')}catch(e){report(e)}finally{setBusy(false)}}}/>}{!!note&&<Copy>{note}</Copy>}<Copy>Los cambios y cancelaciones se sincronizan al abrir Pulso. Abre la app para confirmar los detalles antes de salir.</Copy></Card>}
