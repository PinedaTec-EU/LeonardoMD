# Form capabilities showcase

Open `service-request.mdlr` to start in **Fill form** with synthetic answers, or
open `service-request.mdlf` and select **Fill form** to try an empty template.
Both files are self-contained and use the same v1 definition and Markdown body.
They do not depend on the background resource tracked in
[#201](https://github.com/PinedaTec-EU/LeonardoMD/issues/201).

| Capability | Field / exercise |
| --- | --- |
| Text, required, length bounds | Nombre; try a single character |
| Email, required | Correo; try `invalid`, then correct it |
| URL, optional | Sitio web; try a URL without a scheme |
| Date | Fecha deseada; choose a real calendar date |
| Number, bounds, default | Horas estimadas; 1–40, defaults to 4 |
| Select with labels/default | Prioridad; Normal/Urgente |
| Multiline, max length, placeholder | Detalles; write several lines |
| Checkbox, boolean default | Solicitar copia por correo |
| Switch appearance, boolean default | Avisos de seguimiento |
| Pattern and custom diagnostic | Código del proyecto; use `ABC-123` |
| Read-only and default | Referencia, fixed `SOL-024` |
| Repeated field | Nombre appears again in Confirmación |
| Help and independent properties | Click or keyboard-activate `?` beside any field |

Check that repeated names update together, help remains available on Referencia,
and the sidebar distinguishes editability from requiredness. Save a draft,
reopen it and export PDF: values should remain. Preview and Split retain the
same labels, controls and responsive rows as Fill form, with inputs and help
disabled. PDF and print omit generated form chrome. Invalid answers may be
saved as drafts.

There are no calculations in this example. A fixed read-only reference is not a
calculated value. Numeric and text formulas are deferred to
[#203](https://github.com/PinedaTec-EU/LeonardoMD/issues/203).
