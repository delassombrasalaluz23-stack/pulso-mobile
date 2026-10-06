import {forwardRef,useEffect,useImperativeHandle,useRef,useState} from 'react';
import {ActivityIndicator,Linking,Pressable,StyleSheet,Text,View,type StyleProp,type ViewStyle} from 'react-native';
import {WebView,type WebViewMessageEvent} from 'react-native-webview';
import {mapDocument,scriptJSON,validCoordinate,validRegion,type Coordinate,type MapPin,type Region} from '../lib/map-document';
export type {Region} from '../lib/map-document';
export type MapHandle={animateToRegion:(region:Region)=>void};
type Props={style?:StyleProp<ViewStyle>;initialRegion:Region;region?:Region;markers:MapPin[];userLocation?:Coordinate;onMarkerPress?:(id:string)=>void;onRegionChangeComplete?:(region:Region)=>void;onPress?:(coordinate:Coordinate)=>void;onPanDrag?:()=>void};

const PulsoMap=forwardRef<MapHandle,Props>(function PulsoMap({style,initialRegion,region,markers,userLocation,onMarkerPress,onRegionChangeComplete,onPress,onPanDrag},ref){
  const web=useRef<WebView>(null);
  const pendingCenter=useRef<Region|null>(null);
  const [source]=useState(()=>({html:mapDocument(initialRegion),baseUrl:'https://github.com/delassombrasalaluz23-stack/pulso-mobile/'}));
  const [ready,setReady]=useState(false);
  const [failed,setFailed]=useState(false);
  const [revision,setRevision]=useState(0);
  const payload=scriptJSON({markers:markers.filter(validCoordinate),userLocation:userLocation&&validCoordinate(userLocation)?userLocation:null});
  const controlledRegion=region?scriptJSON(region):null;
  useImperativeHandle(ref,()=>({animateToRegion:(r)=>{if(!validRegion(r))return;pendingCenter.current=r;if(ready)web.current?.injectJavaScript(`window.pulsoMap.center(${scriptJSON(r)});true;`);}}),[ready]);
  useEffect(()=>{if(ready)web.current?.injectJavaScript(`window.pulsoMap.update(${payload});true;`);},[payload,ready]);
  useEffect(()=>{if(ready&&controlledRegion)web.current?.injectJavaScript(`window.pulsoMap.center(${controlledRegion});true;`);},[controlledRegion,ready]);
  function message(event:WebViewMessageEvent){
    try{
      const m=JSON.parse(event.nativeEvent.data);
      if(m.type==='ready'){setReady(true);setFailed(false);if(pendingCenter.current)web.current?.injectJavaScript(`window.pulsoMap.center(${scriptJSON(pendingCenter.current)});true;`);}
      if(m.type==='region'&&validRegion(m.region)){pendingCenter.current=m.region;onRegionChangeComplete?.(m.region);}
      if(m.type==='press'&&validCoordinate(m.coordinate))onPress?.(m.coordinate);
      if(m.type==='marker'&&typeof m.id==='string'&&markers.some(p=>p.id===m.id))onMarkerPress?.(m.id);
      if(m.type==='pan')onPanDrag?.();
      if(m.type==='attribution')void Linking.openURL('https://www.openstreetmap.org/copyright').catch(()=>{});
    }catch{/* Ignore malformed messages from the isolated map view. */}
  }
  return <View style={[styles.container,style]}><WebView key={revision} ref={web} source={source} style={styles.web} originWhitelist={['*']} onMessage={message}
    javaScriptEnabled cacheEnabled cacheMode="LOAD_DEFAULT" domStorageEnabled={false} geolocationEnabled={false}
    applicationNameForUserAgent="PulsoBarberias/0.3 (https://github.com/delassombrasalaluz23-stack/pulso-mobile)"
    allowFileAccess={false} allowFileAccessFromFileURLs={false} allowUniversalAccessFromFileURLs={false} mixedContentMode="never" setSupportMultipleWindows={false}
    onShouldStartLoadWithRequest={r=>r.url==='about:blank'||r.url===source.baseUrl}
    onError={()=>{setReady(false);setFailed(true);}} onContentProcessDidTerminate={()=>{setReady(false);setRevision(v=>v+1);}} onRenderProcessGone={()=>{setReady(false);setRevision(v=>v+1);}}
    scrollEnabled={false} bounces={false} overScrollMode="never"/>
    {!ready&&<View style={styles.overlay}>{failed?<><Text style={styles.text}>No se pudo abrir el mapa.</Text><Pressable accessibilityRole="button" onPress={()=>{setFailed(false);setRevision(v=>v+1);}}><Text style={styles.retry}>Volver a intentar</Text></Pressable></>:<><ActivityIndicator color="#244b34"/><Text style={styles.text}>Abriendo mapa…</Text></>}</View>}
  </View>;
});
export default PulsoMap;
const styles=StyleSheet.create({container:{overflow:'hidden',backgroundColor:'#e8efde'},web:{flex:1,backgroundColor:'#e8efde'},overlay:{position:'absolute',top:0,bottom:0,left:0,right:0,alignItems:'center',justifyContent:'center',gap:12,backgroundColor:'#e8efde'},text:{color:'#244b34'},retry:{color:'#244b34',fontWeight:'700',padding:12}});
