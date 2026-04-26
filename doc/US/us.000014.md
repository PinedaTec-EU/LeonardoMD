# US.000014 - Configuración portable de proyecto

## Resumen

Como usuario quiero que cada proyecto guarde su configuración portable para mantener preferencias visuales, Git y comportamiento aunque cambie de máquina.

## Historia de Usuario

**Como** usuario  
**quiero** que la configuración del proyecto viaje con la carpeta  
**para** conservar paleta, efecto de hoja y preferencias básicas al sincronizar con Git.

## Archivo Propuesto

Ruta:

```text
.leonardomd/project.json
```

Ejemplo:

```json
{
  "schemaVersion": 1,
  "name": "Mi Proyecto",
  "palette": "leonardo-classic",
  "paperEffect": "parchment",
  "git": {
    "enabled": true,
    "syncMode": "manual"
  },
  "markdown": {
    "defaultMode": "preview"
  }
}
```

## Criterios de Aceptación

1. Al crear un proyecto, la app puede crear `.leonardomd/project.json`.
2. Si el archivo no existe, la app usa valores por defecto.
3. Si el archivo existe, la app aplica sus preferencias.
4. El formato es legible y versionable en Git.
5. El archivo no contiene secretos.
6. La app tolera campos desconocidos para compatibilidad futura.
7. La app valida `schemaVersion`.

## Reglas

- La configuración local privada de usuario no debe mezclarse con la configuración compartida del proyecto.
- Preferencias compartibles: paleta del proyecto, efecto de hoja, nombre del proyecto, modo Git.
- Preferencias privadas: ventana, último archivo abierto, zoom personal, credenciales.

## Notas Técnicas

- Usar JSON por simplicidad y compatibilidad.
- Definir migraciones por `schemaVersion`.
- Añadir `.leonardomd/local.json` a `.gitignore` si se necesita estado privado.
