import {forwardRef,useCallback,useEffect,useImperativeHandle,useRef,useState} from 'react';
import {ActivityIndicator,Pressable,StyleSheet,Text,View,type StyleProp,type ViewStyle} from 'react-native';
import {Camera,GeoJSONSource,Layer,Map,type CameraRef} from '@maplibre/maplibre-react-native';
import {pinFeatures,regionBounds,viewportRegion,validCoordinate,validRegion,type Coordinate,type MapPin,type Region} from '../lib/map-geometry';
export type {Region} from '../lib/map-geometry';
export type MapHandle={animateToRegion:(region:Region)=>void};
type Props={style?:StyleProp<ViewStyle>;initialRegion:Region;region?:Region;markers:MapPin[];userLocation?:Coordinate;onMarkerPress?:(id:string)=>void;onRegionChangeComplete?:(region:Region)=>void;onPress?:(coordinate:Coordinate)=>void;onPanDrag?:()=>void};
const MAP_STYLE='https://tiles.openfreemap.org/styles/liberty';
const PulsoMap=forwardRef<MapHandle,Props>(function PulsoMap({style,initialRegion,region,markers,userLocation,onMarkerPress,onRegionChangeComplete,onPress,onPanDrag},ref){
 const camera=useRef<CameraRef>(null);
 const latestRegion=useRef(region??initialRegion);
 const [ready,setReady]=useState(false),[failed,setFailed]=useState(false),[revision,setRevision]=useState(0);
 const initial=useRef({bounds:regionBounds(validRegion(initialRegion)?initialRegion:{latitude:25.6866,longitude:-100.3161,latitudeDelta:.08,longitudeDelta:.08})});
 const center=useCallback((r:Region)=>{if(!validRegion(r))return;latestRegion.current=r;if(ready)camera.current?.fitBounds(regionBounds(r),{duration:350})},[ready]);
 useImperativeHandle(ref,()=>({animateToRegion:center}),[center]);
 const controlled=region?JSON.stringify(region):'';
 useEffect(()=>{if(controlled)center(JSON.parse(controlled) as Region)},[controlled,center]);
 useEffect(()=>{if(ready)return;const timer=setTimeout(()=>setFailed(true),20000);return()=>clearTimeout(timer)},[ready,revision]);
 const retry=()=>{setReady(false);setFailed(false);setRevision(v=>v+1)};
 const user:GeoJSON.FeatureCollection<GeoJSON.Point>={type:'FeatureCollection',features:userLocation&&validCoordinate(userLocation)?[{type:'Feature',geometry:{type:'Point',coordinates:[userLocation.longitude,userLocation.latitude]},properties:{}}]:[]};
 return <View style={[styles.container,style]}>
 <Map key={revision} style={StyleSheet.absoluteFill} mapStyle={MAP_STYLE} androidView="texture" attribution attributionPosition={{bottom:8,left:8}} compass compassPosition={{top:12,right:12}}
 onDidFinishLoadingMap={()=>{setReady(true);setFailed(false);if(validRegion(latestRegion.current))camera.current?.fitBounds(regionBounds(latestRegion.current),{duration:0})}}
 onDidFailLoadingMap={()=>{setFailed(true)}}
 onRegionWillChange={e=>{if(e.nativeEvent.userInteraction)onPanDrag?.()}}
 onRegionDidChange={e=>{const r=viewportRegion(e.nativeEvent.center,e.nativeEvent.bounds);if(validRegion(r)){latestRegion.current=r;onRegionChangeComplete?.(r)}}}
 onPress={e=>{const p={longitude:e.nativeEvent.lngLat[0],latitude:e.nativeEvent.lngLat[1]};if(validCoordinate(p))onPress?.(p)}}>
 <Camera ref={camera} initialViewState={initial.current} minZoom={2} maxZoom={19}/>
 <GeoJSONSource id="pulso-shops" data={pinFeatures(markers)} onPress={e=>{e.stopPropagation();const id=e.nativeEvent.features[0]?.properties?.id;if(typeof id==='string'&&markers.some(p=>p.id===id))onMarkerPress?.(id)}}>
 <Layer id="pulso-shop-dots" type="circle" paint={{'circle-radius':10,'circle-color':['get','color'],'circle-stroke-color':'#ffffff','circle-stroke-width':3}}/>
 <Layer id="pulso-shop-labels" type="symbol" minzoom={12} layout={{'text-field':['get','title'],'text-font':['Noto Sans Regular'],'text-size':13,'text-offset':[0,1.5],'text-anchor':'top','text-max-width':12}} paint={{'text-color':['get','color'],'text-halo-color':'#ffffff','text-halo-width':4}}/>
 </GeoJSONSource>
 <GeoJSONSource id="pulso-user" data={user}><Layer id="pulso-user-halo" type="circle" paint={{'circle-radius':16,'circle-color':'#2678d8','circle-opacity':0.15}}/><Layer id="pulso-user-dot" type="circle" paint={{'circle-radius':7,'circle-color':'#2678d8','circle-stroke-color':'#fff','circle-stroke-width':3}}/></GeoJSONSource>
 </Map>
 {(!ready||failed)&&<View style={styles.overlay} pointerEvents="box-none"><View style={styles.notice}>{failed?<><Text style={styles.text}>No se pudo cargar el mapa. Revisa tu conexión.</Text><Pressable accessibilityRole="button" onPress={retry}><Text style={styles.retry}>Volver a intentar</Text></Pressable></>:<><ActivityIndicator color="#163D2E"/><Text style={styles.text}>Abriendo mapa…</Text></>}</View></View>}
 </View>
});
export default PulsoMap;
const styles=StyleSheet.create({container:{overflow:'hidden',backgroundColor:'#F5F6F3'},overlay:{position:'absolute',top:16,left:16,right:16,alignItems:'center'},notice:{padding:14,borderRadius:16,backgroundColor:'white',gap:8,alignItems:'center'},text:{color:'#163D2E',textAlign:'center'},retry:{color:'#163D2E',fontWeight:'700',padding:12}});
