# US.000009 - Efectos de hoja para el preview

## Resumen

Como usuario quiero aplicar efectos de hoja al preview para que cada proyecto tenga una experiencia de lectura adecuada al tipo de documentación.

## Historia de Usuario

**Como** usuario  
**quiero** escoger entre hoja blanca, color sólido, rayada, cuadriculada, microcuadriculada o pergamino  
**para** adaptar la lectura al tono del proyecto.

## Efectos

| Efecto | MVP | Notas |
| --- | --- | --- |
| Hoja blanca normal | Sí | Predeterminado neutro |
| Color sólido | Sí | Usa paleta activa |
| Rayado | Sí | Líneas finas, sin textura bitmap |
| Cuadrícula | Sí | Grid técnico |
| Microcuadrícula | Sí | Para notas densas |
| Pergamino sólido | Sí | Ligado a Leonardo Classic |
| Bordes quemados/gastados | No MVP | Solo si no impacta render |

## Criterios de Aceptación

1. El usuario puede elegir efecto de hoja global.
2. El usuario puede sobrescribir el efecto por proyecto.
3. El preview aplica el efecto sin alterar el contenido Markdown.
4. Las tablas y bloques de código siguen siendo legibles.
5. Los efectos de rayado y cuadrícula se renderizan de forma ligera.
6. Cambiar el efecto no requiere recargar el documento.
7. En MVP no se incluyen efectos que ralenticen el scroll o el render inicial.

## Decisión MVP

Los efectos deben generarse con patrones ligeros, preferiblemente mediante capacidades nativas o CSS equivalente, evitando imágenes grandes o shaders complejos.

## Matriz de Rendimiento

| Efecto | Coste esperado | Permitido MVP |
| --- | --- | --- |
| Sólido | Bajo | Sí |
| Rayado | Bajo | Sí |
| Cuadrícula | Bajo | Sí |
| Microcuadrícula | Bajo-medio | Sí, medir |
| Pergamino sólido | Bajo | Sí |
| Pergamino con bordes quemados | Medio-alto | No inicial |

## Notas Técnicas

- Los efectos no deben formar parte del archivo Markdown.
- Guardar preferencia en configuración de proyecto.
- Preparar la API visual para añadir bordes gastados más adelante sin cambiar el modelo.

