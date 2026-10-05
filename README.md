# Pulso · Aplicación móvil · Actualización 11 · Servicios activados

Aplicación nativa Expo SDK 57 / React Native, con cuentas separadas e inmutables de
cliente y dueño. Esta entrega es para probar en iPhone mediante Expo Go. No es una
publicación en App Store ni un archivo IPA firmado. Fecha: 3 de octubre de 2026,
hora de México.

## Actualización 11 activada en Supabase

Las nuevas migraciones y los cinco servicios ya están desplegados con autorización
del titular. Se verificó la ejecución del worker programado. Ya puedes actualizar
Codespaces y abrir la aplicación con Expo Go.

El acceso administrativo está reservado para delassombrasalaluz23@gmail.com:
se activa al registrar y confirmar ese correo y completar el perfil. No existe
una cuenta creada por el asistente ni una contraseña predeterminada.

Consulta **OPERACION-11.md** para configurar Stripe, SMTP y credenciales push.
Esas conexiones siguen pendientes. Las exportaciones Android/iOS pasaron; no
se publicaron las aplicaciones en tiendas ni se realizaron cobros reales.

## Corrección de arranque

Se elimina initialRouteName dirigido a una ruta protegida. El orden de pantallas
abre login sin perfil y (tabs) con perfil. Recuperación y eliminación quedan al
final y nunca se eligen como entrada normal. Recuperación incluye Volver a Pulso,
aviso en español y pausa entre solicitudes de correo. La cuota del proveedor
sigue vigente. Pruebas con el router real del SDK verifican los cuatro estados
de inicio, entrada/salida de recuperación y cambios de sesión. No sustituyen
una prueba visual en un iPhone físico.

## Cambios de la actualización 10

- Corregida la política de carga de fotos de barberías y barberos: ahora valida
  la ruta del archivo, no el nombre comercial de la barbería.
- Acceso: Entrar a Pulso, Soy nuevo – crear cuenta y, al final en pequeño,
  Olvidé mi contraseña.
- Cuenta: nombre, teléfono, ciudad, presentación y preferencia PayPal/banco.
  El dueño puede guardar correo PayPal o datos bancarios privados para recepción.
  Son datos sin verificar: no conectan una cuenta ni activan pagos reales.
- Cerrar sesión aparece antes de Eliminar mi cuenta, al final.
- Clientes → Ver cortes y fotografías: historial de visitas completadas,
  notas y foto del resultado mediante cámara o galería, con permiso del cliente.
  Las fotos son privadas para ese cliente y su barbería.
- Ranking para clientes y dueños: Municipio, Estado y Nacional, tarjetas de
  barberías, copas dorada/plateada/bronce y posición de la barbería propia.
  No se muestra la explicación del cálculo en la aplicación.

### Registro y límite de correo: configuración pendiente

El servidor confirmó el error over_email_send_rate_limit. Se tradujo el mensaje;
no se desactivó la verificación del correo ni se cambió la cuota. Para permitir
registros regulares falta conectar un proveedor SMTP en Supabase → Authentication
→ Email → SMTP Settings. Requiere una cuenta de proveedor y sus credenciales;
no están disponibles en este proyecto. No compartir contraseñas por chat.
Documentación: https://supabase.com/docs/guides/auth/auth-smtp

## Funciones conservadas

- Barberos: Disponible / No disponible. Todos usan el horario general del local.
  Pausar un barbero impide nuevas reservas; conserva sus citas confirmadas.
- Promociones para reservas: porcentaje, cantidad de descuento o precio especial,
  corte aplicable, nombre, detalle y vigencia. Se elige una en el resumen; servidor
  recalcula total y anticipo. No se combina con recompensa; extras a precio normal.
- Reprogramar citas: cliente dentro del plazo de cancelación, o dueño. Conserva
  corte, extras, barbero, precio, duración y anticipo; verifica ocupación y vigencia
  de la promoción. Una cita confirmada no puede moverse a un barbero pausado.
- Lista de espera cuando no hay espacio para el corte sin extras. Hasta diez
  esperas por cliente. Una cancelación/reprogramación que libera espacio genera
  un aviso en Cuenta → Avisos y lista de espera. No reserva automáticamente.
- Fotos privadas de referencia desde Mis citas, visibles al cliente y al dueño de
  esa barbería; quitar o cambiar mientras la cita está activa.
- Reseñas de visitas completadas, una por cita: estrellas, comentario y fotografía
  opcionales. Nombre de pila y reseña publicados en el perfil del negocio.
- Cómo llegar abre Apple Maps o Google Maps con las coordenadas registradas.
- Panel del negocio: visitas completadas, cancelaciones, inasistencias, clientes
  que regresan, servicios más solicitados y valor de servicios simulados.
- Recuperación de contraseña desde el acceso: correo y verificación del enlace
  copiado en la app. Es un flujo para Expo Go; no requiere un dominio propio.

Se mantienen mapa, buscador por nombre, radio inicial de 5 km ajustable,
favoritas, saludo con nombre, ranking municipal/estatal/nacional, Disponible hoy,
repetir corte, recordatorios locales y recompensas por visitas. El ranking usa
una fórmula explícita de reseñas y actividad, no un modelo de IA ni ingresos reales.

## Cómo actualizar en tu Codespace (Supabase ya está activado)

1. Detén Expo en la terminal con Ctrl+C.
2. Sube el nuevo Pulso-App-Movil.zip a /workspaces/codespaces-blank y reemplaza el anterior.
3. Ejecuta:

```bash
cd /workspaces/codespaces-blank
unzip -o Pulso-App-Movil.zip
cd pulso-mobile
cp -n .env.example .env
npm ci
npm run preview:go -- --clear
```

Si Expo Go dice que el proyecto no corresponde a tu sesión, detén el servidor y
entra con la misma cuenta que usas en el iPhone:

```bash
npx expo login --username pulsobarberia
npm run preview:go -- --clear
```

Introduce tu contraseña de Expo en la terminal; no se ven los caracteres al
escribir. No compartas contraseñas por chat. Escanea el QR nuevo con el iPhone.
Codespaces debe permanecer encendido para que este modo de prueba funcione.

## Estado de Supabase

Proyecto conectado: zccyxxwpkxjfnixjbuwl. Las once migraciones de
supabase/migrations ya están aplicadas. No volver a ejecutarlas manualmente.
Los archivos son también el historial reproducible para otro proyecto vacío.
La función send-promotion ya está desplegada. Las claves del cliente son públicas;
no distribuir una clave service_role. El archivo .env real no está en este ZIP.

Tablas expuestas con RLS, funciones privilegiadas en esquema privado y wrappers
públicos con permisos limitados. Datos de reservas y clientes separados por dueño.
Las fotos de referencia usan el bucket privado appointment-media y URLs firmadas
con duración de cinco minutos; las fotos de reseñas se comparten tras publicarlas.

## Eliminar cuenta: activado con autorización del titular del proyecto

Disponible en Cuenta → Eliminar mi cuenta. Requiere contraseña actual, escribir
ELIMINAR y aceptar la confirmación final. El servidor valida al titular; no acepta
identificadores de otras cuentas enviados por el teléfono.

Borra acceso, fotos propias, reseñas, favoritas y permisos de promociones. Cancela
citas activas; si el titular es dueño, cierra su barbería y cancela sus reservas
pendientes. Conserva historial sin nombre con un identificador interno. Revoca
sesiones y bloquea tokens antiguos. No elimina cuentas de clientes al cerrar el
negocio. La migración y delete-account están desplegadas; activar esta función no
ha eliminado ninguna cuenta real. La app ya no requiere una variable adicional.

## Límites concretos del piloto

- Anticipos, penalizaciones y devoluciones son SIMULADOS. Para cobros reales falta
  conectar una cuenta de pagos, definir quién cobra/comisión, integrar webhooks,
  reserva temporal del cupo, conciliación y devoluciones. No hay cobros activados.
- Los avisos de lista de espera y cambios están en la bandeja de la aplicación;
  no se envían push con la app cerrada en esta entrega.
- Recordatorios: locales en el dispositivo, 24 horas y 1 hora antes, permiso
  opcional. Un cambio hecho desde otro teléfono se sincroniza al abrir Pulso.
- Las campañas promocionales push requieren un build con credenciales EAS/APNs;
  en Expo Go usar la bandeja. Solo reciben marketing clientes con visita completada
  que lo autorizaron; máximo dos campañas por cliente cada 24 horas.
- Los cupones enviados desde Clientes son canjeables en el local. Para descuento
  automático al reservar, publicar en Mi local → Promociones para reservas.
- Compartir llegada es voluntario, solo en primer plano durante los 20 minutos
  previos; se detiene al salir de la app y los datos caducan a los dos minutos.
- Recuperación: copia el enlace del correo manteniéndolo presionado SIN abrirlo
  previamente. Si caducó o se consumió, solicita otro. Depende de la entrega de
  correo del proyecto. Un build distribuido necesitará deep links configurados.
- Falta probar esta entrega visualmente en el iPhone del usuario. No se generó
  todavía un build firmado ni se publicó en TestFlight/App Store.

## Validación

```bash
npm run typecheck
EXPO_NO_TELEMETRY=1 npm run lint
npm test
EXPO_NO_TELEMETRY=1 npx expo export --platform ios
```

Pruebas locales de la base real en PGlite con roles/JWT simulados: separación de
cuentas, precios, duración, solapamientos, promociones, reprogramación, lista de
espera, fotos, reseñas, estadísticas, recompensas y cierre de cuentas preparado.
Pruebas de cliente: recordatorios, repetición, cálculo de descuentos y validación de CLABE. También se verifican permisos de carga, fotos privadas de cortes y preferencias personales. Pruebas de
función de eliminación con servicios simulados: autenticación, contraseña y
protección contra seleccionar otra cuenta. No envían mensajes ni borran usuarios
reales. Exportación iOS satisfactoria; no equivale a prueba física en el iPhone.

Seguridad del proyecto: el asesor mantiene el aviso previo de protección de
contraseñas filtradas desactivada. Configuración y remediación:
https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

RLS sin políticas permisivas en live_locations, location_sessions y push_deliveries
es intencional: acceso solo por funciones verificadas o servicio administrativo.

## Prueba sugerida en el teléfono

1. Dueño: pausa un barbero y comprueba desde cliente que ya no recibe reservas.
2. Publica una promoción; cliente elige corte + extra y comprueba descuento solo
   en el corte, total y anticipo calculados.
3. Reserva con fecha futura, agrega foto de referencia y cambia el horario.
4. Revisa la foto desde la agenda del dueño; otro dueño no debe verla.
5. En un día sin espacio, entra a la espera; cancela una cita de ese barbero y
   revisa la bandeja de avisos del cliente que espera.
6. Tras completar una visita, publica reseña con foto y verifica el perfil público.
7. Abre Resultados del negocio y Cómo llegar; prueba recuperar tu contraseña.
8. Si deseas probar la eliminación, crea una cuenta de prueba desechable. La eliminación es permanente.
