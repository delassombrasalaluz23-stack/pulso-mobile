import {useCallback,useState} from 'react';
import {Text} from 'react-native';
import {router,useFocusEffect} from 'expo-router';
import {useAuth} from '../lib/auth';
import {db} from '../lib/supabase';
import {Button,Card,Copy,Failure,Screen,Title} from '../components/ui';
export default function Notices(){const {session,profile}=useAuth();const [rows,setRows]=useState<{id:string;title:string;body:string;read_at:string|null;created_at:string}[]>([]);const [error,setError]=useState('');useFocusEffect(useCallback(()=>{void(async()=>{const r=await db().from('booking_notifications').select('*').eq('user_id',session!.user.id).order('created_at',{ascending:false}).limit(100);if(r.error)setError(r.error.message);else setRows(r.data??[])})()},[session]));return <Screen><Title>Tus avisos.</Title><Failure message={error}/>{!rows.length&&<Copy>Aquí aparecerán las novedades de tus citas.</Copy>}{rows.map(n=><Card key={n.id}><Text style={{fontWeight:'700'}}>{n.read_at?'':'● '}{n.title}</Text><Copy>{n.body}</Copy><Copy>{new Date(n.created_at).toLocaleString('es-MX')}</Copy><Button secondary title="Ver mis citas" onPress={async()=>{await db().from('booking_notifications').update({read_at:new Date().toISOString()}).eq('id',n.id);router.push(profile?.role==='owner'?'/agenda':'/appointments')}}/></Card>)}</Screen>}
