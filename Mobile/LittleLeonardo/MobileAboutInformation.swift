import SwiftUI
import LeonardoRender

struct MobileAboutInformation: View {
    enum Topic: String {
        case help = "Ayuda", privacy = "Privacidad", licenses = "Licencias"
    }
    let topic: Topic
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch topic {
                case .help:
                    section("Identifica tus proyectos / Project identity", "Recibido de otro equipo / Received from another device identifica un proyecto que comparte otro equipo: muestra el icono de proyecto y una marca de red, también sin conexión. En el Mac de origen aparece como Compartido desde este equipo / Shared from this device. Archivo de recuperación / Recovery archive conserva solo el icono de proyecto y sigue siendo de solo lectura. A received project is already shared by its source; it does not need a second sharing badge.")
                    section("Prueba la demo sin conexión", "En Biblioteca abre el proyecto Demo y elige Demo-es.mdlr o Demo-en.mdlr. Puedes completar los campos, consultar su ayuda y pulsar Guardar sin conectar con un Mac. Desliza un proyecto y pulsa Eliminar para quitarlo solo de este dispositivo. Recupera Demo en Ajustes de sincronización; conserva las respuestas guardadas y solo reaparece automáticamente con contenido de demo nuevo. Restablecer pide confirmación y solo borra las del idioma elegido.")
                    section("Conecta tu Mac", "En LeonardoMD activa el servicio para compartir. En Little Leonardo pulsa Conectar, escanea el QR o introduce IP y puerto. Comprueba el código en ambos equipos y autoriza los proyectos desde el Mac.")
                    section("Consulta sin conexión", "Abre un proyecto y después un documento. La lectura y la vista de texto no modifican el original. Las copias descargadas están disponibles sin conexión. La sincronización automática solo funciona mientras la app está activa.")
                    section("Dibuja una rúbrica", "Acepta la solicitud del Mac. Gira a horizontal para ampliar el lienzo o pulsa Ampliar lienzo. Al volver a vertical recuperas la página y el dibujo. Deshacer, Limpiar y Vista previa no envían nada; Enviar rúbrica requiere tu acción explícita.")
                case .privacy:
                    section("Datos en este dispositivo", "Los documentos descargados, las respuestas de las demos y los borradores de rúbrica se guardan localmente. Las prácticas son copias editables separadas de los proyectos sincronizados y no se envían al Mac. Desinstalar la app elimina esas copias. Las credenciales de conexión se conservan en el llavero del dispositivo.")
                    section("Intercambio con tu Mac", "El Mac autoriza los proyectos que puedes consultar. Solo se envía la rúbrica al pulsar Enviar rúbrica. La cámara se utiliza para leer el QR de conexión cuando autorizas su uso.")
                    section("Acceso retirado", "Cuando el dispositivo vuelve a contactar con un Mac que ha retirado su autorización, se bloquea el acceso y se elimina la copia autorizada. Sin conexión no se puede garantizar la eliminación inmediata.")
                case .licenses:
                    Text(contents(Bundle.main.url(forResource: "LICENSE", withExtension: "txt", subdirectory: "Legal"))).textSelection(.enabled)
                    Divider()
                    Text(contents(MarkdownLegalResources.noticesURL)).textSelection(.enabled)
                    ForEach(MarkdownLegalResources.licenseURLs, id: \.self) { url in
                        NavigationLink(url.lastPathComponent) {
                            ScrollView { Text(contents(url)).textSelection(.enabled).padding(24) }
                                .classicSurface().navigationTitle(url.lastPathComponent).navigationBarTitleDisplayMode(.inline)
                        }
                    }
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.classicSurface().navigationTitle(topic.rawValue).navigationBarTitleDisplayMode(.inline)
    }
    private func section(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold()).foregroundStyle(MobileClassic.heading)
            Text(content)
        }
    }
    private func contents(_ url: URL?) -> String {
        guard let url else { return "Recurso no disponible" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "Recurso no disponible"
    }
}
