# Pulso 0.4 — pruebas previas al lanzamiento

## Disponible en el código

- Estadísticas semanales, lunes a domingo en la zona de la barbería, con semanas anteriores.
- Excel .xlsx con seis hojas: resumen, días, barberos, servicios, citas y definiciones. Dos gráficos nativos de Excel, sin enviarlo a un servicio externo.
- Cifras de anticipos reales separadas de pruebas. El valor de los servicios no prueba el pago del saldo en el local.
- Aviso de retraso de 5 a 30 minutos, sin cambiar el horario ni las condiciones de la cita.
- Propuesta de cambio que requiere aceptación del destinatario. La reserva original sigue vigente; al aceptar se comprueba otra vez la disponibilidad.
- Selección de reserva guardada por cuenta y barbería durante 24 horas. Solicitud pendiente persistente e identificador idempotente para recuperar un intento tras una interrupción.
- Lista de preparación del negocio, perfil público y enlace/QR `pulso://visit/…` para dispositivos con Pulso instalada. No hay enlace público de descarga ni universal link todavía.
- Panel operativo para administrador: devoluciones con error/pendientes, avisos con error/demorados, reservas por liberar y cambios pendientes. Se actualiza mientras se consulta el panel.
- Reenvío de confirmación de correo, verificación por código si la plantilla lo incluye y prueba de avisos con la aplicación cerrada.

## Configuración externa pendiente

Estas funciones no sustituyen las credenciales de los proveedores. No se activaron planes de pago.

1. **Stripe**: no había cuentas de barberías habilitadas para cobrar al revisar esta actualización. Requiere clave secreta y webhook en los secretos de Supabase y alta de Stripe Connect del negocio. Nunca poner una clave secreta en variables EXPO_PUBLIC ni en Git. El flujo existente de Checkout, comprobante, devolución e inasistencia está implementado, pero falta una prueba real completa en el entorno de pruebas de Stripe.
2. **Correo**: configurar un proveedor SMTP autorizado en Supabase > Authentication > SMTP. Tener una dirección Gmail no configura SMTP. No se dispone de sus credenciales; el límite del proveedor predeterminado no se corrige solamente con código. Probar registro con correo externo, confirmación y recuperación.
3. **Avisos Android**: configurar FCM v1 en EAS y el archivo de Google Services del mismo proyecto Firebase. Registrar el teléfono desde Cuenta y solicitar la prueba con la app cerrada. La cola y el worker están implementados; un dispositivo registrado no prueba entrega. Apple queda para una etapa posterior.

## Cómo revisar la actualización

1. Generar una nueva APK con el perfil preview. No basta reiniciar Metro.
2. Abrir una cuenta de barbería y comprobar Estadísticas y Excel semanal. Elegir la semana actual y una vacía, guardar el archivo desde el menú de compartir y abrirlo en Excel.
3. Proponer un cambio desde cliente: la hora original no cambia. Aceptar desde barbería. Repetir rechazando, venciendo y con un horario ocupado.
4. En la hora anterior a una cita, enviar un retraso. Revisar el aviso en la cuenta de la barbería.
5. Cortar la conexión mientras se reserva, volver a abrir Pulso y usar Recuperar reserva. Verificar que existe una sola cita.
6. Abrir el QR en otro teléfono que tenga la APK instalada.

La migración requiere la app actualizada para reprogramar. No se cambia el mapa ni el orden de navegación de cliente o barbería.

Verificaciones automatizadas: tipos, lint, exportación JavaScript Android/iOS, permisos y transacciones en Postgres de pruebas, totales y estructura Excel. La APK y la entrega de notificaciones se deben comprobar en un teléfono físico.
