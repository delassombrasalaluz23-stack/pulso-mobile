export type AddressSuggestion={id:string;address:string;municipality:string;state:string;country:string;lat:number;lng:number;label:string;precise:boolean};
export function parseAddresses(data:unknown):AddressSuggestion[]{
 const features=(data as {features?:unknown[]})?.features;if(!Array.isArray(features))return [];
 return features.flatMap((f:unknown)=>{const v=f as {geometry?:{type?:string;coordinates?:number[]};properties?:Record<string,unknown>};const p=v.properties??{},c=v.geometry?.coordinates;const str=(key:string)=>typeof p[key]==='string'?(p[key] as string).trim():'';
 if(v.geometry?.type!=='Point'||!c||!Number.isFinite(c[0])||!Number.isFinite(c[1])||Math.abs(c[0])>180||Math.abs(c[1])>85)return [];
 const street=str('street')||(str('type')==='street'?str('name'):''),number=str('housenumber'),name=str('name');
 if(!street&&!name)return [];
 if(['city','state','country','county','district','locality'].includes(str('type')))return [];
 const address=[street||name,number].filter(Boolean).join(' '),municipality=str('county')||str('city'),state=str('state'),country=str('country');
 const label=[name&&name!==street?name:'',address,str('district'),municipality,state,country].filter(Boolean).join(', ');
 return [{id:String(p.osm_type??'')+String(p.osm_id??label),address,municipality,state,country,lat:c[1],lng:c[0],label,precise:!!number||!!name&&!!street&&name!==street&&str('type')!=='street'}];
 });
}
const cache=new Map<string,AddressSuggestion[]>();
export async function searchAddresses(query:string,signal:AbortSignal):Promise<AddressSuggestion[]>{
 const q=query.trim();if(q.length<4)return [];if(cache.has(q))return cache.get(q)!;
 const endpoint=process.env.EXPO_PUBLIC_GEOCODER_URL||'https://photon.komoot.io';
 const response=await fetch(`${endpoint.replace(/\/$/,'')}/api/?q=${encodeURIComponent(q)}&limit=6&countrycode=MX`,{signal,headers:{Accept:'application/json'}});
 if(!response.ok)throw Error('No pudimos buscar direcciones. Intenta de nuevo en un momento.');
 const results=parseAddresses(await response.json());if(cache.size>=40)cache.delete(cache.keys().next().value!);cache.set(q,results);return results;
}
