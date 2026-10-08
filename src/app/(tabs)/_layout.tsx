import type {ColorValue} from 'react-native';
import {Tabs} from 'expo-router';
import Ionicons from '@expo/vector-icons/Ionicons';
import {useAuth} from '../../lib/auth';
import {colors} from '../../components/ui';
export default function Layout(){const {profile}=useAuth();const owner=profile?.role==='owner';const icon=(name:React.ComponentProps<typeof Ionicons>['name'])=>function TabIcon({color,size}:{color:ColorValue;size:number}){return <Ionicons name={name} size={size} color={color}/>};return <Tabs screenOptions={{headerShown:false,tabBarActiveTintColor:colors.green,tabBarInactiveTintColor:colors.muted,tabBarStyle:{backgroundColor:colors.white,borderTopColor:colors.line},tabBarLabelStyle:{fontSize:11,fontWeight:'700'}}}>
<Tabs.Screen name="index" options={{title:owner?'Hoy':'Explorar',tabBarIcon:icon(owner?'today-outline':'compass-outline')}}/>
<Tabs.Protected guard={!owner}><Tabs.Screen name="appointments" options={{title:'Mis citas',tabBarIcon:icon('calendar-outline')}}/></Tabs.Protected>
<Tabs.Screen name="ranking" options={{title:'Ranking',href:owner?null:undefined,tabBarIcon:icon('trophy-outline')}}/>
<Tabs.Protected guard={!owner}><Tabs.Screen name="favorites" options={{title:'Favoritas',tabBarIcon:icon('heart-outline')}}/></Tabs.Protected>
<Tabs.Protected guard={owner}><Tabs.Screen name="services" options={{title:'Servicios',tabBarIcon:icon('cut-outline')}}/><Tabs.Screen name="customers" options={{title:'Clientes',tabBarIcon:icon('people-outline')}}/><Tabs.Screen name="business" options={{title:'Mi negocio',tabBarIcon:icon('storefront-outline')}}/><Tabs.Screen name="agenda" options={{href:null}}/></Tabs.Protected>
<Tabs.Screen name="account" options={{title:'Cuenta',href:owner?null:undefined,tabBarIcon:icon('person-circle-outline')}}/>
</Tabs>}
