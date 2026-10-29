# Gráfico Vega-Lite

Activa **Preferencias → Extensiones → Gráficos (Vega-Lite)** para ver el
gráfico. La especificación contiene los datos inline, por lo que el documento
se puede abrir sin conexión.

````vega-lite
{
  "$schema": "https://vega.github.io/schema/vega-lite/v6.json",
  "width": 480,
  "height": 260,
  "data": {
    "values": [
      {"month": "Enero", "visits": 120},
      {"month": "Febrero", "visits": 185},
      {"month": "Marzo", "visits": 164},
      {"month": "Abril", "visits": 212}
    ]
  },
  "mark": {"type": "bar", "cornerRadiusEnd": 4},
  "encoding": {
    "x": {"field": "month", "type": "ordinal", "sort": null, "title": "Mes"},
    "y": {"field": "visits", "type": "quantitative", "title": "Visitas"},
    "color": {"value": "#2B5C8A"},
    "tooltip": [
      {"field": "month", "type": "ordinal"},
      {"field": "visits", "type": "quantitative"}
    ]
  },
  "width": "container",
  "height": 260
}
````

El modo inicial es estático: los tooltips y las selecciones interactivas se
omiten al renderizar en LeonardoMD y la exportación PDF conserva el SVG.
