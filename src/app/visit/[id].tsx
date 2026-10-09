import {Redirect,useLocalSearchParams} from 'expo-router';
import {useAuth} from '../../lib/auth';
import PublicShop from '../guest-shop/[id]';
export default function Visit(){const {id}=useLocalSearchParams<{id:string}>();const {profile,ready}=useAuth();if(!ready)return null;if(!/^[0-9a-f-]{36}$/i.test(id??''))return <Redirect href="/"/>;return profile?.role==='client'?<Redirect href={{pathname:'/shop/[id]',params:{id}}}/>:<PublicShop/>}
