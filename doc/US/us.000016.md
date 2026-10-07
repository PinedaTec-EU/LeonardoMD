# US.000016 - Visor individual y modo foco

## Resumen

Abrir un documento Markdown desde Finder o un diálogo sin proyecto y sin mostrar carpetas; concentrarse en un documento de proyecto ocultando sus paneles.

## Criterios de aceptación

1. Abrir un archivo individual no crea ni adjunta un proyecto.
2. El visor utiliza preferencias globales y resuelve imágenes y enlaces relativos desde el documento.
3. Lectura es el modo inicial; edición y vista dividida están disponibles.
4. Abrir la carpeta como proyecto es una acción explícita.
5. Foco oculta navegación e inspector conservando proyecto, documento y cambios.
6. Salir de foco restaura los paneles solicitados.
7. Navegar o cerrar espera el guardado y protege la edición ante conflictos externos.

## Extensiones en MVP

Mermaid y matemáticas se activan voluntariamente, globalmente o por proyecto. Desactivadas no cargan ni ejecutan sus motores. Al desactivarlas se destruye el contexto que las ejecutaba. Los diagramas habilitados se procesan cuando son visibles. PDF se exporta desde el documento renderizado.

## Referencia

Implementación y validación: [GitHub issue #1](https://github.com/PinedaTec-EU/LeonardoMD/issues/1).
