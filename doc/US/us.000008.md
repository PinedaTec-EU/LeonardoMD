# US.000008 - Paleta Leonardo Classic inspirada en Vitruvio

## Resumen

Como usuario quiero una paleta antigua inspirada en Leonardo da Vinci y la lámina del Hombre de Vitruvio para leer documentos con aspecto de pergamino, tinta negra y titulares rojo sangre.

## Historia de Usuario

**Como** usuario  
**quiero** usar la paleta Leonardo Classic  
**para** dar a mis documentos una estética antigua, cálida y reconocible sin sacrificar legibilidad.

## Alcance MVP

| Elemento | MVP |
| --- | --- |
| Fondo pergamino sólido | Sí |
| Texto principal negro | Sí |
| Titulares rojo sangre | Sí |
| Acento óxido | Sí |
| Bordes sutiles envejecidos | Sí, sin textura pesada |
| Bordes quemados realistas | No MVP |
| Extracción desde imagen original | No MVP |

## Propuesta Visual

| Token | Color inicial | Uso |
| --- | --- | --- |
| `paper` | `#E7D6AD` | Fondo de hoja |
| `ink` | `#11100D` | Texto principal |
| `bloodRed` | `#7A1114` | H1, H2, alertas editoriales |
| `oxide` | `#8C3F22` | Links, acentos y selección |
| `agedLine` | `#9C8052` | Líneas, tablas y separadores |
| `shadow` | `#3A2D1D` | Sombras suaves |

## Criterios de Aceptación

1. La paleta aparece como opción predefinida.
2. El preview Markdown usa fondo pergamino y texto principal negro.
3. Los encabezados principales usan rojo sangre.
4. Los links y acentos usan óxido.
5. Las tablas, citas y bloques de código son legibles dentro de la paleta.
6. La app mantiene contraste suficiente para lectura prolongada.
7. Los efectos visuales de envejecido no reducen de forma perceptible el rendimiento.

## Reglas de Estilo

- La estética debe ser antigua, no caricaturesca.
- Evitar texturas bitmap pesadas en MVP.
- Los bordes quemados o gastados quedan como efecto opcional post-MVP si las pruebas de rendimiento lo permiten.
- El documento debe seguir siendo cómodo para specs técnicas largas.

## Riesgos

| Riesgo | Mitigación |
| --- | --- |
| Baja legibilidad por exceso de estilo | Contraste validado y modo lectura limpio |
| Render pesado por texturas | MVP con colores sólidos y CSS/nativo ligero |
| Apariencia demasiado temática | Controles sobrios y uso de acentos limitado |

