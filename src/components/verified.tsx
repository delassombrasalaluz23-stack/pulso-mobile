import {useEffect,useState} from 'react';
import {Text} from 'react-native';
import {db} from '../lib/supabase';
import {s} from './ui';
export default function Verified({shop}:{shop:string}){const [yes,setYes]=useState(false);useEffect(()=>{let active=true;void db().from('shop_trust').select('verified_at,suspended').eq('shop_id',shop).maybeSingle().then(r=>{if(active)setYes(!!r.data?.verified_at&&!r.data?.suspended)});return()=>{active=false}},[shop]);return yes?<Text style={s.pill}>✓ BARBERÍA VERIFICADA</Text>:null}
