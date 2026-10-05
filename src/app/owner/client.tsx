import {useCallback,useState} from 'react';
import {useFocusEffect,useLocalSearchParams} from 'expo-router';
import {Text} from 'react-native';
import {db} from '../../lib/supabase';
import {useAuth} from '../../lib/auth';
import {Appointment,money} from '../../lib/types';
import HaircutRecord from '../../components/haircut-record';
import {Card,Copy,Failure,Screen,Title,s} from '../../components/ui';
export default function ClientHistory(){const {id}=useLocalSearchParams<{id:string}>();const {session}=useAuth();const [rows,setRows]=useState<Appointment[]>([]);const [error,setError]=useState('');useFocusEffect(useCallback(()=>{let active=true;void(async()=>{try{const sh=await db().from('shops').select('id').eq('owner_id',session!.user.id).single();if(sh.error)throw sh.error;const r=await db().from('appointments').select('*').eq('shop_id',sh.data.id).eq('customer_id',id).eq('status','completed').order('starts_at',{ascending:false});if(r.error)throw r.error;if(active){setRows(r.data??[]);setError('')}}catch(e){if(active)setError((e as Error).message)}})();return()=>{active=false}},[session,id]));return <Screen><Title>{rows[0]?.customer_name??'Historial del cliente'}</Title><Copy>Sus cortes realizados en tu barbería, con los detalles para repetir su estilo.</Copy><Failure message={error}/>{rows.map(a=><Card key={a.id}><Text style={s.heading}>{new Date(a.starts_at).toLocaleDateString('es-MX')}</Text><Copy>{a.barber_name}</Copy>{a.lines.map((l,i)=><Copy key={i}>{l.name} · {money(l.price_cents)}</Copy>)}<HaircutRecord a={a} owner/></Card>)}{!rows.length&&!error&&<Copy>No hay visitas completadas de este cliente en tu barbería.</Copy>}</Screen>}
