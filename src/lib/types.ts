export type Shop={verified?:boolean;id:string;owner_id:string;name:string;description:string;address:string;municipality:string;state:string;country:string;lat:number;lng:number;timezone:string;open_hour:number;close_hour:number;days:number[];deposit_percent:number;cancel_hours:number;active:boolean};
export type Barber={id:string;shop_id:string;name:string;specialty:string;active:boolean};
export type Service={id:string;shop_id:string;name:string;description:string;kind:'cut'|'addon';price_cents:number;duration_minutes:number;active:boolean};
export type Photo={id:string;shop_id:string;kind:string;barber_id:string|null;service_id:string|null;caption:string;storage_path:string};
export type Appointment={late_minutes?:number|null;late_notified_at?:string|null;id:string;customer_id:string;shop_id:string;barber_id:string;customer_name:string;shop_name:string;barber_name:string;starts_at:string;ends_at:string;lines:{id?:string;name:string;price_cents:number;minutes:number}[];total_cents:number;deposit_cents:number;cancel_hours:number;status:string;outcome:string;payment_mode:string;discount_cents:number;loyalty_reward_id:string|null;offer_id:string|null;offer_title:string|null;reference_path:string|null};
export type Customer={customer_id:string;name:string;visits:number;last_visit:string;marketing:boolean};
export const money=(cents:number)=>new Intl.NumberFormat('es-MX',{style:'currency',currency:'MXN'}).format(cents/100);
export function distance(a:number,b:number,c:number,d:number){const rad=Math.PI/180;const h=Math.sin((c-a)*rad/2)**2+Math.cos(a*rad)*Math.cos(c*rad)*Math.sin((d-b)*rad/2)**2;return 12742*Math.atan2(Math.sqrt(h),Math.sqrt(Math.max(0,1-h)))}
export function quote(service:Service,extras:Service[],percent:number){const total=service.price_cents+extras.reduce((n,s)=>n+s.price_cents,0);return {total,deposit:Math.round(total*percent/100),minutes:service.duration_minutes+extras.reduce((n,s)=>n+s.duration_minutes,0)}}

export type TodaySlot={shop_id:string;barber_id:string;service_id:string;service_name:string;starts_at:string;price_cents:number;timezone:string};
export type LoyaltyProgram={shop_id:string;visits_required:number;discount_cents:number;enabled:boolean};
export type LoyaltyReward={id:string;shop_id:string;customer_id:string;discount_cents:number;used_appointment_id:string|null;created_at:string};

export type Offer={id:string;shop_id:string;service_id:string;title:string;kind:'percent'|'amount'|'price';value:number;ends_at:string;conditions:string;active:boolean};
export function offerDiscount(o:Offer,price:number){return Math.max(0,o.kind==='percent'?Math.round(price*o.value/100):o.kind==='amount'?Math.min(price,o.value):price-o.value)}
