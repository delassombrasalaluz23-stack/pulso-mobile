#!/usr/bin/env python3
"""Initial Stripe setup. Secrets stay in memory and Supabase, never in source files."""
import getpass,hashlib,hmac,json,sys,time,urllib.request,urllib.parse,urllib.error
PROJECT='zccyxxwpkxjfnixjbuwl'
BASE='https://'+PROJECT+'.supabase.co/functions/v1/payment-webhook'
def request(url,token=None,data=None,method=None,headers=None,form=False):
    h=dict(headers or {})
    if token:h['Authorization']='Bearer '+token
    if data is not None:
        data=(urllib.parse.urlencode(data) if form else json.dumps(data)).encode()
        h['Content-Type']='application/x-www-form-urlencoded' if form else 'application/json'
    req=urllib.request.Request(url,data=data,headers=h,method=method or ('POST' if data is not None else 'GET'))
    try:
        with urllib.request.urlopen(req,timeout=35) as r:return json.load(r)
    except urllib.error.HTTPError as e:raise RuntimeError('El servicio respondió HTTP '+str(e.code)+'. Revisa permisos y configuración en su panel; no compartas tus claves.') from None
    except urllib.error.URLError:raise RuntimeError('No se pudo conectar al servicio. Revisa tu conexión.') from None

def main():
    if not sys.stdin.isatty():raise RuntimeError('Abre una terminal interactiva para introducir las claves sin mostrarlas.')
    print('Conectar Stripe a Pulso. No crea cargos ni contrata planes. No pegues estas claves en el chat.')
    print('Stripe: https://dashboard.stripe.com/apikeys')
    key=getpass.getpass('Clave secreta Stripe (no se verá al pegar): ').strip()
    if not key.startswith(('sk_test_','sk_live_')):raise RuntimeError('Se necesita una clave secreta Stripe válida.')
    live=key.startswith('sk_live_')
    print('Modo: '+('DINERO REAL' if live else 'PRUEBAS SIN DINERO REAL'))
    print('Supabase: https://supabase.com/dashboard/account/tokens')
    token=getpass.getpass('Token de acceso Supabase con permisos de secretos (no se verá): ').strip()
    if not token:raise RuntimeError('Falta el token de Supabase.')
    secrets_url='https://api.supabase.com/v1/projects/'+PROJECT+'/secrets'
    existing=request(secrets_url,token)
    if any(x.get('name') in ('STRIPE_SECRET_KEY','STRIPE_WEBHOOK_SECRET','STRIPE_CONNECT_WEBHOOK_SECRET') for x in existing):raise RuntimeError('Ya existe configuración Stripe. Se conserva sin sobrescribir. Usa Verificar conexión de cobros en Pulso antes de cambiarla.')
    account=request('https://api.stripe.com/v1/account',key)
    if live and not account.get('charges_enabled'):raise RuntimeError('Stripe todavía no habilita cobros reales de tu cuenta. Completa la verificación en su panel.')
    old=request('https://api.stripe.com/v1/webhook_endpoints?limit=100',key)
    if old.get('has_more') or any(e.get('url')==BASE for e in old.get('data',[])):raise RuntimeError('Hay webhooks que requieren revisión antes de crear otros. No se cambió tu configuración.')
    print('Se crearán dos conexiones de notificaciones Stripe y se guardarán tres secretos en el servidor de Pulso.')
    expected='CONECTAR COBROS REALES' if live else 'CONECTAR PRUEBAS'
    if input('Escribe '+expected+' para continuar: ').strip()!=expected:raise RuntimeError('Cancelado sin cambios.')
    created=[];saved=False
    try:
        for connect in (False,True):
            events=['account.updated'] if connect else ['checkout.session.completed','checkout.session.async_payment_succeeded']
            params={'url':BASE,'description':'Pulso '+('cuentas receptoras' if connect else 'anticipos'),'connect':str(connect).lower()}
            params.update({'enabled_events['+str(i)+']':e for i,e in enumerate(events)})
            endpoint=request('https://api.stripe.com/v1/webhook_endpoints',key,params,form=True)
            created.append(endpoint)
        payload=[{'name':'STRIPE_SECRET_KEY','value':key},{'name':'STRIPE_WEBHOOK_SECRET','value':created[0]['secret']},{'name':'STRIPE_CONNECT_WEBHOOK_SECRET','value':created[1]['secret']}]
        request(secrets_url,token,payload);saved=True
        print('Conexión guardada. Ahora abre Pulso > Mi cuenta > Anticipos y cuenta receptora y completa los datos bancarios de la barbería.')
        # Non-financial probe validates the installed signature handler only.
        raw=json.dumps({'id':'pulso_connection_check','type':'pulso.connection_check','data':{'object':{}}}).encode();stamp=str(int(time.time()))
        signature=hmac.new(created[0]['secret'].encode(),stamp.encode()+b'.'+raw,hashlib.sha256).hexdigest()
        req=urllib.request.Request(BASE,data=raw,method='POST',headers={'Content-Type':'application/json','Stripe-Signature':'t='+stamp+',v1='+signature})
        try:
            with urllib.request.urlopen(req,timeout=30) as r:print('Firma del receptor verificada.' if r.status==200 else 'Falta verificar el receptor.')
        except (urllib.error.URLError,urllib.error.HTTPError):print('Secretos guardados; falta verificar la recepción tras su propagación.')
        print('Esto NO certifica un cobro. Falta probar reserva, pago, devolución e inasistencia desde la app y comprobarlos en Stripe.')
        if not live:print('Antes de pasar a dinero real hay que revisar la configuración y las cuentas de prueba. No cambies solo la clave.')
    except Exception:
        if not saved:
            print('La configuración no se confirmó. No repitas ni borres claves: revisa primero los secretos de Supabase y los webhooks de Stripe.')
            print('Webhooks creados para identificar en el panel: '+', '.join(e['id'] for e in created))
        raise
if __name__=='__main__':
    try:main()
    except (RuntimeError,KeyboardInterrupt,EOFError) as e:sys.exit(str(e) or 'Cancelado.')
