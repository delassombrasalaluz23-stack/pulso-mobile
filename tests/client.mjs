import fs from 'node:fs';
import assert from 'node:assert/strict';
import ts from 'typescript';
const modules=new Map();
function load(name){if(modules.has(name))return modules.get(name);const source=fs.readFileSync('src/lib/'+name+'.ts','utf8');const code=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;const m={exports:{}};new Function('require','exports','module',code)(path=>load(path.replace('./','')),m.exports,m);modules.set(name,m.exports);return m.exports}
const {reminderPlan}=load('reminder-plan');
const now=Date.parse('2026-10-03T00:00:00Z');const list=[{id:'future',status:'confirmed',starts_at:'2026-10-05T00:00:00Z'},{id:'cancelled',status:'cancelled',starts_at:'2026-10-05T00:00:00Z'},{id:'soon',status:'confirmed',starts_at:'2026-10-03T00:30:00Z'},{id:'invalid',status:'confirmed',starts_at:'bad'}];
assert.deepEqual(reminderPlan(list,now),[{appointment:'future',at:now+24*3600000,hours:24},{appointment:'future',at:now+47*3600000,hours:1}]);
assert.equal(reminderPlan([{id:'later-today',status:'confirmed',starts_at:new Date(now+2*3600000).toISOString()}],now).length,1);
assert.equal(reminderPlan(Array.from({length:50},(_,i)=>({id:String(i),status:'confirmed',starts_at:new Date(now+(i+2)*86400000).toISOString()})),now).length,40);
const {localDay,nextDay,repeatSelection}=load('booking-helpers');assert.equal(localDay(new Date('2026-10-03T02:00:00Z'),'America/Monterrey'),'2026-10-02');assert.equal(nextDay('2026-12-31',1),'2027-01-01');
const services=[{id:'cut',kind:'cut'},{id:'beard',kind:'addon'}];const appointment={barber_id:'barber',lines:[{id:'cut'},{id:'beard'}]};assert.deepEqual(repeatSelection(appointment,services,[{id:'barber'}]),{cut:'cut',extras:['beard'],barber:'barber',missing:false});assert.equal(repeatSelection(appointment,services.slice(0,1),[]).missing,true);assert.equal(repeatSelection(appointment,[],[]).cut,'');
const {offerSummary}=load('promotion');const service={name:'Fade',price_cents:30000};assert.match(offerSummary(service,'percent','20','2099-12-31',''),/240\.00/);assert.match(offerSummary(service,'amount','50','2099-12-31',''),/250\.00/);assert.match(offerSummary(service,'price','199.90','2099-12-31',''),/199\.90/);for(const [k,v,d] of [['percent','101','2099-12-31'],['amount','301','2099-12-31'],['price','350','2099-12-31'],['price','abc','2099-12-31'],['percent','20','2020-01-01'],['percent','20','2099-02-31']])assert.throws(()=>offerSummary(service,k,v,d,''));
console.log('PASS: reminder timing/cancellation/cap, local dates, missing repeat services and promotion amounts.');

const {validClabe,authMessage}=load('account-details');
assert.equal(validClabe('032180000118359719'),true);
assert.equal(validClabe('032180000118359710'),false);
assert.equal(validClabe('123'),false);
assert.match(authMessage({code:'over_email_send_rate_limit'}),/límite temporal/);
assert.match(authMessage({message:'Email rate limit exceeded'}),/límite temporal/);
console.log('PASS: bank check digit and email-rate-limit translation.');
