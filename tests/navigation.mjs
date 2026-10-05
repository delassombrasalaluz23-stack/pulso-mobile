import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import ts from 'typescript';
const require=createRequire(import.meta.url);
// Use the installed Expo SDK's real stack router. Native views are not needed to test route state.
const {StackRouter,StackActions}=require('../node_modules/expo-router/build/react-navigation/routers/StackRouter.js');
const jsx=require('react/jsx-runtime');
const Stack=Object.assign(()=>null,{Screen:()=>null,Protected:()=>null});
const Tabs=Object.assign(()=>null,{Screen:()=>null,Protected:()=>null});
let auth;
function load(source){const module={exports:{}};const code=ts.transpileModule(source,{compilerOptions:{jsx:ts.JsxEmit.ReactJSX,module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;new Function('require','module','exports',code)(name=>{
 if(name==='react/jsx-runtime')return jsx;
 if(name==='expo-router')return {Stack,Tabs};
 if(name.endsWith('/lib/auth'))return {useAuth:()=>auth,AuthProvider:()=>null};
 if(name.endsWith('/components/ui'))return {colors:{}};
 return new Proxy({},{get:()=>()=>null});
},module,module.exports);return module.exports}
const source=fs.readFileSync('src/app/_layout.tsx','utf8');
const {Routes}=load(source+'\nexport {Routes};');
const tabLayout=load(fs.readFileSync('src/app/(tabs)/_layout.tsx','utf8')).default;
function screens(element,Navigator){const names=[];function walk(x){if(!x)return;if(Array.isArray(x)){x.forEach(walk);return}if(x.type===Navigator.Protected){if(x.props.guard)walk(x.props.children)}else if(x.type===Navigator.Screen)names.push(x.props.name);else walk(x.props?.children)}walk(element);return names}
function config(render=Routes){const tree=render();assert.equal(tree.type,Stack);const names=screens(tree,Stack);assert.ok(!tree.props.initialRouteName||names.includes(tree.props.initialRouteName),'Initial screen must exist AFTER protected routes are filtered');assert.equal(new Set(names).size,names.length);return {names,router:StackRouter({initialRouteName:tree.props.initialRouteName}),args:{routeNames:names,routeParamList:{},routeGetIdList:{},routeKeyChanges:[]}}}
const session={user:{id:'test'}};
for(const state of [{session:null,profile:null},{session,profile:null},{session,profile:{role:'client'}},{session,profile:{role:'owner'}}]){
 auth={...state,ready:true};const c=config();const initial=c.router.getInitialState(c.args);assert.equal(initial.routes[0].name,state.profile?'(tabs)':state.session?'login':'explore');assert.ok(c.names.includes('recover'));
 const recovery=c.router.getStateForAction(initial,StackActions.push('recover'),c.args);assert.equal(recovery.routes.at(-1).name,'recover');
 const back=c.router.getStateForAction(recovery,StackActions.replace(state.profile?'(tabs)':state.session?'login':'explore'),c.args);assert.equal(back.routes.at(-1).name,state.profile?'(tabs)':state.session?'login':'explore');
 if(state.profile){const names=screens(tabLayout(),Tabs);assert.equal(names[0],'index');assert.equal(names.includes('business'),state.profile.role==='owner');assert.equal(names.includes('appointments'),state.profile.role==='client');assert.equal(c.names.includes('owner/team'),state.profile.role==='owner');assert.equal(c.names.includes('shop/[id]'),state.profile.role==='client')}
}
// Signing in removes login; signing out removes tabs and falls back to login, never recovery.
auth={session:null,profile:null,ready:true};let c=config();const loggedOut=c.router.getInitialState(c.args);
auth={session,profile:{role:'client'},ready:true};c=config();const loggedIn=c.router.getStateForRouteNamesChange(loggedOut,c.args);assert.equal(loggedIn.routes[0].name,'(tabs)');
auth={session:null,profile:null,ready:true};c=config();assert.equal(c.router.getStateForRouteNamesChange(loggedIn,c.args).routes[0].name,'explore');
// Prove this regression test detects the exact bad setting shown on the user's iPhone.
const broken=load(source.replace('<Stack screenOptions=','<Stack initialRouteName="(tabs)" screenOptions=')+'\nexport {Routes};');
assert.throws(()=>config(broken.Routes),/Initial screen must exist/);
auth={session:null,profile:null,ready:false};assert.notEqual(Routes().type,Stack);
console.log('PASS: real Expo stack router boots logged out/incomplete/client/owner, opens/exits recovery, handles login/logout and catches protected initial-route regression.');
