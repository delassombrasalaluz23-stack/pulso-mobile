import fs from 'node:fs';
import ts from 'typescript';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),jsx=require('react/jsx-runtime');
const source=fs.readFileSync('src/app/shop/[id].tsx','utf8');
const ast=ts.createSourceFile('shop.tsx',source,ts.ScriptTarget.Latest,true,ts.ScriptKind.TSX),names=[];
function visit(n){if(ts.isVariableDeclaration(n)&&ts.isArrayBindingPattern(n.name)&&n.initializer&&ts.isCallExpression(n.initializer)&&n.initializer.expression.getText(ast)==='useState')names.push(n.name.elements[0].getText(ast));ts.forEachChild(n,visit)}visit(ast);
let i=0;const state={};const empty=()=>{};
const shop={id:'shop',name:'Prueba',address:'Calle',municipality:'Monterrey',timezone:'America/Monterrey',days:[1,2],open_hour:9,close_hour:20,deposit_percent:30,cancel_hours:12,description:''};
Object.assign(state,{shop,services:[{id:'cut',kind:'cut',name:'Corte',price_cents:20000,duration_minutes:30}],barbers:[{id:'barber',name:'Ana'}],cut:'cut',barber:'barber',slots:[{starts_at:'2026-10-10T18:00:00Z',ends_at:'2026-10-10T18:30:00Z'}]});
const react={useState:init=>{const key=names[i++];if(!(key in state))state[key]=typeof init==='function'?init():init;return [state[key],v=>{state[key]=typeof v==='function'?v(state[key]):v}]},useRef:value=>({current:value}),useEffect:empty};
const module={exports:{}};
new Function('require','module','exports',ts.transpileModule(source,{compilerOptions:{jsx:ts.JsxEmit.ReactJSX,module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText)(name=>{
 if(name==='react')return react;if(name==='react/jsx-runtime')return jsx;
 if(name==='expo-crypto')return {randomUUID:()=> 'request'};
 if(name==='expo-router')return {router:{push:empty,replace:empty},useLocalSearchParams:()=>({id:'shop'})};
 if(name.endsWith('/lib/auth'))return {useAuth:()=>({session:{user:{id:'client'}},profile:{role:'client'}})};
 if(name.endsWith('/lib/clock'))return {useClock:()=>Date.parse('2026-10-08T00:00:00Z')};
 if(name.endsWith('/lib/booking-helpers'))return {localDay:()=> '2026-10-08',nextDay:d=>d};
 if(name.endsWith('/lib/types'))return {money:n=>'$'+n/100,quote:()=>({total:20000,deposit:6000,minutes:30}),offerDiscount:()=>0};
 return new Proxy({__esModule:true,default:name,s:{},colors:{}},{get:(o,k)=>k in o?o[k]:String(k)});
},module,module.exports);
global.requestAnimationFrame=f=>f();
function render(){i=0;return module.exports.default()}
function all(root,predicate){const out=[];function walk(e){if(!e)return;if(Array.isArray(e)){e.forEach(walk);return}if(typeof e!=='object')return;if(predicate(e))out.push(e);walk(e.props?.children);walk(e.props?.footer)}walk(root);return out}
let tree=render();const screen=all(tree,x=>x.type==='Screen')[0];assert.ok(screen.props.footer,'persistent booking footer');
all(tree,x=>x.type==='Button'&&x.props.title==='Continuar')[0].props.onPress();assert.equal(state.section,'date');assert.equal(state.reviewOpen,false);
state.slot='2026-10-10T18:00:00Z';tree=render();all(tree,x=>x.type==='Button'&&x.props.title==='Revisar reserva')[0].props.onPress();assert.equal(state.reviewOpen,true);
assert.equal(all(render(),x=>x.type==='Modal')[0].props.visible,true);
const confirm=all(render(),x=>x.type==='Button'&&x.props.title==='Reservar con anticipo de prueba')[0];assert.equal(confirm.props.disabled,true,'terms acceptance still required');
state.accept=true;assert.equal(all(render(),x=>x.type==='Button'&&x.props.title==='Reservar con anticipo de prueba')[0].props.disabled,false);
state.slotBusy=true;assert.equal(all(render(),x=>x.type==='Button'&&x.props.title==='Reservar con anticipo de prueba')[0].props.disabled,true,'availability recheck blocks confirmation');
state.tab='team';tree=render();assert.equal(all(tree,x=>x.props?.step==='01').length,0,'service selection is hidden on team tab');assert.ok(all(tree,x=>x.type==='Screen')[0].props.footer,'booking remains reachable from team');
console.log('PASS UI: sticky summary, missing time guidance, review before payment, consent gate, availability gate, profile tabs.');
