# Pulso 11 · Preparación para Android y iPhone

## Estado de esta entrega

Código implementado y comprobado localmente. Con autorización expresa del titular,
las migraciones nuevas ya están aplicadas en Supabase. Los cinco servicios están
desplegados y el worker programado respondió HTTP 200. Ya se puede actualizar
el proyecto de Codespaces con este ZIP.

El correo delassombrasalaluz23@gmail.com aún no tiene cuenta en Pulso. Su acceso
administrativo quedó reservado: después de registrar y confirmar ese correo,
al completar el perfil se activa la membresía administrativa. No se creó una
contraseña ni se omitió la verificación de correo.

No se realizaron cobros reales ni se conectaron credenciales Stripe, SMTP o
APNs/FCM. Estas conexiones siguen pendientes. No se verificó un negocio ni se
suspendió una cuenta durante el despliegue.

## Qué contiene

- Mapa inicial sin cuenta y perfiles públicos con cortes, precios, equipo y fotos.
  Para reservar o guardar favoritas hay que iniciar sesión. No expone clientes,
  datos bancarios, citas ni identificadores del propietario al visitante.
- Código de llegada de seis dígitos visible solo al cliente. El dueño lo introduce
  desde 20 minutos antes de la cita hasta dos horas después del final previsto.
  Cinco errores bloquean intentos durante 15 minutos. No se permite completar
  una visita sin confirmar llegada. Las versiones antiguas deben actualizarse.
- Ayuda por cita y reportes de negocio, reseña o fotografía. Hasta diez solicitudes
  por usuario al día; historial, estado y respuesta privada en Ayuda y reportes.
- Panel administrativo con búsqueda y páginas de 50 elementos: negocios,
  cuentas, reportes con contexto, respuestas, cancelación con solicitud de
  devolución, suspensión/restablecimiento y retirada de contenido.
- Verificación solo administrativa con motivo obligatorio y auditoría.
  Cambiar nombre, dirección, coordenadas o propietario retira el distintivo.
  La suspensión bloquea nuevas operaciones; no cancela automáticamente citas.
- Stripe Connect: alta del negocio en el proveedor y depósito en su cuenta bancaria;
  Checkout alojado para el anticipo con tarjeta, recibo y estado de devolución.
  No se cobra comisión adicional de Pulso en este código; las tarifas del
  proveedor siguen aplicando. PayPal continúa siendo una preferencia guardada,
  no una integración de cobro ni un monedero conectado.
- Reservas pendientes de pago con retención de 35 minutos. Checkout caduca a los
  34 minutos; al caducar el cupo se libera. Se exige al menos 40 minutos antes de
  la cita. El servidor recalcula precio y aplica una promoción o recompensa.
  Solo una confirmación verificada del proveedor confirma el pago. Un pago tardío
  cuyo cupo se perdió queda para devolución, no genera una reserva doble.
- Cancelación a tiempo o por el negocio: devolución íntegra del anticipo solicitada
  al proveedor. Cancelación fuera de plazo/no asistencia: retención del anticipo,
  sin cargo adicional. El saldo restante se paga en el local. El comprobante
  del proveedor no constituye una factura fiscal emitida por Pulso.
- Cola del servidor para avisos de reservas/cambios y recordatorios de 24 h y 1 h.
  Worker con reintentos, bloqueo temporal de trabajos, consulta de recibos y
  retirada de tokens inválidos. Las entregas al teléfono dependen de APNs/FCM,
  permisos y conectividad; no son una garantía de recepción.
- Retirada de archivos reportados mediante Storage API; el código no borra
  metadatos internos de Storage por SQL. Se conserva el registro administrativo.

## Supabase: activado con autorización del titular

Proyecto: zccyxxwpkxjfnixjbuwl. Las once migraciones del historial están aplicadas.
No volver a ejecutarlas ni usar db push para repetir este historial.

- pulso_launch_foundation: nuevas tablas, funciones, permisos y estados.
- pulso_booking_worker_schedule: pg_cron/pg_net y worker cada minuto.
- pulso_reserved_administrator: acceso reservado al correo indicado por el titular,
  activado únicamente después de que Supabase confirme la dirección y exista el perfil.

Servicios activos: create-checkout, payment-onboarding, payment-webhook,
payment-return y booking-worker. Validan sesión, firma Stripe o token privado según
su función. payment-return es informativa y nunca confirma pagos por sí sola.

El worker respondió HTTP 200 con cero trabajos pendientes. Esto verifica su
funcionamiento en el servidor, no la entrega push a un teléfono sin configurar.
Los asesores no detectaron errores de seguridad; los avisos informativos de RLS
sin políticas en tablas privadas son intencionales: se accede solo mediante
funciones autorizadas. Continúa el aviso previo de protección de contraseñas
filtradas desactivada (enlace al final).

## Correo real: falta proveedor SMTP

El código no puede eliminar el límite del servicio de prueba. Se mantiene la
verificación de direcciones; no se confirma artificialmente a los usuarios.

Con una cuenta de correo transaccional y remitente/dominio verificado:

- Configurar SMTP en Authentication → Email/SMTP de Supabase.
- Usar las plantillas de supabase/email-templates para confirmación y recuperación.
  Recuperación admite código o enlace dentro de Pulso.
- Opcional: ejecutar `python3 scripts/configurar-correo.py` en Codespaces.
  Solicita los valores de forma interactiva, oculta los secretos y no los guarda.
  Requiere un token personal de Supabase autorizado para configurar el proyecto.
- Probar un registro y una recuperación reales; revisar bandeja, spam y registros.
  Ajustar cuotas con el proveedor, sin desactivar la confirmación.

No introducir claves SMTP en variables EXPO_PUBLIC ni enviar secretos por chat.
Guía oficial: https://supabase.com/docs/guides/auth/auth-smtp

## Pagos: falta cuenta y credenciales de Stripe

1. Crear/configurar la plataforma Stripe Connect del titular y revisar su
   disponibilidad para las cuentas mexicanas que se vayan a conectar.
2. Registrar STRIPE_SECRET_KEY en los secretos del servidor Supabase, nunca en
   el .env de la aplicación.
3. Configurar un webhook de plataforma a payment-webhook para
   checkout.session.completed y checkout.session.async_payment_succeeded.
   Guardar su firma en STRIPE_WEBHOOK_SECRET.
4. Configurar eventos de cuentas conectadas account.updated al mismo endpoint
   y guardar esa firma en STRIPE_CONNECT_WEBHOOK_SECRET.
5. Dueño → Cuenta → Conectar cobros de mi barbería: completar el alta y revisión
   del proveedor. charges_enabled y payouts_enabled deben ser verdaderos.
6. Antes de habilitar dinero real, probar en Stripe test: éxito, rechazo,
   abandono, evento repetido, cupo ocupado, cancelación, devolución y cierre de
   cuenta con reserva pagada. El comprobante muestra si Stripe está en prueba.
7. Pasar a claves/webhooks/cuentas de producción y repetir una prueba controlada
   autorizada. Esta entrega no ha probado transferencias o devoluciones reales.

Las reservas de negocios no conectados siguen explícitamente en modo de prueba.
Las devoluciones fallidas requieren revisión de soporte; el worker conserva su
estado y no finge éxito. Un saldo insuficiente, disputa o devolución externa al
flujo de Pulso requiere conciliación del operador con el proveedor.
Guías: https://docs.stripe.com/connect/destination-charges
https://docs.stripe.com/webhooks

## Avisos: faltan credenciales y builds firmados

- Vincular EXPO_PUBLIC_EAS_PROJECT_ID al proyecto de la cuenta pulsobarberia.
- Configurar APNs para Apple y FCM v1 para Android en EAS. Android también necesita
  google-services.json como archivo seguro y la clave de Maps restringida al
  paquete com.pulso.barberias y los certificados de firma correspondientes.
- Si se protege Expo Push, configurar EXPO_ACCESS_TOKEN solo en Supabase.
- Compilar con EAS y activar avisos desde Cuenta en cada teléfono real.
  Los avisos remotos de Android no funcionan en Expo Go.
- Mantener acceso al worker solo por su token privado; no exponerlo en la app.
- Probar reserva, cambio y recordatorio con la aplicación cerrada en ambos sistemas.
  Los recordatorios locales siguen disponibles; si se habilitan junto a los
  remotos pueden existir dos avisos. Para la prueba de push, desactivar los locales.

## Android y Apple

Ambas plataformas usan este mismo proyecto React Native. Hay perfiles EAS para
APK interno Android, compilación iOS y producción para las dos tiendas.

```bash
npm run android:preview
npm run ios:preview
# Solo cuando se decida preparar las tiendas:
npm run build:stores
```

Esto no implica publicación. Faltan firma/credenciales y pruebas físicas. No se
crearon IPA/APK firmados ni fichas de App Store o Google Play en esta entrega.

## Validación ejecutada

- TypeScript y lint.
- Router real de Expo: invitado, perfil incompleto, cliente, dueño y recuperación.
- Base local PGlite: historial completo de migraciones, aislamiento entre negocios,
  códigos y bloqueo, administración, suspensión, verificación, reportes,
  reservas pendientes, conciliación, idempotencia y devolución.
- Firma Stripe: mensaje válido, alterado y vencido.
- Deno check para las cuatro funciones operativas.
- Exportaciones de JavaScript/Hermes para iOS y Android.

No equivalen a pruebas en un iPhone/Android físico ni contra Stripe/SMTP reales.
Aviso previo del asesor Supabase: protección de contraseñas filtradas desactivada.
Remediación: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
