# Pulso 0.3: APK de prueba

El mapa usa Leaflet 1.9.4 empaquetado dentro de la app y mapas de OpenStreetMap por HTTPS. No requiere una clave de Google Maps ni activar facturación. No se descargan mapas sin conexión ni áreas por adelantado. Se conserva la caché HTTP del WebView, un User-Agent que identifica Pulso y el crédito visible de OpenStreetMap. El proveedor es de disponibilidad voluntaria: este piloto no implica capacidad ilimitada ni garantía para un lanzamiento masivo.

Conserva los tres usos: explorar barberías (ubicación voluntaria, búsqueda y radio), marcar el local y ver clientes que comparten su llegada. Los nombres se insertan como texto, no como HTML. La ubicación del teléfono la obtiene Expo tras pedir permiso; el mapa no pide permisos por su cuenta.

El perfil `preview` de EAS produce una APK instalable, sin Metro ni Codespaces abiertos. Incluye solo los dos valores públicos de conexión del cliente, nunca una clave administrativa. Se conserva el ID de proyecto Expo existente.

## Generar

En el directorio del proyecto:

```sh
npm ci
npm run typecheck
npm run lint
npx eas-cli@latest build --platform android --profile preview
```

Usar exclusivamente la cuota gratuita disponible de Expo. No aceptar una mejora de plan o compra de créditos. Si pregunta si deseas generar un nuevo Android Keystore y todavía no hay uno, responder Y; EAS conserva la clave para futuras actualizaciones. No elegir iOS ni enviar a tiendas. Al terminar, abrir el enlace de instalación en Android, descargar el APK e instalarlo. Si ofrece instalar en un emulador en la computadora, responder N.

## Verificación en dispositivo pendiente

- Abrir sin Codespaces encendido; cargar catálogo y mapa con conexión a Internet.
- Permitir/negar ubicación; centrar, mover, ampliar y tocar un marcador; revisar radio de 5 km y búsqueda.
- Editar ubicación del local; guardar, reabrir y verificar el marcador.
- Probar la llegada compartida voluntaria en su ventana de 20 minutos y comprobar que desaparezca al caducar.
- Cambiar entre primer plano y segundo plano y recuperar el mapa.

El código pasó TypeScript, lint y exportación Android; eso no sustituye la compilación nativa ni estas pruebas. Los cobros reales, credenciales push y correo personalizado siguen requiriendo su configuración correspondiente. Esta actualización no activa cobros.

Para regenerar Leaflet tras cambios deliberados de versión: `npm run bundle:map`. Su licencia se incluye en `src/lib/leaflet-bundle.ts`.
