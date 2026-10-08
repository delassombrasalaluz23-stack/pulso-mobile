import type {ReactNode} from 'react';
import {Pressable,Text,View} from 'react-native';
import Ionicons from '@expo/vector-icons/Ionicons';
import {colors,s} from './ui';
export default function BookingSection({step,title,summary,open,onToggle,children}:{step:string;title:string;summary:string;open:boolean;onToggle:()=>void;children:ReactNode}){
 return <View style={{backgroundColor:colors.white,borderWidth:1,borderColor:open?colors.green:colors.line,borderRadius:22,overflow:'hidden'}}>
  <Pressable accessibilityRole="button" accessibilityState={{expanded:open}} accessibilityLabel={`${title}. ${summary}`} accessibilityHint={open?'Ocultar opciones':'Mostrar opciones'} onPress={onToggle} style={({pressed})=>({padding:18,flexDirection:'row',alignItems:'center',gap:12,backgroundColor:pressed?'#EFF4E7':colors.white,minHeight:84})}>
   <View style={{width:32,height:32,borderRadius:11,backgroundColor:open?colors.green:'#EFF4E7',alignItems:'center',justifyContent:'center'}}><Text style={{fontSize:12,fontWeight:'800',color:open?colors.lime:colors.green}}>{step}</Text></View>
   <View style={{flex:1,gap:5}}><Text style={{fontSize:18,fontWeight:'700',color:colors.ink}}>{title}</Text><Text style={s.muted}>{summary}</Text></View>
   <Ionicons name={open?'chevron-up':'chevron-down'} size={22} color={colors.green}/>
  </Pressable>
  {open&&<View style={{padding:16,paddingTop:4,gap:14}}>{children}</View>}
 </View>
}
