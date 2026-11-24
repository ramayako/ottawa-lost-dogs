# Lost & Found Dogs Ottawa: cómo ponerla en línea

El sitio son archivos estáticos (GitHub Pages, gratis) más una base de datos gratuita (Supabase). Mientras `config.js` esté vacío, el sitio funciona en **modo vista previa**, con perros de ejemplo, y no guarda nada.

## 1. Crear la base de datos (unos 10 minutos)
1. Entra en https://supabase.com y crea una cuenta gratis (activa la verificación en dos pasos).
2. Pulsa **New project**. Ponle de nombre `ottawa-lost-dogs`, elige una contraseña fuerte (guárdala) y la región **Canada (Central)**.
3. Cuando esté listo, ve a **SQL Editor → New query**, pega todo el contenido de `supabase-setup.sql` y pulsa **Run**. Debe decir "Success".

## 2. Conectar el sitio
1. En Supabase ve a **Project Settings → API**.
2. Abre `config.js` y pega:
   - **Project URL** en `supabaseUrl`
   - la clave **anon public** en `anonKey` (es pública y segura de publicar)
   - en `siteUrl` pon `https://ramayako.github.io/ottawa-lost-dogs/`
3. ⚠️ **Nunca** pegues la clave `service_role` en ningún archivo: esa es la llave maestra.

## 3. Publicar en GitHub Pages
1. En GitHub crea un repositorio **público** llamado `ottawa-lost-dogs`.
2. Pulsa **Add file → Upload files** y sube todos los archivos de esta carpeta (menos este LEEME, si quieres).
3. Ve a **Settings → Pages**, y en *Source* elige `main` / `root`. A los pocos minutos el sitio estará en https://ramayako.github.io/ottawa-lost-dogs/
4. Si usas otro nombre de repositorio o un dominio propio, cambia esa dirección en `index.html` (canonical y og:*), `robots.txt`, `sitemap.xml` y `llms.txt`.

## 4. Métricas
- Abre `https://ramayako.github.io/ottawa-lost-dogs/stats.html`. Verás visitas, visitantes, de dónde llegan, reportes nuevos por día, perros reunidos, números de teléfono consultados y reportes por barrio. Esta página no aparece en Google.
- También puedes pedirle a Claude que te dé las métricas, o programar un resumen semanal por correo.

## 5. Moderación
- Para ocultar un reporte falso: en Supabase ve a **Table Editor → reports**, busca el reporte y pon `hidden` en `true`.
- Cada persona recibe un **código privado** al publicar, con el que puede marcar su perro como reunido o borrar su reporte.

## Seguridad y privacidad (ya incluidas)
- **Teléfonos protegidos:** no aparecen en la lista ni en los datos abiertos. Solo se muestra uno cuando alguien pulsa "Show phone number", con un límite de 12 por hora y 40 por día por conexión, así no se pueden copiar todos.
- **Nadie puede modificar ni leer la tabla directamente:** solo funciones controladas (publicar, ver un contacto, marcar como reunido con código, registrar una visita).
- **Límites contra spam:** máximo 6 reportes por hora por conexión, un campo trampa para robots, límites de tamaño en todos los campos, y fotos solo de imagen y de máximo 1 MB.
- **Sin servidor propio que atacar:** el sitio es estático. Lleva además una política de seguridad de contenido que bloquea scripts externos.
- **Lo que te toca a ti:** activa la verificación en dos pasos en GitHub y en Supabase, y no compartas la clave `service_role` ni la contraseña de la base de datos.
- **Mejora opcional:** si algún día llega mucho spam, se puede añadir una verificación "no soy un robot" (Cloudflare Turnstile, gratis).
