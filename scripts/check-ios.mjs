const required = [
  ['EXPO_PUBLIC_SUPABASE_URL', value => { try { return new URL(value).protocol === 'https:'; } catch { return false; } }],
  ['EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY', value => value.length > 20 && !value.startsWith('sb_secret_')],
  ['EXPO_PUBLIC_EAS_PROJECT_ID', value => /^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(value)],
];
let failures = 0;
for (const [name, valid] of required) {
  const value = process.env[name] ?? '';
  const ok = valid(value);
  console.log(ok ? 'OK: ' + name : 'PENDIENTE: ' + name);
  if (!ok) failures++;
}
if (failures) {
  console.error('No se iniciará la compilación iOS: faltan servicios o configuración válidos. Sigue PRUEBA-IPHONE.md. No pegues contraseñas en el chat.');
  process.exitCode = 1;
} else {
  console.log('Configuración básica presente. EAS comprobará la sesión, firma Apple y dispositivo registrado. Esta revisión no confirma conectividad ni despliegue del servidor.');
}
