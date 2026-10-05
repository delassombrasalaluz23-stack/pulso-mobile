import {useCallback,useState} from 'react';
import {Text} from 'react-native';
import {router,useFocusEffect} from 'expo-router';
import {useAuth} from '../../lib/auth';
import {db} from '../../lib/supabase';
import {type Shop} from '../../lib/types';
import {Brand,Button,Card,Copy,Empty,Failure,Screen,Title,s} from '../../components/ui';
export default function Favorites(){const {session}=useAuth();const [shops,setShops]=useState<Shop[]>([]);const [error,setError]=useState('');const load=useCallback(async()=>{if(!session)return;const {data,error}=await db().from('favorites').select('shop_id,shops(*)').eq('customer_id',session.user.id);if(error){setError(error.message);return}setError('');setShops((data??[]).map((x:any)=>x.shops).filter(Boolean))},[session?.user.id]);useFocusEffect(useCallback(()=>{void load()},[load]));return <Screen><Brand/><Title>Tus lugares de siempre.</Title><Copy>Un buen corte merece volver.</Copy><Failure message={error} onRetry={load}/>{!session?<Button title="Iniciar sesión" onPress={()=>router.push('/login')}/>:shops.length?shops.map(shop=><Card key={shop.id}><Text style={s.heading}>{shop.name}</Text><Copy>{shop.address}</Copy><Button title="Ver barbería" onPress={()=>router.push('/shop/'+shop.id as any)}/></Card>):<Empty icon="heart-outline" title="Encuentra tu favorita" body="Toca el corazón en el perfil de una barbería para tenerla siempre a mano."/>}</Screen>}
