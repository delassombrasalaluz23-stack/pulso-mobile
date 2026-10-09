// Read-only: never prints secret values and never creates a charge or purchase.
import fs from 'node:fs';
const configured=Boolean(process.env.EXPO_PUBLIC_SUPABASE_URL&&process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
console.log('Conexión pública de Supabase:',configured?'configurada':'falta configurar');
console.log('Archivo Android de Firebase:',process.env.GOOGLE_SERVICES_JSON&&fs.existsSync(process.env.GOOGLE_SERVICES_JSON)?'disponible':'validar en el entorno preview de EAS');
console.log('Antes de habilitar cobros: conectar Stripe en Cuenta, completar requisitos del negocio y probar pago, cancelación, devolución e inasistencia en modo test.');
console.log('Antes de abrir registros: configurar SMTP en Supabase y probar confirmación y recuperación con un correo externo. No desactivar la confirmación para sortear el límite.');
console.log('Antes de confiar en avisos: Cuenta > Activar avisos > Probar aviso con la app cerrada. Validar FCM v1 de Android en EAS.');
console.log('No se ha realizado ningún cobro ni se ha activado un plan de pago.');
