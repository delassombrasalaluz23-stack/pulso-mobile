export type ReminderAppointment={id:string;starts_at:string;status:string};
export function reminderPlan(appointments:ReminderAppointment[],now=Date.now()){
 return appointments.filter(a=>a.status==='confirmed').flatMap(a=>[24,1].map(hours=>({appointment:a.id,at:Date.parse(a.starts_at)-hours*3600000,hours}))).filter(r=>Number.isFinite(r.at)&&r.at>now+5000).sort((a,b)=>a.at-b.at||a.appointment.localeCompare(b.appointment)).slice(0,40);
}
