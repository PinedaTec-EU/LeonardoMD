# US.000010 - Aplicación macOS nativa con estilo glass

## Resumen

Como usuario de macOS quiero una aplicación nativa, moderna y rápida, con estética glass coherente con macOS, para que LeonardoMD se sienta integrada en el sistema.

## Historia de Usuario

**Como** usuario de macOS  
**quiero** que LeonardoMD sea una app nativa con estilo glass  
**para** tener una experiencia fluida, moderna y consistente con mi escritorio.

## Alcance MVP

| Capacidad | MVP |
| --- | --- |
| App macOS instalable | Sí |
| Ventana principal nativa | Sí |
| Sidebar glass/translucent | Sí |
| Atajos macOS | Sí |
| Menú de aplicación macOS | Sí |
| Drag and drop de archivos | Deseable |
| iCloud document integration | No |

## Criterios de Aceptación

1. La app se abre como aplicación macOS estándar.
2. La ventana principal usa patrones visuales compatibles con macOS moderno.
3. El sidebar puede usar translucidez/material glass cuando el sistema lo permita.
4. La UI respeta modo claro/oscuro del sistema, salvo paleta explícita del proyecto.
5. Los atajos `Cmd+O`, `Cmd+S`, `Cmd+N`, `Cmd+W` funcionan de forma esperada.
6. El rendimiento visual se mantiene fluido al redimensionar ventana y hacer scroll.
7. El diseño no depende de una web remota ni de servicios externos.

## Consideración Tecnológica

| Opción | Ventajas | Riesgos |
| --- | --- | --- |
| Swift/SwiftUI | Mejor integración macOS, arranque rápido, UI nativa | Menor reutilización directa con .NET |
| .NET MAUI/Mac Catalyst | C# y reutilización futura | Experiencia macOS menos nativa, rendimiento a validar |
| Avalonia UI | C#, multiplataforma, desktop fuerte | Menos nativo en detalles macOS |
| Tauri + TypeScript/Rust | App ligera, UI web potente | Stack adicional y renderer web |
| Electron + TypeScript | Ecosistema enorme | Arranque/memoria peor para requisito de velocidad |

## Recomendación Inicial

Para el requisito de rendimiento y feeling nativo en macOS, **Swift/SwiftUI** es la opción más fuerte para el shell inicial. Para proteger el futuro multiplataforma, conviene aislar el dominio en librerías portables o servicios internos con contratos claros. Si el objetivo prioritario es maximizar C#, **Avalonia** merece un spike temprano antes que asumir MAUI.

## Spike Necesario

Crear una prueba técnica comparando:

| Métrica | SwiftUI | Avalonia | Tauri |
| --- | --- | --- | --- |
| Cold start | Medir | Medir | Medir |
| Render Markdown | Medir | Medir | Medir |
| Mermaid | Medir | Medir | Medir |
| Memoria inicial | Medir | Medir | Medir |
| Integración macOS | Evaluar | Evaluar | Evaluar |
