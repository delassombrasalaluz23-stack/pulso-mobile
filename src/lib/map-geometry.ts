export type Coordinate={latitude:number;longitude:number};
export type Region=Coordinate&{latitudeDelta:number;longitudeDelta:number};
export type MapPin=Coordinate&{id:string;title?:string;description?:string;color?:string};
export const validCoordinate=(p:Coordinate)=>Number.isFinite(p?.latitude)&&Math.abs(p.latitude)<=85&&Number.isFinite(p.longitude)&&Math.abs(p.longitude)<=180;
export const validRegion=(p:Region)=>validCoordinate(p)&&Number.isFinite(p.latitudeDelta)&&p.latitudeDelta>0&&p.latitudeDelta<=170&&Number.isFinite(p.longitudeDelta)&&p.longitudeDelta>0&&p.longitudeDelta<=360;
export function regionBounds(r:Region):[number,number,number,number]{return [r.longitude-r.longitudeDelta/2,Math.max(-85,r.latitude-r.latitudeDelta/2),r.longitude+r.longitudeDelta/2,Math.min(85,r.latitude+r.latitudeDelta/2)];}
export function viewportRegion(center:number[],bounds:number[]):Region{return {latitude:Math.max(-85,Math.min(85,center[1])),longitude:((center[0]+180)%360+360)%360-180,latitudeDelta:Math.max(.00001,Math.min(170,bounds[3]-bounds[1])),longitudeDelta:Math.max(.00001,Math.min(360,bounds[2]>=bounds[0]?bounds[2]-bounds[0]:bounds[2]+360-bounds[0]))};}
export function pinFeatures(markers:MapPin[]):GeoJSON.FeatureCollection<GeoJSON.Point>{return {type:'FeatureCollection',features:markers.filter(validCoordinate).map(p=>({type:'Feature',id:p.id,geometry:{type:'Point',coordinates:[p.longitude,p.latitude]},properties:{id:p.id,title:p.title??'',color:p.color||'#163D2E'}}))};}
