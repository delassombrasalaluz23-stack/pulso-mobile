# Actualización 9

Consulta README.md para instalar esta entrega y ver qué está activo.
La eliminación de cuentas ya está activada con confirmación del titular; los pagos son simulados.

# Primera prueba de Pulso en iPhone

## Estado
Código preparado y validado; todavía no hay enlace de instalación ni archivo
IPA firmado. No se debe presentar un ZIP o un bundle Hermes como instalador.
El iPhone necesita iOS 16.4 o posterior para este proyecto SDK 57.

## Servicios conectados
Supabase Pulso Barberías ya está configurado. Copiar .env.example a .env al
extraer el proyecto. Contiene solo la URL y clave publicable, sin secretos.
El registro por correo está habilitado y requiere confirmar el correo.

## A. Primera prueba dentro de Expo Go
Para revisar mapas, formularios y reservas sin generar aún una app independiente:
1. Instalar Expo Go desde App Store y crear/iniciar sesión con la cuenta Expo
   del proyecto.
2. Autenticar Expo CLI con ESA MISMA cuenta en el entorno que ejecutará Pulso.
   El acceso de Expo Go iOS exige que coincidan ambas cuentas.
   Comando local: npx expo login --browser
   La redirección localhost de ese comando funciona en la computadora donde se
   ejecuta; no enviar su URL a otra computadora esperando que la sesión se conecte.
3. Una vez configurado Supabase, ejecutar npm run preview:go.
4. Escanear el QR generado con la cámara del iPhone y abrir en Expo Go.
   El túnel es temporal y deja de funcionar si se detiene el entorno.
5. Los pagos siguen simulados; las notificaciones remotas se verifican en la
   compilación firmada, no se consideran probadas con Expo Go.

## B. App propia instalada en iPhone
Necesita cuenta Expo conectada y firma de Apple Developer para distribución.
1. Vincular el proyecto con EAS y completar EXPO_PUBLIC_EAS_PROJECT_ID.
2. Configurar variables públicas del backend en el entorno de compilación EAS.
3. Registrar el iPhone para distribución interna mediante EAS device:create,
   completar la firma Apple y usar npm run ios:preview.
4. Esperar que EAS termine y comprobar el resultado antes de compartir el enlace
   de instalación. No existe todavía un enlace ni QR de distribución en esta entrega.
5. Para TestFlight: generar un build de tienda, configurar App Store Connect,
   cargarlo, esperar el procesamiento y habilitar al probador. No llamar
   “TestFlight” a un enlace de distribución interna.

La falta de sesión de Expo y firma Apple impide completar
el paso B desde el estado actual. Instalar Expo Go por sí solo tampoco conecta
el entorno de desarrollo.

## Recorrido de aceptación en el teléfono
- Permitir/denegar GPS; mover el mapa y localizar una barbería registrada.
- Dueño: publicar local, dirección/pin, foto, barbero, corte y agregado con precios.
- Cliente: elegir corte + agregado; comprobar total, duración y anticipo simulado.
- Reservar, volver a abrir la app y confirmar persistencia.
- Intentar reservar el mismo barbero a la misma hora desde otra cuenta.
- Completar una visita y verificar que aparece solo en clientes de su local.
- Dar/revocar consentimiento de promociones.
- Compartir ubicación solo en los 20 minutos previos; revocar y salir de la app.
- Comprobar todo con otro dueño para verificar aislamiento entre negocios.

## Referencias
https://docs.expo.dev/get-started/start-developing/
https://docs.expo.dev/build/internal-distribution/
https://docs.expo.dev/versions/v57.0.0/
