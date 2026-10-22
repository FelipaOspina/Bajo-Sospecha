# Guía para colaborar en "Bajo Sospecha"

Esta guía es para la persona que va a trabajar en el juego junto a Felipe. No hace falta saber programar para seguirla: cada paso dice qué abrir y qué pulsar. Está pensada para Windows.

El código vive en GitHub, en el repositorio **FelipaOspina/Bajo-Sospecha**. Ahí está todo: el juego (hecho con Godot 4.3) y el servidor (hecho con Node.js). La carpeta importante es `claude/`.

---

## 1. Acepta la invitación de GitHub

1. Si no tienes cuenta, créala gratis en <https://github.com/signup>.
2. Pásale a Felipe tu **nombre de usuario de GitHub** (no tu correo).
3. Te llegará un correo de GitHub que dice "invited you to collaborate on FelipaOspina/Bajo-Sospecha". Pulsa **View invitation** y luego **Accept invitation**.
   - Si no ves el correo, entra a <https://github.com/FelipaOspina/Bajo-Sospecha/invitations> con tu sesión iniciada.
4. El repositorio es público, así que cualquiera puede verlo. La invitación es lo que te permite **subir** cambios.

## 2. Instala los programas

Instálalos en este orden, aceptando las opciones que vienen por defecto:

| Programa | Para qué sirve | Dónde se descarga |
|---|---|---|
| **GitHub Desktop** | Descargar el proyecto y subir tus cambios sin usar comandos | <https://desktop.github.com> |
| **Node.js 22 LTS** | Ejecutar el servidor del juego en tu PC | <https://nodejs.org> (botón "LTS") |
| **Godot 4.3 (estándar)** | Abrir y probar el juego | <https://godotengine.org/download/archive/4.3-stable/> |

Sobre Godot:
- Descarga la versión **Standard**, no la ".NET". Tiene que ser la **4.3**: con otra versión el proyecto puede dar errores.
- Godot no se instala: es un `.zip`. Descomprímelo en una carpeta fija, por ejemplo `C:\Godot\`. Dentro queda un archivo como `Godot_v4.3-stable_win64.exe`.

Al abrir GitHub Desktop por primera vez, inicia sesión con tu cuenta de GitHub (**File > Options > Accounts > Sign in**).

## 3. Descarga el proyecto (clonar)

1. En GitHub Desktop: **File > Clone repository**.
2. En la pestaña **GitHub.com**, elige **FelipaOspina/Bajo-Sospecha**.
3. En **Local path** elige dónde guardarlo, por ejemplo `C:\Proyectos\Bajo-Sospecha`.
4. Pulsa **Clone** y espera a que termine. Pesa unos cientos de MB.

A partir de aquí, "la carpeta del proyecto" es la que elegiste, y el juego está en su subcarpeta `claude\`.

## 4. Arranca el servidor en tu PC

El juego necesita un servidor para las partidas. Para probar, lo arrancas en tu propio PC:

1. Abre la carpeta del proyecto y entra en `claude\`.
2. Haz doble clic en **`iniciar_servidor.bat`**.
3. La primera vez tarda un poco, porque instala lo que necesita. Sabrás que funciona cuando la ventana negra diga:
   `Servidor escuchando en el puerto 7777`
4. **Deja esa ventana abierta** mientras juegas. Para apagar el servidor, ciérrala.

Si Windows muestra un aviso de seguridad o del firewall, pulsa **Más información > Ejecutar de todas formas** o **Permitir acceso**.

## 5. Abre el juego en Godot

**Para editar** (escenas, scripts, arte):
1. Abre `Godot_v4.3-stable_win64.exe`.
2. Pulsa **Importar** y elige el archivo `claude\client\project.godot` dentro de la carpeta del proyecto.
3. Pulsa **Importar y editar**. La primera vez tarda unos minutos mientras prepara las texturas y los modelos.

**Para jugar varias ventanas a la vez contra tu servidor local:**
1. Haz clic derecho en `claude\abrir_clientes.bat` y elige **Editar**.
2. Cambia la línea `set "GODOT=D:\Godot\Godot_v4.3-stable_win64.exe"` por la ruta donde tú pusiste Godot, por ejemplo `set "GODOT=C:\Godot\Godot_v4.3-stable_win64.exe"`. Guarda.
   - No subas este cambio a GitHub, porque en el PC de Felipe la ruta es otra. En GitHub Desktop, haz clic derecho sobre ese archivo y elige **Discard changes** antes de subir, o simplemente no lo marques.
3. Con el servidor ya encendido (paso 4), abre una ventana de comandos en la carpeta `claude\` y escribe:
   `abrir_clientes.bat 2 PRUEBA`
   Se abren 2 ventanas del juego que entran juntas a la sala **PRUEBA**. Puedes poner hasta 4.

Si una ventana no se conecta, revisa que la del servidor siga abierta.

## 6. Conecta tu propio Claude al proyecto

Así tu Claude puede leer y modificar el mismo código.

1. Crea tu cuenta en <https://claude.ai>. Para que Claude trabaje con código necesitas un plan de pago (Pro o superior).
2. Conecta tu GitHub en <https://claude.ai/connect-github> y acepta los permisos.
3. En claude.ai, crea un **Proyecto** nuevo (por ejemplo "Bajo Sospecha").
4. En la configuración del proyecto, en **Repositorios**, añade **FelipaOspina/Bajo-Sospecha**.
   - Si el repositorio no aparece en la lista, avisa a Felipe: tiene que comprobar que la app de Claude en su GitHub tiene acceso a ese repositorio.
5. En las **instrucciones del proyecto**, pega este texto para que tu Claude siga las mismas reglas:

```
Proyecto: juego multijugador de deducción "Bajo Sospecha" (cliente Godot 4.3 en claude/client, servidor Node.js/TypeScript en claude/server).
Responde en español.
Nunca hagas push directo a main: main despliega el servidor de producción en Render.
Trabaja siempre en una rama nueva y abre un Pull Request hacia main para que Felipe lo revise.
No subas node_modules, dist, .godot, archivos .aab/.apk, claves (.keystore) ni contraseñas.
Regla de diseño: los roles nunca se revelan por skins, colores, nombres ni HUD. Los 12 animales son gratis; la tienda solo vende cosméticos.
```

## 7. Cómo trabajar sin pisarse

Las reglas importantes:

1. **Nunca subas cambios directamente a `main`.** Lo que entra en `main` se publica en el servidor real.
2. **Antes de empezar, actualiza.** En GitHub Desktop pulsa **Fetch origin** y luego **Pull origin**. Cierra Godot antes de hacerlo.
3. **Crea una rama para cada tarea.** En GitHub Desktop: **Current branch > New branch**, con un nombre que diga qué haces, por ejemplo `nueva-pista-cocina`.
4. **Guarda tus cambios (commit).** Cuando algo funcione, en GitHub Desktop escribe un resumen corto abajo a la izquierda y pulsa **Commit to nueva-pista-cocina**.
5. **Súbelos y pide revisión.** Pulsa **Publish branch** (o **Push origin**) y luego **Create Pull Request**. Se abre GitHub en el navegador: describe qué cambiaste y pulsa **Create pull request**.
6. **Felipe revisa y fusiona.** Cuando lo apruebe, vuelve a `main` en GitHub Desktop y haz **Pull** para tener la versión nueva.

Para evitar conflictos:
- Avisaos de qué escena o archivo está tocando cada uno. Dos personas editando la misma escena (`.tscn`) a la vez casi siempre generan un conflicto difícil de arreglar.
- Haz ramas pequeñas y frecuentes, mejor que una enorme al final.
- Si GitHub Desktop avisa de un conflicto, no fuerces nada: pídele ayuda a tu Claude o a Felipe.

## 8. Qué no se debe subir nunca

- Carpetas `node_modules`, `dist` y `.godot` (se generan solas).
- Archivos de Android `.aab` o `.apk`, y claves de firma `.keystore`.
- Contraseñas, tokens o archivos `.env`.
- Tu cambio de ruta en `abrir_clientes.bat`.

---

## Para Felipe: cómo invitar a la otra persona

1. Abre <https://github.com/FelipaOspina/Bajo-Sospecha/settings/access>.
2. Pulsa **Add people**, escribe su usuario de GitHub y confirma.
3. Opcional, pero recomendable: en **Settings > Branches > Add branch protection rule**, protege `main` y marca **Require a pull request before merging**. Así nadie, ni siquiera un Claude, puede subir directo a producción por error.
