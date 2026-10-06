import {leafletCSS,leafletJS} from './leaflet-bundle';

export type Coordinate={latitude:number;longitude:number};
export type Region=Coordinate&{latitudeDelta:number;longitudeDelta:number};
export type MapPin=Coordinate&{id:string;title?:string;description?:string;color?:string};
export const validCoordinate=(p:Coordinate)=>Number.isFinite(p?.latitude)&&Math.abs(p.latitude)<=85&&Number.isFinite(p?.longitude)&&Math.abs(p.longitude)<=180;
export const validRegion=(p:Region)=>validCoordinate(p)&&Number.isFinite(p.latitudeDelta)&&p.latitudeDelta>0&&p.latitudeDelta<=170&&Number.isFinite(p.longitudeDelta)&&p.longitudeDelta>0&&p.longitudeDelta<=360;
// Escaping is also required for injected messages containing shop/customer names.
export const scriptJSON=(value:unknown)=>JSON.stringify(value).replace(/</g,'\\u003c').replace(/\u2028/g,'\\u2028').replace(/\u2029/g,'\\u2029');

export function mapDocument(initial:Region){return `<!doctype html><html lang="es"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src https://tile.openstreetmap.org data:; connect-src 'none';">
<style>${leafletCSS}
html,body,#map{margin:0;width:100%;height:100%;background:#e8efde} .leaflet-container{font-family:system-ui,sans-serif}
.leaflet-control-attribution{font-size:11px!important;background:white!important;color:#24362d!important}
.leaflet-control-attribution a{color:#244b34!important} .leaflet-tooltip{white-space:normal;max-width:180px}
#error{display:none;position:absolute;top:8px;left:48px;right:8px;z-index:1000;padding:8px;background:white;border-radius:8px;font:12px system-ui;color:#6b2424}
</style></head><body><div id="map" aria-label="Mapa de Pulso"></div><div id="error" role="status">No se pudo cargar parte del mapa. Revisa tu conexión y vuelve a abrir esta pantalla.</div>
<script>${leafletJS}</script><script>
(function(){
var initial=${scriptJSON(initial)}, send=function(m){window.ReactNativeWebView.postMessage(JSON.stringify(m));};
var map=L.map('map',{zoomControl:true,attributionControl:false,minZoom:2,maxZoom:19,worldCopyJump:true});
L.control.attribution({position:'bottomleft',prefix:false}).addTo(map);
// Only visible tiles, no bulk downloads/prefetch. WebView's HTTP cache remains enabled.
var tiles=L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,keepBuffer:0,updateWhenIdle:true,updateWhenZooming:false,attribution:'© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'}).addTo(map);
tiles.on('tileerror',function(){document.getElementById('error').style.display='block';});
tiles.on('tileload',function(){document.getElementById('error').style.display='none';});
var pins=L.layerGroup().addTo(map), user=L.layerGroup().addTo(map);
function center(r){map.fitBounds([[Math.max(-85,r.latitude-r.latitudeDelta/2),r.longitude-r.longitudeDelta/2],[Math.min(85,r.latitude+r.latitudeDelta/2),r.longitude+r.longitudeDelta/2]],{animate:false});}
center(initial);
window.pulsoMap={center:center,update:function(data){
pins.clearLayers();user.clearLayers();
data.markers.forEach(function(p){
var marker=L.circleMarker([p.latitude,p.longitude],{radius:10,color:'white',weight:3,fillColor:p.color||'#244b34',fillOpacity:1,bubblingMouseEvents:false}).addTo(pins);
var label=document.createElement('span');label.textContent=[p.title,p.description].filter(Boolean).join(' · ');
if(label.textContent)marker.bindTooltip(label,{direction:'top'});
marker.on('click',function(){send({type:'marker',id:p.id});});
});
if(data.userLocation)L.circleMarker([data.userLocation.latitude,data.userLocation.longitude],{radius:7,color:'white',weight:3,fillColor:'#2678d8',fillOpacity:1,interactive:false}).addTo(user);
}};
map.on('dragstart',function(){send({type:'pan'});});
map.on('moveend',function(){var c=map.getCenter().wrap(),b=map.getBounds();send({type:'region',region:{latitude:Math.max(-85,Math.min(85,c.lat)),longitude:c.lng,latitudeDelta:Math.min(170,b.getNorth()-b.getSouth()),longitudeDelta:Math.min(360,b.getEast()-b.getWest())}});});
map.on('click',function(e){var p=e.latlng.wrap();send({type:'press',coordinate:{latitude:p.lat,longitude:p.lng}});});
document.addEventListener('click',function(e){var a=e.target.closest('a');if(a){e.preventDefault();send({type:'attribution'});}});
window.addEventListener('resize',function(){map.invalidateSize();});
send({type:'ready'});
})();</script></body></html>`;}
