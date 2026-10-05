import {money,type Service} from './types';
export type OfferKind='percent'|'amount'|'price';
export function offerSummary(service:Service,kind:OfferKind,value:string,until:string,conditions:string){
 const amount=Number(value.replace(',','.'));if(!value.trim()||!Number.isFinite(amount)||amount<=0)throw Error('Escribe un importe o porcentaje mayor que cero.');
 if(kind==='percent'&&(amount>100||amount%1!==0))throw Error('El porcentaje debe ser un número entero entre 1 y 100.');
 const cents=Math.round(amount*100);if(kind!=='percent'&&Math.abs(amount*100-cents)>.000001)throw Error('Usa como máximo dos decimales.');
 const final=kind==='percent'?Math.round(service.price_cents*(1-amount/100)):kind==='amount'?service.price_cents-cents:cents;
 if(final<0||final>=service.price_cents)throw Error('El precio promocional debe ser menor al original y no negativo.');
 const date=new Date(until+'T23:59:59');if(!/^\d{4}-\d{2}-\d{2}$/.test(until)||Number.isNaN(date.getTime())||date.getFullYear()!==Number(until.slice(0,4))||date.getMonth()+1!==Number(until.slice(5,7))||date.getDate()!==Number(until.slice(8,10))||date.getTime()<Date.now())throw Error('Indica una fecha de vigencia válida, hoy o posterior, con formato AAAA-MM-DD.');
 const label=kind==='percent'?amount+'% de descuento':kind==='amount'?money(cents)+' de descuento':'Precio especial';
 return `${service.name} · ${label}\nAntes: ${money(service.price_cents)} · Ahora: ${money(final)}\nVálida hasta ${until}, al cierre del local.\n${conditions.trim()||'Sin condiciones adicionales.'}\nCanje en el local. La reserva en Pulso conserva el precio de catálogo.`;
}
