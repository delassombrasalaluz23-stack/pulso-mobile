"""Configura el SMTP elegido por el titular. No imprime ni guarda secretos."""
import getpass,json,pathlib,re,urllib.request,urllib.error
project=input('Referencia de proyecto Supabase [zccyxxwpkxjfnixjbuwl]: ').strip() or 'zccyxxwpkxjfnixjbuwl'
if not re.fullmatch(r'[a-z0-9]{20}',project):raise SystemExit('Referencia inválida')
token=getpass.getpass('Token personal de Supabase (se oculta): ')
host=input('Servidor SMTP del proveedor: ').strip()
port=int(input('Puerto SMTP: ').strip())
user=input('Usuario SMTP: ').strip()
password=getpass.getpass('Contraseña SMTP / clave del proveedor (se oculta): ')
sender=input('Correo remitente verificado: ').strip()
if not host or not user or not password or '@' not in sender or not 1<=port<=65535:raise SystemExit('Faltan datos válidos')
root=pathlib.Path(__file__).resolve().parents[1]
payload={'external_email_enabled':True,'mailer_autoconfirm':False,'smtp_host':host,'smtp_port':port,'smtp_user':user,'smtp_pass':password,'smtp_admin_email':sender,'smtp_sender_name':'Pulso','mailer_subjects_confirmation':'Confirma tu cuenta de Pulso','mailer_subjects_recovery':'Recupera tu acceso a Pulso','mailer_templates_confirmation_content':(root/'supabase/email-templates/confirmation.html').read_text(),'mailer_templates_recovery_content':(root/'supabase/email-templates/recovery.html').read_text()}
print('Se configurará el remitente',sender,'en el proyecto',project,'y se mantendrá la verificación del correo.')
if input('Escribe CONFIGURAR para aplicar: ').strip()!='CONFIGURAR':raise SystemExit('Sin cambios')
req=urllib.request.Request('https://api.supabase.com/v1/projects/'+project+'/config/auth',data=json.dumps(payload).encode(),method='PATCH',headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
try:
 with urllib.request.urlopen(req,timeout=30) as r:print('Configuración guardada. Prueba registro y recuperación desde el teléfono; revisa entrega y spam.')
except urllib.error.HTTPError as e:raise SystemExit('No se pudo guardar. Código HTTP '+str(e.code)+'. Revisa permisos del token y datos SMTP.')
