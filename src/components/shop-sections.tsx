import {Image,Pressable,ScrollView,Text,View} from 'react-native';
import {router} from 'expo-router';
import {photoURL} from '../lib/supabase';
import type {Barber,Photo} from '../lib/types';
import {ShopReviews} from './review';
import {Button,Card,Copy,Empty,colors,s} from './ui';
export type ShopTab='services'|'team'|'work'|'reviews';
export function ShopTabs({value,onChange}:{value:ShopTab;onChange:(v:ShopTab)=>void}){return <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{gap:8}}>{(['services','team','work','reviews'] as ShopTab[]).map((v,i)=><Pressable key={v} accessibilityRole="tab" accessibilityState={{selected:value===v}} onPress={()=>onChange(v)} style={{paddingVertical:13,paddingHorizontal:17,borderRadius:16,backgroundColor:value===v?colors.green:colors.white,borderWidth:1,borderColor:colors.line}}><Text style={{fontWeight:'700',color:value===v?'white':colors.ink}}>{['Servicios','Equipo','Trabajos','Opiniones'][i]}</Text></Pressable>)}</ScrollView>}
export function ShopSectionContent({tab,shop,photos,barbers,guest=false,onSelectBarber}:{tab:ShopTab;shop:string;photos:Photo[];barbers:Barber[];guest?:boolean;onSelectBarber?:(id:string)=>void}){
 if(tab==='team')return <View style={{gap:12}}>{barbers.length?barbers.map(b=>{const photo=photos.find(p=>p.barber_id===b.id);return <Card key={b.id}><View style={[s.row,{flexWrap:'nowrap'}]}>{photo&&<Image source={{uri:photoURL(photo.storage_path)}} style={{width:64,height:64,borderRadius:20}}/>}<View style={{flex:1,gap:4}}><Text style={s.heading}>{b.name}</Text><Copy>{b.specialty||'Barbero profesional'}</Copy><Text style={s.pill}>DISPONIBLE</Text></View></View><Button secondary title={'Elegir a '+b.name} onPress={()=>guest?router.push('/login'):onSelectBarber?.(b.id)}/></Card>}):<Empty icon="people-outline" title="Equipo por publicar" body="La barbería aún no tiene barberos disponibles."/>}</View>;
 if(tab==='work'){const gallery=photos.filter(p=>!p.barber_id);return <View style={{gap:14}}>{gallery.length?gallery.map(p=><Card key={p.id}><Image source={{uri:photoURL(p.storage_path)}} style={[s.photo,{height:240}]}/>{!!p.caption&&<Copy>{p.caption}</Copy>}{!guest&&<Button secondary title="Reportar foto" onPress={()=>router.push({pathname:'/support',params:{kind:'photo',target:p.id}})}/>}</Card>):<Empty icon="images-outline" title="Galería por estrenar" body="Las fotos del local y sus cortes aparecerán aquí."/>}</View>}
 if(tab==='reviews')return guest?<Card><Copy>Entra a Pulso para consultar las opiniones de visitas verificadas.</Copy><Button title="Entrar a Pulso" onPress={()=>router.push('/login')}/></Card>:<ShopReviews shop={shop}/>;
 return null;
}
