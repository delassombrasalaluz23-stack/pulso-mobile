import {Alert,Linking} from 'react-native';
import {Button,report} from './ui';
import {db} from '../lib/supabase';
export default function Directions({shopId}:{shopId:string}){async function open(){try{const {data,error}=await db().from('shops').select('name,lat,lng').eq('id',shopId).single();if(error)throw error;const dest=`${data.lat},${data.lng}`;const launch=(url:string)=>void Linking.openURL(url).catch(report);Alert.alert('Cómo llegar',data.name,[{text:'Apple Maps',onPress:()=>launch(`https://maps.apple.com/?daddr=${dest}&q=${encodeURIComponent(data.name)}`)},{text:'Google Maps',onPress:()=>launch(`https://www.google.com/maps/dir/?api=1&destination=${dest}`)},{text:'Volver',style:'cancel'}])}catch(e){report(e)}}return <Button secondary title="Cómo llegar" onPress={open}/>}
